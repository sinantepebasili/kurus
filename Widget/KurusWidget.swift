//
//  KurusWidget.swift
//  Kuruş — Tek WidgetBundle altında 4 widget
//
//  Hedef: Widget Extension
//  (Ayrıca bu hedefe dahil edin: Theme, BrandEngine, ExpenseModel, ExpenseParser,
//   SharedExpenseStore, AddExpenseIntent)
//
//   1. Hızlı Ekleme        .systemMedium        — interaktif Button(intent:)
//   2. 7 Günlük İvme       .systemSmall         — 7 dikey kapsül
//   3. Bütçe Halkası       .accessoryCircular   — Gauge
//   4. Aylık Özet Satırı   .accessoryRectangular — toplam + birikim oranı
//

import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Zaman çizelgesi

struct KurusEntry: TimelineEntry {
    let date: Date
    let monthTotal: Decimal
    let todayTotal: Decimal
    let budget: Decimal
    let savingsShare: Double
    let week: [DayTotal]

    var budgetProgress: Double {
        budget > 0 ? (monthTotal / budget).doubleValue : 0
    }

    static func make(from snapshot: KurusSnapshot, at date: Date) -> KurusEntry {
        let month = Ledger.inMonth(snapshot.expenses, of: date)
        return KurusEntry(
            date: date,
            monthTotal: Ledger.spending(month),
            todayTotal: Ledger.spendingOnDay(snapshot.expenses, day: date),
            budget: snapshot.monthlyBudget,
            savingsShare: Ledger.savingsShare(month),
            week: Ledger.dailyTotals(snapshot.expenses, days: 7, endingAt: date)
        )
    }

    static var placeholder: KurusEntry {
        let cal = Ledger.calendar
        let today = cal.startOfDay(for: .now)
        let sample: [Decimal] = [420, 180, 960, 310, 0, 640, 275]
        let week = sample.enumerated().map { index, total in
            DayTotal(date: cal.date(byAdding: .day, value: index - 6, to: today) ?? today, total: total)
        }
        return KurusEntry(
            date: .now,
            monthTotal: 18_642.5,
            todayTotal: 275,
            budget: 30_000,
            savingsShare: 0.14,
            week: week
        )
    }
}

struct KurusProvider: TimelineProvider {
    func placeholder(in context: Context) -> KurusEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (KurusEntry) -> Void) {
        let snapshot = SharedExpenseStore.loadSnapshot()
        if context.isPreview && snapshot.expenses.isEmpty {
            completion(.placeholder)
        } else {
            completion(.make(from: snapshot, at: .now))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<KurusEntry>) -> Void) {
        let now = Date()
        let entry = KurusEntry.make(from: SharedExpenseStore.loadSnapshot(), at: now)
        let cal = Ledger.calendar
        let midnight = cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: now) ?? now)
        let refresh = min(midnight, now.addingTimeInterval(30 * 60))
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}

// MARK: - 1) İnteraktif Hızlı Ekleme (.systemMedium)

private struct QuickPreset: Identifiable {
    let id: String
    let title: String
    let amount: Decimal
    let category: ExpenseCategory

    var command: String { "\(title) \(NSDecimalNumber(decimal: amount).stringValue)" }

    static let all: [QuickPreset] = [
        QuickPreset(id: "coffee", title: "Kahve", amount: 145, category: .coffee),
        QuickPreset(id: "food", title: "Yemek", amount: 320, category: .food),
        QuickPreset(id: "market", title: "Market", amount: 500, category: .market),
    ]
}

