//
//  ExpenseModel.swift
//  Kuruş / Cent — Veri modeli, hesap defteri (Ledger) ve biçimlendirme
//
//  Hedefler: App + Widget Extension
//

import Foundation
import SwiftUI

// MARK: - Kategori

enum ExpenseCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case food, coffee, market, transport, shopping, technology, housing, bills, tax, subscription
    case entertainment, health, travel, education, savings, income, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .food: L("Yemek", "Food")
        case .coffee: L("Kahve", "Coffee")
        case .market: L("Market", "Groceries")
        case .transport: L("Ulaşım", "Transport")
        case .shopping: L("Alışveriş", "Shopping")
        case .technology: L("Teknoloji", "Tech")
        case .housing: L("Konut", "Housing")
        case .bills: L("Fatura", "Bills")
        case .tax: L("Vergi & Resmi", "Tax & Government")
        case .subscription: L("Abonelik", "Subscriptions")
        case .entertainment: L("Eğlence", "Entertainment")
        case .health: L("Sağlık", "Health")
        case .travel: L("Seyahat", "Travel")
        case .education: L("Eğitim", "Education")
        case .savings: L("Birikim", "Savings")
        case .income: L("Gelir", "Income")
        case .other: L("Diğer", "Other")
        }
    }

    var symbol: String {
        switch self {
        case .food: "fork.knife"
        case .coffee: "cup.and.saucer.fill"
        case .market: "cart.fill"
        case .transport: "car.fill"
        case .shopping: "bag.fill"
        case .technology: "desktopcomputer"
        case .housing: "house.fill"
        case .bills: "bolt.fill"
        case .tax: "building.columns.fill"
        case .subscription: "repeat"
        case .entertainment: "popcorn.fill"
        case .health: "cross.case.fill"
        case .travel: "airplane"
        case .education: "book.fill"
        case .savings: "chart.line.uptrend.xyaxis"
        case .income: "arrow.down.left.circle.fill"
        case .other: "square.grid.2x2.fill"
        }
    }

    var color: Color {
        switch self {
        case .food, .coffee, .bills: Theme.amber
        case .market: Theme.emerald
        case .transport, .travel, .education, .housing: Theme.ocean
        case .shopping, .entertainment, .health: Theme.coral
        case .subscription, .savings: Theme.violet
        case .technology: Theme.indigo
        case .tax: Theme.brass
        case .income: Theme.emerald
        case .other: Theme.textSecondary
        }
    }

    /// Birikim / Yatırım "gerçek harcama" toplamına girmez.
    var isSavings: Bool { self == .savings }

    /// Gelir (maaş, iade, prim…) harcama toplamına girmez; bütçe havuzunu büyütür.
    var isIncome: Bool { self == .income }

    /// Gerçek harcama = birikim ve gelir dışındaki her şey.
    var countsAsSpending: Bool { !isSavings && !isIncome }
}

// MARK: - Kart

struct PaymentCard: Codable, Identifiable, Hashable, Sendable {
    /// Kartsız harcamaların havuzu. Banka (debit) kartı harcamaları hesap kesimine tabi olmadığı
    /// için burada izlenir; etiket gerçek dünyadaki karşılığını söyler (Heuristic #2).
    static var cashTitle: String { L("Nakit / Banka Kartı", "Cash / Debit") }
    static var cashShortTitle: String { L("Nakit", "Cash") }

    /// Kalıcı, benzersiz kimlik. Yeni kartlar `UUID().uuidString` alır; ad değişse de, iki kart aynı
    /// adı taşısa da tüm güncellemeler (ad, hesap kesim günü) yalnızca bu kimlikle yapılır.
    /// (Eski sürümlerden gelen "card-4532" / "bank-bonus" biçimli kimlikler aynen geçerli kalır.)
    var id: String
    var last4: String?
    var bankName: String
    var nickname: String?
    /// Hesap kesim günü (1–31). `nil` → belirtilmemiş.
    var statementDay: Int?
    /// İlk açılış demosunun oluşturduğu kart. "Clear & Start" ya da ilk gerçek giriş onu da siler.
    /// İsteğe bağlı: eski sürümlerin kayıtları bu alan olmadan da okunur.
    var isDemo: Bool? = nil

