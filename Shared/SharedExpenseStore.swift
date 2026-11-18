//
//  SharedExpenseStore.swift
//  Kuruş / Cent — Yerel depolama (App Group) + iCloud anahtar-değer eşitlemesi
//
//  Hedefler: App + Widget Extension
//
//  • Sunucu yok, hesap yok: tüm veri cihazdaki App Group UserDefaults'ta durur.
//  • Aynı anlık görüntü NSUbiquitousKeyValueStore ile kullanıcının kendi iCloud hesabına yansır.
//  • Çakışmada "son yazan kazanır" (updatedAt). Widget ve Kestirmeler aynı App Group'u okur/yazar.
//

import Foundation
import Observation
import WidgetKit

@MainActor
@Observable
final class SharedExpenseStore {

    static let shared = SharedExpenseStore()

    nonisolated static let appGroupID = "group.com.kurus.app"
    nonisolated static let snapshotKey = "kurus.snapshot.v1"

    private(set) var snapshot: KurusSnapshot

    var expenses: [Expense] { snapshot.expenses }
    var cards: [PaymentCard] { snapshot.cards }
    var monthlyBudget: Decimal { snapshot.monthlyBudget }
    var hasCompletedOnboarding: Bool { snapshot.hasCompletedOnboarding }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let cloud = NSUbiquitousKeyValueStore.default
    @ObservationIgnored private var cloudObserver: NSObjectProtocol?

    private init() {
        let defaults = UserDefaults(suiteName: Self.appGroupID) ?? .standard
        self.defaults = defaults
        self.snapshot = Self.decode(defaults.data(forKey: Self.snapshotKey)) ?? KurusSnapshot()
        startCloudSync()
    }

    // MARK: - Widget / Intent için eşzamansız okuma

    /// Ana aktöre ihtiyaç duymadan (TimelineProvider içinden) App Group'tan okur.
    nonisolated static func loadSnapshot() -> KurusSnapshot {
        decode(UserDefaults(suiteName: appGroupID)?.data(forKey: snapshotKey)) ?? KurusSnapshot()
    }