struct QuickAddWidgetView: View {
    let entry: KurusEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("BU AY")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(Theme.textSecondary)
                    AmountText(amount: entry.monthTotal, size: 26, weight: .bold)
                }
                Spacer(minLength: 8)
                Link(destination: URL(string: "kurus://quick-add")!) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                        Text("Yaz")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(Theme.background)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(Theme.textPrimary, in: Capsule())
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                ForEach(QuickPreset.all) { preset in
                    Button(intent: AddExpenseIntent(text: preset.command)) {
                        presetChip(preset)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func presetChip(_ preset: QuickPreset) -> some View {
        HStack(spacing: 8) {
            Image(systemName: preset.category.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(preset.category.color)
                .frame(width: 26, height: 26)
                .background(preset.category.color.opacity(0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(preset.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                AmountText(amount: preset.amount, size: 13, weight: .semibold, showsFraction: false)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
    }
}

struct QuickAddWidget: Widget {
    let kind = "KurusQuickAdd"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: KurusProvider()) { entry in
            QuickAddWidgetView(entry: entry)
                .containerBackground(for: .widget) { Theme.background }
        }
        .configurationDisplayName("Hızlı Ekle")
        .description("Aylık toplamın ve tek dokunuşla kahve, yemek, market kaydı.")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - 2) 7 Günlük Harcama İvmesi (.systemSmall)

struct WeeklyPulseWidgetView: View {
    let entry: KurusEntry

    private var maxTotal: Double {
        max(entry.week.map { $0.total.doubleValue }.max() ?? 0, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("7 GÜN")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.emerald)
            }

            Spacer(minLength: 6)

            HStack(alignment: .bottom, spacing: 0) {
                ForEach(Array(entry.week.enumerated()), id: \.offset) { index, day in
                    let isToday = index == entry.week.count - 1
                    let ratio = day.total.doubleValue / maxTotal
                    VStack(spacing: 4) {
                        Capsule()
                            .fill(isToday ? Theme.emerald : Theme.ocean.opacity(day.total > 0 ? 0.6 : 0.25))
                            .frame(width: 9, height: max(5, 50 * ratio))
                        Text(KurusDate.weekdayInitial(day.date))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(isToday ? Theme.textPrimary : Theme.textMuted)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 66, alignment: .bottom)

            Spacer(minLength: 6)

            Text("Bugün")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            AmountText(amount: entry.todayTotal, size: 20, weight: .bold)
        }
    }
}

struct WeeklyPulseWidget: Widget {
    let kind = "KurusWeeklyPulse"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: KurusProvider()) { entry in
            WeeklyPulseWidgetView(entry: entry)
                .containerBackground(for: .widget) { Theme.background }
        }
        .configurationDisplayName("7 Günlük İvme")
        .description("Son yedi günün harcama ritmi ve bugünkü toplam.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - 3) Kilit Ekranı Bütçe Halkası (.accessoryCircular)

struct BudgetRingWidgetView: View {
    let entry: KurusEntry

    var body: some View {
        Gauge(value: min(max(entry.budgetProgress, 0), 1)) {
            Image(systemName: "turkishlirasign")
        } currentValueLabel: {
            Text("\(Int((entry.budgetProgress * 100).rounded()))")
                .font(.system(size: 16, weight: .bold))
                .monospacedDigit()
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetAccentable()
        .accessibilityLabel("Bütçenin yüzde \(Int((entry.budgetProgress * 100).rounded())) kısmı kullanıldı")
    }
}

struct BudgetRingWidget: Widget {
    let kind = "KurusBudgetRing"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: KurusProvider()) { entry in
            BudgetRingWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Bütçe Halkası")
        .description("Aylık limitine göre dolan halka.")
        .supportedFamilies([.accessoryCircular])
    }
}

// MARK: - 4) Kilit Ekranı Özet Satırı (.accessoryRectangular)

struct MonthlyLineWidgetView: View {
    let entry: KurusEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "turkishlirasign.circle.fill")
                Text("Kuruş · \(KurusDate.monthName(entry.date))")
            }
            .font(.system(size: 12, weight: .semibold))
            .widgetAccentable()

            Text(CurrencyFormat.string(entry.monthTotal, fraction: false))
                .font(.system(size: 20, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            HStack(spacing: 6) {
                Text("Birikim %\(Int((entry.savingsShare * 100).rounded()))")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .fixedSize()
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.25))
                        Capsule()
                            .fill(Color.primary)
                            .frame(width: entry.savingsShare > 0 ? max(4, geo.size.width * entry.savingsShare) : 0)
                    }
                }
                .frame(height: 4)
                .widgetAccentable()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MonthlyLineWidget: Widget {
    let kind = "KurusMonthlyLine"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: KurusProvider()) { entry in
            MonthlyLineWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Aylık Özet")
        .description("Bu ayki toplam harcama ve birikim oranı.")
        .supportedFamilies([.accessoryRectangular])
    }
}

// MARK: - Paket

@main
struct KurusWidgetBundle: WidgetBundle {
    var body: some Widget {
        QuickAddWidget()
        WeeklyPulseWidget()
        BudgetRingWidget()
        MonthlyLineWidget()
    }
}