    var displayName: String {
        if let nickname, !nickname.trimmingCharacters(in: .whitespaces).isEmpty { return nickname }
        return isBankUnknown ? L("Kart", "Card") : bankName
    }

    /// Banka adı bilinmiyor mu? (Eski sürümler bilinmeyen bankayı "Kart" olarak saklıyordu.)
    var isBankUnknown: Bool { bankName.isEmpty || bankName == "Kart" }

    var maskedSuffix: String { last4.map { "••\($0)" } ?? "" }

    var pillTitle: String {
        [displayName, maskedSuffix].filter { !$0.isEmpty }.joined(separator: " ")
    }
}

// MARK: - Taksit

struct InstallmentInfo: Codable, Hashable, Sendable {
    var groupID: UUID
    var index: Int
    var count: Int
    var total: Decimal

    var label: String { "\(index)/\(count)" }
}

// MARK: - Harcama

struct Expense: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var title: String
    var amount: Decimal
    var date: Date
    var category: ExpenseCategory
    var brandID: String?
    /// `nil` → Nakit
    var cardID: String?
    var installment: InstallmentInfo?
    var isRecurring: Bool
    var isDemo: Bool
    var note: String?
    /// ISO para birimi. `nil` → cihazın ana para birimi (`Money.homeCurrency`).
    /// Yabancı para birimli kayıtlar (ör. yurt dışında "$14.50") kur çevrimi yapılmadığı için toplamlara girmez.
    var currencyCode: String?

    init(
        id: UUID = UUID(),
        title: String,
        amount: Decimal,
        date: Date = .now,
        category: ExpenseCategory,
        brandID: String? = nil,
        cardID: String? = nil,
        installment: InstallmentInfo? = nil,
        isRecurring: Bool = false,
        isDemo: Bool = false,
        note: String? = nil,
        currencyCode: String? = nil
    ) {
        self.id = id
        self.title = title
        self.amount = amount
        self.date = date
        self.category = category
        self.brandID = brandID
        self.cardID = cardID
        self.installment = installment
        self.isRecurring = isRecurring
        self.isDemo = isDemo
        self.note = note
        self.currencyCode = currencyCode
    }

    var brand: Brand? { brandID.flatMap(BrandEngine.brand(id:)) }

    /// Ana para biriminde mi (toplamlara dahil mi)?
    var isHomeCurrency: Bool { currencyCode == nil || currencyCode == Money.homeCurrency }
}

// MARK: - Kalıcı anlık görüntü (App Group + iCloud KVS)

struct KurusSnapshot: Codable, Sendable {
    var expenses: [Expense] = []
    var cards: [PaymentCard] = []
    var monthlyBudget: Decimal = 30_000
    var hasCompletedOnboarding: Bool = false
    var updatedAt: Date = .distantPast
}

// MARK: - Kart filtresi

enum CardFilter: Hashable, Sendable {
    case all
    case cash
    case card(String)

    func includes(_ expense: Expense) -> Bool {
        switch self {
        case .all: true
        case .cash: expense.cardID == nil
        case .card(let id): expense.cardID == id
        }
    }
}

// MARK: - Yaklaşan ödeme

struct UpcomingPayment: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable { case installment, subscription, statement }

    let id: String
    let title: String
    let subtitle: String
    let date: Date
    let amount: Decimal?
    let brandID: String?
    let category: ExpenseCategory
    let kind: Kind
    /// Hesap kesimi satırları için kartın kimliği (basılı tutunca kart düzenleme açılır)
    var cardID: String? = nil

    var brand: Brand? { brandID.flatMap(BrandEngine.brand(id:)) }
}

