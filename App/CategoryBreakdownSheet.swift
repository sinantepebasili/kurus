//
//  CategoryBreakdownSheet.swift
//  Kuruş — Seçili ayın gerçek harcamaları için ince halka grafik (Sağlık / Fitness estetiği)
//
//  Hedef: App
//

import SwiftUI

struct CategoryBreakdownSheet: View {
    let month: Date
    /// Ay + kart filtresi uygulanmış kayıtlar (gelir ve birikim burada süzülür).
    let expenses: [Expense]
    let scopeTitle: String
    var isProjection: Bool = false

    @Environment(\.dismiss) private var dismiss
    @State private var revealed = false
    @State private var focused: ExpenseCategory?

    private let ringWidth: CGFloat = 16
    private let ringSize: CGFloat = 208

    private struct Slice: Identifiable {
        let category: ExpenseCategory
        let total: Decimal
        let share: Double
        let start: Double
        var end: Double { start + share }
        var id: String { category.rawValue }
    }

    private var total: Decimal { Ledger.spending(expenses) }

    private var slices: [Slice] {
        let spending = expenses.filter { $0.category.countsAsSpending }
        let total = Ledger.sum(spending)
        guard total > 0 else { return [] }

        let grouped = Dictionary(grouping: spending, by: \.category)
            .map { (category: $0.key, total: Ledger.sum($0.value)) }
            .sorted { $0.total > $1.total }

        var cursor = 0.0
        var result: [Slice] = []
        for item in grouped {
            let share = (item.total / total).doubleValue
            result.append(Slice(category: item.category, total: item.total, share: share, start: cursor))
            cursor += share
        }
        return result
    }

    var body: some View {
        let data = slices

        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    Text(scopeTitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    ring(data)

                    if data.isEmpty {
                        emptyState
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(data.enumerated()), id: \.element.id) { index, slice in
                                if index > 0 {
                                    Rectangle().fill(Theme.hairline).frame(height: 1).padding(.leading, 58)
                                }
                                row(slice)
                            }
                        }
                        .padding(.horizontal, 14)
                        .craftCard(fill: Theme.background)
                    }

                    Text(footnote)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textMuted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background(Theme.surface)
            .navigationTitle("Kategori Dağılımı")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.surface, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Bitti") { dismiss() }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.emerald)
                }
            }
        }
        .presentationDetents([.fraction(0.82), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.surface)
        .presentationCornerRadius(28)
        .onAppear {
            withAnimation(Theme.spring.delay(0.1)) { revealed = true }
        }
    }

    // MARK: - Halka

    private func ring(_ data: [Slice]) -> some View {
        let progress = revealed ? 1.0 : 0.0
        let gap = data.count > 1 ? 0.006 : 0
        let focusedSlice = data.first { $0.category == focused }

        return ZStack {
            Circle()
                .stroke(Theme.elevated, lineWidth: ringWidth)

            ZStack {
                ForEach(data) { slice in
                    let from = slice.start * progress + gap / 2
                    let to = max(from, slice.end * progress - gap / 2)
                    Circle()
                        .trim(from: from, to: to)
                        .stroke(slice.category.color, style: StrokeStyle(lineWidth: ringWidth, lineCap: .butt))
                        .opacity(focused == nil || focused == slice.category ? 1 : 0.25)
                }
            }
            .rotationEffect(.degrees(-90))

            VStack(spacing: 4) {
                Text(focusedSlice?.category.title ?? (isProjection ? "Tahmini Yük" : "Gerçek Harcama"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(focusedSlice?.category.color ?? Theme.textSecondary)
                    .contentTransition(.interpolate)
                AmountText(amount: focusedSlice?.total ?? total, size: 26, weight: .bold)
                    .privacyBlur()
                Text(focusedSlice.map { percent($0.share) } ?? KurusDate.monthYear(month))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textMuted)
                    .monospacedDigit()
            }
            .padding(.horizontal, ringWidth + 12)
        }
        .frame(width: ringSize, height: ringSize)
        .animation(Theme.spring, value: focused)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            data.map { "\($0.category.title) \(percent($0.share))" }.joined(separator: ", ")
        )
    }

    // MARK: - Liste

    private func row(_ slice: Slice) -> some View {
        Button {
            focused = focused == slice.category ? nil : slice.category
            Haptics.selection()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: slice.category.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(slice.category.color)
                    .frame(width: 32, height: 32)
                    .background(slice.category.color.opacity(0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(slice.category.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer(minLength: 8)
                        AmountText(amount: slice.total, size: 15, weight: .semibold)
                            .privacyBlur()
                    }
                    HStack(spacing: 10) {
                        CapsuleMeter(progress: revealed ? slice.share : 0, tint: slice.category.color, height: 4)
                        Text(percent(slice.share))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .opacity(focused == nil || focused == slice.category ? 1 : 0.45)
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.pie")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.textMuted)
            Text(isProjection ? "Bu ay için planlı ödeme yok" : "Bu dönemde harcama yok")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.vertical, 12)
    }

    private var footnote: String {
        var text = "Birikim / yatırım ve gelir kayıtları bu dağılıma dahil değildir."
        if isProjection {
            text += " Gelecek ay; kayıtlı taksitler ve abonelik tahminlerinden oluşur."
        }
        return text
    }

    private func percent(_ share: Double) -> String {
        if share > 0, share < 0.01 { return "<%1" }
        return "%\(Int((share * 100).rounded()))"
    }
}
