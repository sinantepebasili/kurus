//
//  ExpenseModel.swift
//  Kuruş — Veri modeli, hesap defteri (Ledger) ve biçimlendirme
//
//  Hedefler: App + Widget Extension
//

import Foundation
import SwiftUI

// MARK: - Kategori

enum ExpenseCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case food, coffee, market, transport, shopping, bills, subscription
    case entertainment, health, travel, education, savings, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .food: "Yemek"
        case .coffee: "Kahve"
        case .market: "Market"
        case .transport: "Ulaşım"
        case .shopping: "Alışveriş"
        case .bills: "Fatura"
        case .subscription: "Abonelik"
        case .entertainment: "Eğlence"
        case .health: "Sağlık"
        case .travel: "Seyahat"
        case .education: "Eğitim"
        case .savings: "Birikim"
        case .other: "Diğer"
        }
    }

    var symbol: String {
        switch self {
        case .food: "fork.knife"
        case .coffee: "cup.and.saucer.fill"
        case .market: "cart.fill"
        case .transport: "car.fill"
        case .shopping: "bag.fill"
        case .bills: "bolt.fill"
        case .subscription: "repeat"
        case .entertainment: "popcorn.fill"
        case .health: "cross.case.fill"
        case .travel: "airplane"
        case .education: "book.fill"
        case .savings: "chart.line.uptrend.xyaxis"
        case .other: "square.grid.2x2.fill"
        }
    }

    var color: Color {
        switch self {
        case .food, .coffee, .bills: Theme.amber
        case .market: Theme.emerald
        case .transport, .travel, .education: Theme.ocean
        case .shopping, .entertainment, .health: Theme.coral
        case .subscription, .savings: Theme.violet
        case .other: Theme.textSecondary
        }
    }

    /// Birikim / Yatırım "gerçek harcama" toplamına girmez.
    var isSavings: Bool { self == .savings }
}

// MARK: - Kart

struct PaymentCard: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var last4: String?
    var bankName: String
    var nickname: String?
    /// Hesap kesim günü (1–31). `nil` → belirtilmemiş.
    var statementDay: Int?

    var displayName: String {
        if let nickname, !nickname.trimmingCharacters(in: .whitespaces).isEmpty { return nickname }
        return bankName
    }

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
        note: String? = nil
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
    }

    var brand: Brand? { brandID.flatMap(BrandEngine.brand(id:)) }
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
        cal.locale = Locale(identifier: "tr_TR")
        cal.firstWeekday = 2
        cal.timeZone = .current
        return cal
    }

    static func inMonth(_ expenses: [Expense], of date: Date = .now) -> [Expense] {
        let cal = calendar
        return expenses.filter { cal.isDate($0.date, equalTo: date, toGranularity: .month) }
    }

    static func sum(_ expenses: [Expense]) -> Decimal {
        expenses.reduce(Decimal(0)) { $0 + $1.amount }
    }

    static func spending(_ expenses: [Expense]) -> Decimal {
        sum(expenses.filter { !$0.category.isSavings })
    }

    static func savings(_ expenses: [Expense]) -> Decimal {
        sum(expenses.filter { $0.category.isSavings })
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
        return Dictionary(grouping: recurring) { $0.brandID ?? $0.title.kurusNormalized }
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
                subtitle: "Taksit \(e.installment?.label ?? "")",
                date: e.date,
                amount: e.amount,
                brandID: e.brandID,
                category: e.category,
                kind: .installment
            ))
        }

        // 2) Abonelik yenilemeleri
        for e in latestRecurring(in: s, now: now) {
            guard let next = cal.date(byAdding: .month, value: 1, to: e.date), next > now, next <= horizon else { continue }
            items.append(UpcomingPayment(
                id: "sub-\(e.id.uuidString)",
                title: e.title,
                subtitle: "Yenileme",
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
            let due = sum(s.expenses.filter { $0.cardID == card.id && $0.date > previous && $0.date <= now })
            items.append(UpcomingPayment(
                id: "stmt-\(card.id)",
                title: card.pillTitle,
                subtitle: "Hesap kesimi",
                date: next,
                amount: due > 0 ? due : nil,
                brandID: nil,
                category: .bills,
                kind: .statement
            ))
        }

        return items.sorted { $0.date < $1.date }
    }

    /// Gelecek ayların yükü: o aya düşen taksitler + aylık tekrarlayan giderler.
    static func load(monthOffset: Int, in s: KurusSnapshot, now: Date = .now) -> Decimal {
        let cal = calendar
        guard let target = cal.date(byAdding: .month, value: monthOffset, to: now) else { return 0 }
        let scheduled = sum(s.expenses.filter {
            $0.date > now && cal.isDate($0.date, equalTo: target, toGranularity: .month)
        })
        let recurring = sum(latestRecurring(in: s, now: now))
        return scheduled + recurring
    }
}

// MARK: - Para biçimi (tr_TR: ₺12.000,50)

enum CurrencyFormat {
    static func parts(_ value: Decimal) -> (sign: String, integer: String, fraction: String) {
        let rounded = value.rounded(2)
        let negative = rounded < 0
        let absolute = negative ? -rounded : rounded
        let cents = NSDecimalNumber(decimal: absolute * 100).int64Value
        let integer = cents / 100
        let fraction = cents % 100
        return (negative ? "−" : "", grouped(integer), String(format: "%02lld", fraction))
    }

    static func grouped(_ value: Int64) -> String {
        let digits = String(value)
        var out = ""
        for (index, char) in digits.enumerated() {
            if index > 0, (digits.count - index) % 3 == 0 { out.append(".") }
            out.append(char)
        }
        return out
    }

    /// "₺12.000,50" ya da `fraction: false` ile "₺12.001"
    static func string(_ value: Decimal, fraction: Bool = true) -> String {
        let p = parts(fraction ? value : value.rounded(0))
        return "\(p.sign)₺\(p.integer)" + (fraction ? ",\(p.fraction)" : "")
    }

    /// CSV için gruplamasız "642,50"
    static func plain(_ value: Decimal) -> String {
        let p = parts(value)
        return "\(p.sign == "" ? "" : "-")\(p.integer.replacingOccurrences(of: ".", with: "")),\(p.fraction)"
    }
}

extension Decimal {
    func rounded(_ scale: Int) -> Decimal {
        var source = self
        var result = Decimal()
        NSDecimalRound(&result, &source, scale, .plain)
        return result
    }

    var doubleValue: Double { NSDecimalNumber(decimal: self).doubleValue }
}

// MARK: - Tarih biçimleri

enum KurusDate {
    static let locale = Locale(identifier: "tr_TR")

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

    static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(locale))
    }

    static func dayHeader(_ date: Date) -> String {
        let cal = Ledger.calendar
        if cal.isDateInToday(date) { return "Bugün" }
        if cal.isDateInYesterday(date) { return "Dün" }
        return date.formatted(.dateTime.day().month(.wide).weekday(.wide).locale(locale))
    }

    static func relative(_ date: Date, from now: Date = .now) -> String {
        let cal = Ledger.calendar
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: date)).day ?? 0
        switch days {
        case ..<1: return "Bugün"
        case 1: return "Yarın"
        default: return "\(days) gün"
        }
    }

    /// Pazar=1 … Cumartesi=7 → Türkçe baş harf
    static func weekdayInitial(_ date: Date) -> String {
        let initials = ["P", "P", "S", "Ç", "P", "C", "C"]
        let weekday = Ledger.calendar.component(.weekday, from: date)
        return initials[max(0, min(6, weekday - 1))]
    }
}