struct DayTotal: Hashable, Sendable {
    let date: Date
    let total: Decimal
}

// MARK: - Hesap defteri (saf fonksiyonlar — App ve Widget ortak)

enum Ledger {
    static var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = .current
        cal.firstWeekday = Calendar.current.firstWeekday
        cal.timeZone = .current
        return cal
    }

    static func inMonth(_ expenses: [Expense], of date: Date = .now) -> [Expense] {
        let cal = calendar
        return expenses.filter { cal.isDate($0.date, equalTo: date, toGranularity: .month) }
    }

    /// Yalnızca ana para birimindeki kayıtları toplar; döviz kayıtları kur çevrimi olmadan toplanamaz.
    static func sum(_ expenses: [Expense]) -> Decimal {
        expenses.reduce(Decimal(0)) { $1.isHomeCurrency ? $0 + $1.amount : $0 }
    }

    static func spending(_ expenses: [Expense]) -> Decimal {
        sum(expenses.filter { $0.category.countsAsSpending })
    }

    static func savings(_ expenses: [Expense]) -> Decimal {
        sum(expenses.filter { $0.category.isSavings })
    }

    static func income(_ expenses: [Expense]) -> Decimal {
        sum(expenses.filter { $0.category.isIncome })
    }

    /// O ay en az bir gelir girildiyse bütçe havuzu = o ayın toplam geliri; yoksa manuel hedef.
    static func effectiveBudget(_ monthEntries: [Expense], manual: Decimal) -> Decimal {
        let earned = income(monthEntries)
        return earned > 0 ? earned : manual
    }

    // MARK: Ay gezintisi

    static func startOfMonth(_ date: Date) -> Date {
        let cal = calendar
        return cal.date(from: cal.dateComponents([.year, .month], from: date)) ?? date
    }

    static func isCurrentMonth(_ month: Date, now: Date = .now) -> Bool {
        startOfMonth(month) == startOfMonth(now)
    }

    static func isFutureMonth(_ month: Date, now: Date = .now) -> Bool {
        startOfMonth(month) > startOfMonth(now)
    }

    /// Bir ayın kayıtları. Gelecek aylarda kayıtlı taksitlerin yanında tekrarlayan
    /// aboneliklerin (ve maaş gibi düzenli gelirlerin) tahmini kopyaları da döner.
    /// Tahminler kalıcı değildir; `projectedIDs` ile işaretlenir.
    static func monthEntries(in s: KurusSnapshot, month: Date, now: Date = .now) -> (items: [Expense], projectedIDs: Set<UUID>) {
        let real = inMonth(s.expenses, of: month)
        guard isFutureMonth(month, now: now) else { return (real, []) }
        let projected = projectedRecurring(in: s, month: month, existing: real, now: now)
        return (real + projected, Set(projected.map(\.id)))
    }

    static func projectedRecurring(in s: KurusSnapshot, month: Date, existing: [Expense], now: Date = .now) -> [Expense] {
        let cal = calendar
        let existingKeys = Set(existing.map { recurringKey($0) })
        let monthStart = startOfMonth(month)
        let daysInMonth = cal.range(of: .day, in: .month, for: monthStart)?.count ?? 28

        return latestRecurring(in: s, now: now).compactMap { source in
            guard !existingKeys.contains(recurringKey(source)) else { return nil }
            var comps = cal.dateComponents([.year, .month], from: monthStart)
            let original = cal.dateComponents([.day, .hour, .minute], from: source.date)
            comps.day = min(original.day ?? 1, daysInMonth)
            comps.hour = original.hour
            comps.minute = original.minute
            guard let date = cal.date(from: comps) else { return nil }
            return Expense(
                id: projectedID(for: source.id, month: monthStart),
                title: source.title,
                amount: source.amount,
                date: date,
                category: source.category,
                brandID: source.brandID,
                cardID: source.cardID,
                isRecurring: true,
                isDemo: source.isDemo,
                note: source.note,
                currencyCode: source.currencyCode
            )
        }
    }

    private static func recurringKey(_ e: Expense) -> String {
        e.brandID ?? e.title.kurusNormalized
    }

    /// Kaynak kimlik + ay → kararlı (her çizimde aynı) tahmin kimliği.
    private static func projectedID(for source: UUID, month: Date) -> UUID {
        let comps = calendar.dateComponents([.year, .month], from: month)
        var bytes = source.uuid
        bytes.13 ^= 0xA5
        bytes.14 = UInt8(truncatingIfNeeded: comps.year ?? 0)
        bytes.15 = UInt8(truncatingIfNeeded: comps.month ?? 0)
        return UUID(uuid: bytes)
    }

    /// Birikim / (Harcama + Birikim)
    static func savingsShare(_ expenses: [Expense]) -> Double {
        let s = savings(expenses).doubleValue
        let total = s + spending(expenses).doubleValue
        return total > 0 ? s / total : 0
    }

    static func spendingOnDay(_ expenses: [Expense], day: Date = .now) -> Decimal {
        let cal = calendar
        return spending(expenses.filter { cal.isDate($0.date, inSameDayAs: day) })
    }

    static func dailyTotals(_ expenses: [Expense], days: Int = 7, endingAt end: Date = .now) -> [DayTotal] {
        let cal = calendar
        let today = cal.startOfDay(for: end)
        return (0..<days).reversed().compactMap { offset in
            guard let day = cal.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let total = spending(expenses.filter { cal.isDate($0.date, inSameDayAs: day) })
            return DayTotal(date: day, total: total)
        }
    }

    /// Bir sonraki "ayın N. günü". Kısa aylarda ayın son gününe sabitlenir.
    static func nextOccurrence(day: Int, onOrAfter date: Date) -> Date? {
        let cal = calendar
        let start = cal.startOfDay(for: date)
        for offset in 0...2 {
            guard let monthDate = cal.date(byAdding: .month, value: offset, to: start) else { continue }
            var comps = cal.dateComponents([.year, .month], from: monthDate)
            let daysInMonth = cal.range(of: .day, in: .month, for: monthDate)?.count ?? 28
            comps.day = min(day, daysInMonth)
            if let candidate = cal.date(from: comps), candidate >= start { return candidate }
        }
        return nil
    }

    /// Son tekrarlayan gider kayıtları (marka ya da başlığa göre en yenisi).
    private static func latestRecurring(in s: KurusSnapshot, now: Date) -> [Expense] {
        let recurring = s.expenses.filter { $0.isRecurring && $0.installment == nil && $0.date <= now }
        return Dictionary(grouping: recurring) { recurringKey($0) }
            .compactMap { $0.value.max { $0.date < $1.date } }
    }

    /// Taksitler, abonelik yenilemeleri ve hesap kesim tarihleri — tarihe göre.
    static func upcoming(in s: KurusSnapshot, now: Date = .now, horizonDays: Int = 45) -> [UpcomingPayment] {
        let cal = calendar
        let horizon = cal.date(byAdding: .day, value: horizonDays, to: now) ?? now
        var items: [UpcomingPayment] = []

        // 1) Her taksit grubunun en yakın gelecek taksiti
        let futureInstallments = s.expenses.filter { $0.installment != nil && $0.date > now && $0.date <= horizon }
        let nearest = Dictionary(grouping: futureInstallments) { $0.installment?.groupID ?? $0.id }
            .compactMap { $0.value.min { $0.date < $1.date } }
        for e in nearest {
            items.append(UpcomingPayment(
                id: "inst-\(e.id.uuidString)",
                title: e.title,
                subtitle: "\(L("Taksit", "Installment")) \(e.installment?.label ?? "")",
                date: e.date,
                amount: e.amount,
                brandID: e.brandID,
                category: e.category,
                kind: .installment
            ))
        }

        // 2) Abonelik yenilemeleri
        for e in latestRecurring(in: s, now: now) where !e.category.isIncome {
            guard let next = cal.date(byAdding: .month, value: 1, to: e.date), next > now, next <= horizon else { continue }
            items.append(UpcomingPayment(
                id: "sub-\(e.id.uuidString)",
                title: e.title,
                subtitle: L("Yenileme", "Renews"),
                date: next,
                amount: e.amount,
                brandID: e.brandID,
                category: e.category,
                kind: .subscription
            ))
        }

        // 3) Hesap kesim tarihleri — dönem içi kart borcu ile
        for card in s.cards {
            guard let day = card.statementDay,
                  let next = nextOccurrence(day: day, onOrAfter: now),
                  let previous = cal.date(byAdding: .month, value: -1, to: next) else { continue }
            let due = sum(s.expenses.filter { $0.cardID == card.id && $0.category.countsAsSpending && $0.date > previous && $0.date <= now })
            items.append(UpcomingPayment(
                id: "stmt-\(card.id)",
                title: card.pillTitle,
                subtitle: L("Hesap kesimi", "Statement"),
                date: next,
                amount: due > 0 ? due : nil,
                brandID: nil,
                category: .bills,
                kind: .statement,
                cardID: card.id
            ))
        }

        return items.sorted { $0.date < $1.date }
    }

    /// Gelecek ayların yükü: o aya düşen taksitler + aylık tekrarlayan giderler (gelirler hariç).
    static func load(monthOffset: Int, in s: KurusSnapshot, now: Date = .now) -> Decimal {
        let cal = calendar
        guard let target = cal.date(byAdding: .month, value: monthOffset, to: now) else { return 0 }
        let scheduled = spending(s.expenses.filter {
            $0.date > now && cal.isDate($0.date, equalTo: target, toGranularity: .month)
        })
        let recurring = spending(latestRecurring(in: s, now: now))
        return scheduled + recurring
    }
}