    nonisolated static func decode(_ data: Data?) -> KurusSnapshot? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(KurusSnapshot.self, from: data)
    }

    // MARK: - Sorgular

    func card(id: String) -> PaymentCard? {
        snapshot.cards.first { $0.id == id }
    }

    /// Ayrıştırıcıya giden kullanıcı kart adları: takma adlar ve banka sözlüğünde olmayan banka
    /// adları ("Nkolay"). Sözlükteki bankalar ("Bonus", "Chase") zaten tanındığı için eklenmez.
    var userCardNames: [String] {
        var seen = Set<String>()
        var names: [String] = []
        for card in snapshot.cards {
            var candidates: [String] = []
            if let nickname = card.nickname?.trimmingCharacters(in: .whitespacesAndNewlines), !nickname.isEmpty {
                candidates.append(nickname)
            }
            if !card.isBankUnknown, ExpenseParser.knownBankName(for: card.bankName) == nil {
                candidates.append(card.bankName)
            }
            for name in candidates where seen.insert(name.kurusNormalized).inserted {
                names.append(name)
            }
        }
        return names
    }

    /// Bu kayıt yeni bir kart oluşturur mu? (Ücretsiz planın kart sınırı için; veri değişmez.)
    func wouldCreateCard(for parsed: ParsedExpense) -> Bool {
        var probe = snapshot
        let before = probe.cards.count
        _ = Self.resolveCard(for: parsed, in: &probe)
        return probe.cards.count > before
    }

    // MARK: - Yazma işlemleri

    /// Ayrıştırılmış metni kaydeder. Taksitliyse her ay için bir kayıt üretir (1/3, 2/3, 3/3).
    @discardableResult
    func add(_ parsed: ParsedExpense, at date: Date = .now, isDemo: Bool = false) -> [Expense] {
        guard let total = parsed.amount, total > 0 else { return [] }
        // "dün" / "yesterday" → bir gün önce
        let date = parsed.dayOffset == 0
            ? date
            : (Ledger.calendar.date(byAdding: .day, value: parsed.dayOffset, to: date) ?? date)
        var created: [Expense] = []
        commit { s in
            if !isDemo {
                // İlk gerçek giriş demoyu da temizler (örnek kartlar dahil)
                Self.removeDemoData(from: &s)
                s.hasCompletedOnboarding = true
            }
            let cardID = Self.resolveCard(for: parsed, in: &s, isDemo: isDemo)
            created = Self.makeExpenses(from: parsed, total: total, cardID: cardID, date: date, isDemo: isDemo)
            s.expenses.append(contentsOf: created)
        }
        return created
    }

    /// Siler; taksitli ise tüm taksit grubunu kaldırır. Geri alma için silinenleri döndürür.
    @discardableResult
    func delete(_ expense: Expense) -> [Expense] {
        var removed: [Expense] = []
        commit { s in
            if let group = expense.installment?.groupID {
                removed = s.expenses.filter { $0.installment?.groupID == group }
            } else {
                removed = s.expenses.filter { $0.id == expense.id }
            }
            let ids = Set(removed.map(\.id))
            s.expenses.removeAll { ids.contains($0.id) }
        }
        return removed
    }

    func restore(_ items: [Expense]) {
        guard !items.isEmpty else { return }
        commit { s in
            let existing = Set(s.expenses.map(\.id))
            s.expenses.append(contentsOf: items.filter { !existing.contains($0.id) })
        }
    }

    /// Kategoriyi değiştirir. Abonelik seçilen gider tekrarlayan olur (Yaklaşanlar'a ve gelecek aya
    /// yansır); Abonelik'ten başka kategoriye geçen gider tekrarlayan olmaktan çıkar.
    /// Taksitler zaten her ay ayrı kayıt olduğundan tekrarlayan yapılmaz.
    func setCategory(_ category: ExpenseCategory, for expense: Expense) {
        commit { s in
            for index in s.expenses.indices {
                let item = s.expenses[index]
                let sameGroup = expense.installment != nil && item.installment?.groupID == expense.installment?.groupID
                if item.id == expense.id || sameGroup {
                    let previous = item.category
                    s.expenses[index].category = category
                    guard item.installment == nil else { continue }
                    if category == .subscription {
                        s.expenses[index].isRecurring = true
                    } else if previous == .subscription {
                        s.expenses[index].isRecurring = false
                    }
                }
            }
        }
    }

    func setBudget(_ value: Decimal) {
        guard value > 0 else { return }
        commit { $0.monthlyBudget = value.rounded(0) }
    }

    /// Kartın adını ve hesap kesim gününü tek seferde, yalnızca kimliğe (id) göre günceller.
    func updateCard(id: String, nickname: String, statementDay: Int?) {
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        commit { s in
            guard let index = s.cards.firstIndex(where: { $0.id == id }) else { return }
            s.cards[index].nickname = trimmed.isEmpty ? nil : trimmed
            s.cards[index].statementDay = statementDay
        }
    }

    enum CardAddOutcome: Equatable { case added, updated }
    enum CardAddError: Error, Equatable { case invalidName, invalidLast4, duplicate, limitReached }

    /// Ayarlar → "Kart Ekle". Ad, ayrıştırıcının kart sözlüğüne girer ("Kahve 85 nkolay").
    /// • Ad bilinen bir bankaysa kanonik adı kullanılır ("garanti" → "Garanti BBVA").
    /// • Aynı son 4 haneli, bankası bilinmeyen kart (SMS'ten gelen "Kart ••1234") bu adı kazanır.
    /// • Aynı adlı, son 4 hanesi olmayan kart son 4 haneyi kazanır. Aynısı varsa `.duplicate`.
    /// • `allowNewCard == false` (ücretsiz plan sınırı) ve yeni kart gerekiyorsa `.limitReached`.
    func addCard(name: String, last4: String?, allowNewCard: Bool) -> Result<CardAddOutcome, CardAddError> {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.kurusNormalized
        guard (2...24).contains(trimmed.count), trimmed.contains(where: \.isLetter),
              !ExpenseParser.genericCardNames.contains(normalized) else { return .failure(.invalidName) }

        let digits = last4?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard digits.isEmpty || (digits.count == 4 && digits.allSatisfy { $0.isASCII && $0.isNumber }) else {
            return .failure(.invalidLast4)
        }
        let last4 = digits.isEmpty ? nil : digits
        let bankName = ExpenseParser.knownBankName(for: trimmed) ?? trimmed

        func sameName(_ card: PaymentCard) -> Bool {
            card.bankName.kurusNormalized == bankName.kurusNormalized
                || card.nickname?.kurusNormalized == normalized
        }

        if let last4, let index = snapshot.cards.firstIndex(where: { $0.last4 == last4 && $0.isBankUnknown && $0.nickname == nil }) {
            commit { $0.cards[index].bankName = bankName }
            return .success(.updated)
        }
        if let existing = snapshot.cards.firstIndex(where: sameName) {
            let card = snapshot.cards[existing]
            if card.last4 == last4 || last4 == nil { return .failure(.duplicate) }
            if card.last4 == nil {
                commit { $0.cards[existing].last4 = last4 }
                return .success(.updated)
            }
            // Aynı bankanın başka bir kartı (farklı son 4 hane) → yeni kart.
        }
        guard allowNewCard else { return .failure(.limitReached) }
        commit { s in
            s.cards.append(PaymentCard(id: UUID().uuidString, last4: last4, bankName: bankName))
        }
        return .success(.added)
    }

    /// Ücretsiz plan sınırı için gerçek (demo olmayan) kart sayısı
    var realCardCount: Int { snapshot.cards.filter { $0.isDemo != true }.count }

    /// Kartı kimliğiyle siler. SwiftData'daki .nullify / .cascade karşılığı:
    /// `keepExpenses == true`  → harcamalar "Nakit / Banka Kartı"na aktarılır (cardID = nil)
    /// `keepExpenses == false` → karta bağlı harcamalar da silinir
    /// Hiçbir harcama, var olmayan bir karta bağlı (yetim) kalmaz.
    func deleteCard(id: String, keepExpenses: Bool) {
        commit { s in
            if keepExpenses {
                for index in s.expenses.indices where s.expenses[index].cardID == id {
                    s.expenses[index].cardID = nil
                }
            } else {
                s.expenses.removeAll { $0.cardID == id }
            }
            s.cards.removeAll { $0.id == id }
        }
    }

    /// Karta bağlı harcama sayısı (silme onayında gösterilir)
    func expenseCount(forCard id: String) -> Int {
        snapshot.expenses.filter { $0.cardID == id }.count
    }

    func renameCard(id: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        commit { s in
            guard let index = s.cards.firstIndex(where: { $0.id == id }) else { return }
            s.cards[index].nickname = trimmed.isEmpty ? nil : trimmed
        }
    }

    func setStatementDay(_ day: Int?, forCard id: String) {
        commit { s in
            guard let index = s.cards.firstIndex(where: { $0.id == id }) else { return }
            s.cards[index].statementDay = day
        }
    }

    /// Açılış demosunu temizler ve kullanıcıyı boş bir sayfayla başlatır.
    func clearDemo() {
        commit { s in
            Self.removeDemoData(from: &s)
            s.hasCompletedOnboarding = true
        }
    }

    /// Demonun bütün izleri: örnek harcamalar ve demo sırasında oluşan kartlar (ör. "Yapı Kredi").
    private static func removeDemoData(from s: inout KurusSnapshot) {
        s.expenses.removeAll { $0.isDemo }
        s.cards.removeAll { $0.isDemo == true }
    }

    /// "Tüm Verileri Sıfırla": harcamalar, kartlar ve bütçe bu cihazdan VE iCloud'dan silinir.
    /// Boş anlık görüntü en yeni `updatedAt` ile yazılır; iCloud'a bağlı diğer cihazlar da
    /// "son yazan kazanır" kuralıyla boş duruma geçer. Pro satın alımı Apple'da olduğu için etkilenmez.
    func resetAllData() {
        var empty = KurusSnapshot()
        empty.hasCompletedOnboarding = true   // açılış demosu yeniden oynamasın
        empty.updatedAt = .now
        snapshot = empty
        persist()
    }

    /// Uygulama öne geldiğinde: widget/Kestirme yazdıysa diskteki yeni veriyi al, iCloud'u eşitle.
    func reloadFromDisk() {
        if let disk = Self.decode(defaults.data(forKey: Self.snapshotKey)), disk.updatedAt > snapshot.updatedAt {
            snapshot = disk
        }
        pullFromCloud()
    }

    // MARK: - Kart havuzu

    /// Aynı kartla (son 4 hane + uyumlu banka) gelen harcamalar o kartın havuzunda birleşir.
    /// Kartlar adla değil kimlikle (id) tutulur; yeni kartlar UUID alır.
    private static func resolveCard(for parsed: ParsedExpense, in s: inout KurusSnapshot, isDemo: Bool = false) -> String? {
        if parsed.isCash { return nil }

        // Kullanıcının kendi kart adı ("Kahve 85 nkolay"): takma ada ya da banka adına göre bulunur.
        var parsed = parsed
        if let name = parsed.userCardName {
            let key = name.kurusNormalized
            if let index = s.cards.firstIndex(where: { card in
                (card.nickname?.kurusNormalized == key || card.bankName.kurusNormalized == key)
                    && (parsed.cardLast4 == nil || card.last4 == nil || card.last4 == parsed.cardLast4)
            }) {
                if let last4 = parsed.cardLast4, s.cards[index].last4 == nil {
                    s.cards[index].last4 = last4
                }
                return s.cards[index].id
            }
            // Kart bu arada silindiyse ad, banka adı olarak kullanılır.
            if parsed.bankName == nil { parsed.bankName = name }
        }

        // Banka adı biri tarafında bilinmiyorsa uyumlu sayılır; ikisi de biliniyorsa aynı olmalı.
        // Böylece "Bonus ••4532" ile "World ••4532" iki ayrı kart olarak kalır.
        func sameBank(_ card: PaymentCard) -> Bool {
            guard let bank = parsed.bankName, !card.isBankUnknown else { return true }
            return card.bankName.kurusNormalized == bank.kurusNormalized
        }

        if let last4 = parsed.cardLast4 {
            if let index = s.cards.firstIndex(where: { $0.last4 == last4 && sameBank($0) }) {
                if let bank = parsed.bankName, s.cards[index].isBankUnknown {
                    s.cards[index].bankName = bank
                }
                return s.cards[index].id
            }
            // Daha önce yalnızca adıyla bilinen kart ("Kahve 145 bonus") şimdi son 4 hanesini kazanır.
            if let bank = parsed.bankName,
               let index = s.cards.firstIndex(where: { $0.last4 == nil && $0.bankName.kurusNormalized == bank.kurusNormalized }) {
                s.cards[index].last4 = last4
                return s.cards[index].id
            }
            let card = PaymentCard(id: UUID().uuidString, last4: last4, bankName: parsed.bankName ?? "", isDemo: isDemo ? true : nil)
            s.cards.append(card)
            return card.id
        }

        if let bank = parsed.bankName {
            if let existing = s.cards.first(where: { $0.bankName.kurusNormalized == bank.kurusNormalized }) {
                return existing.id
            }
            let card = PaymentCard(id: UUID().uuidString, last4: nil, bankName: bank, isDemo: isDemo ? true : nil)
            s.cards.append(card)
            return card.id
        }

        return nil
    }

    private static func makeExpenses(
        from parsed: ParsedExpense,
        total: Decimal,
        cardID: String?,
        date: Date,
        isDemo: Bool
    ) -> [Expense] {
        let count = max(1, parsed.installmentCount)
        let total = total.rounded(2)
        let per = (total / Decimal(count)).rounded(2)
        let group = UUID()
        let cal = Ledger.calendar

        return (0..<count).map { i in
            let due = cal.date(byAdding: .month, value: i, to: date) ?? date
            // Son taksit kuruş farkını üstlenir: 100 / 3 → 33,33 + 33,33 + 33,34
            let amount = (i == count - 1) ? total - per * Decimal(count - 1) : per
            return Expense(
                title: parsed.title,
                amount: amount,
                date: due,
                category: parsed.category,
                brandID: parsed.brandID,
                cardID: cardID,
                installment: count > 1 ? InstallmentInfo(groupID: group, index: i + 1, count: count, total: total) : nil,
                isRecurring: parsed.isRecurring,
                isDemo: isDemo,
                note: parsed.rawText,
                currencyCode: parsed.currencyCode
            )
        }
    }

    // MARK: - Kalıcılık

    private func commit(_ change: (inout KurusSnapshot) -> Void) {
        // Widget ya da Kestirme bu arada yazmış olabilir: her zaman en taze veri üzerine uygula.
        var next = snapshot
        if let disk = Self.decode(defaults.data(forKey: Self.snapshotKey)), disk.updatedAt > next.updatedAt {
            next = disk
        }
        change(&next)
        next.updatedAt = .now
        snapshot = next
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Self.snapshotKey)
        pushToCloud(data)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - iCloud anahtar-değer eşitlemesi

    private func startCloudSync() {
        cloudObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloud,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.pullFromCloud()
            }
        }
        cloud.synchronize()
        pullFromCloud()
    }

    private func pullFromCloud() {
        guard let remote = Self.decode(cloud.data(forKey: Self.snapshotKey)) else {
            if snapshot.updatedAt > .distantPast, let data = try? JSONEncoder().encode(snapshot) {
                pushToCloud(data)
            }
            return
        }
        if remote.updatedAt > snapshot.updatedAt {
            snapshot = remote
            if let data = try? JSONEncoder().encode(remote) {
                defaults.set(data, forKey: Self.snapshotKey)
            }
            WidgetCenter.shared.reloadAllTimelines()
        } else if snapshot.updatedAt > remote.updatedAt, let data = try? JSONEncoder().encode(snapshot) {
            pushToCloud(data)
        }
    }

    /// iCloud KVS kotası 1 MB'tır. Sınıra yaklaşılırsa buluta son 12 ay gönderilir; cihazdaki veri eksiksiz kalır.
    private func pushToCloud(_ data: Data) {
        var payload = data
        if payload.count > 900_000 {
            var trimmed = snapshot
            let cutoff = Ledger.calendar.date(byAdding: .month, value: -12, to: .now) ?? .distantPast
            trimmed.expenses.removeAll { $0.date < cutoff }
            payload = (try? JSONEncoder().encode(trimmed)) ?? Data()
        }
        guard !payload.isEmpty, payload.count < 1_000_000 else { return }
        cloud.set(payload, forKey: Self.snapshotKey)
        cloud.synchronize()
    }
}