// Para biçimi: bkz. Localization.swift (CurrencyFormat)

extension Decimal {
    func rounded(_ scale: Int) -> Decimal {
        var source = self
        var result = Decimal()
        NSDecimalRound(&result, &source, scale, .plain)
        return result
    }

    var doubleValue: Double { NSDecimalNumber(decimal: self).doubleValue }
}

// MARK: - Tarih biçimleri (cihaz yerel ayarı)

enum KurusDate {
    static var locale: Locale { .current }

    static func monthName(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).locale(locale))
    }

    static func monthYear(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year().locale(locale))
    }

    static func shortDay(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).locale(locale))
    }

    static func numeric(_ date: Date) -> String {
        date.formatted(.dateTime.day(.twoDigits).month(.twoDigits).year().locale(locale))
    }

    /// tr: "14:32" · en_US: "2:32 PM"
    static func time(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(locale))
    }

    static func dayHeader(_ date: Date) -> String {
        let cal = Ledger.calendar
        if cal.isDateInToday(date) { return L("Bugün", "Today") }
        if cal.isDateInYesterday(date) { return L("Dün", "Yesterday") }
        return date.formatted(.dateTime.day().month(.wide).weekday(.wide).locale(locale))
    }

    static func relative(_ date: Date, from now: Date = .now) -> String {
        let cal = Ledger.calendar
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: date)).day ?? 0
        switch days {
        case ..<1: return L("Bugün", "Today")
        case 1: return L("Yarın", "Tomorrow")
        default: return L("\(days) gün", "in \(days) days")
        }
    }

    /// Yerel tek harfli gün adı (tr: P S Ç P C C P · en: M T W T F S S)
    static func weekdayInitial(_ date: Date) -> String {
        let cal = Ledger.calendar
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        let weekday = cal.component(.weekday, from: date)
        return symbols[max(0, min(symbols.count - 1, weekday - 1))]
    }
}
