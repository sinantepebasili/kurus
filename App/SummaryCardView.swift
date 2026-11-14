//
//  SummaryCardView.swift
//  Kuruş — Aylık özet, satır içi bütçe, harcama/birikim çubuğu, kart hapları, yaklaşan ödemeler
//
//  Hedef: App
//

import SwiftUI

struct SummaryCardView: View {
    @Environment(SharedExpenseStore.self) private var store

    @Binding var filter: CardFilter
    @Binding var isPrivate: Bool

    @State private var isEditingBudget = false
    @State private var budgetDraft = ""
    @FocusState private var budgetFocused: Bool

    @State private var renamingCard: PaymentCard?
    @State private var renameDraft = ""

    private var monthExpenses: [Expense] {
        Ledger.inMonth(store.expenses).filter { filter.includes($0) }
    }

    var body: some View {
        let month = monthExpenses
        let spend = Ledger.spending(month)
        let saved = Ledger.savings(month)

        VStack(alignment: .leading, spacing: 16) {
            mainCard(spend: spend, saved: saved)
                .padding(.horizontal, Theme.gutter)
            cardPills
            upcomingStrip
        }
        .alert(
            "Kart Adı",
            isPresented: Binding(
                get: { renamingCard != nil },
                set: { if !$0 { renamingCard = nil } }
            ),
            presenting: renamingCard
        ) { card in
            TextField("Örn. Bonus Platinum", text: $renameDraft)
            Button("Kaydet") {
                withAnimation(Theme.spring) { store.renameCard(id: card.id, to: renameDraft) }
                Haptics.success()
            }
            Button("Vazgeç", role: .cancel) {}
        } message: { card in
            Text(card.last4.map { "••\($0) ile biten kart" } ?? "\(card.bankName) kartı")
        }
    }

    // MARK: - Ana kart

    private func mainCard(spend: Decimal, saved: Decimal) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                Text(headerTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 8)
                if filter == .all { usageChip(spend: spend) }
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Button {
                    withAnimation(Theme.spring) { isPrivate.toggle() }
                    Haptics.tap()
                } label: {
                    AmountText(amount: spend, size: 42, weight: .bold)
                        .privacyBlur()
                }
                .buttonStyle(.plain)
                .layoutPriority(1)
                .accessibilityHint("Dokunarak tutarları gizle ya da göster")

                budgetLimit
                    .fixedSize()

                Spacer(minLength: 0)
            }

            budgetCaption(spend: spend)

            ratioBar(spend: spend, saved: saved)
        }
        .padding(20)
        .craftCard()
    }

    private var headerTitle: String {
        let month = KurusDate.monthName(.now).uppercased(with: KurusDate.locale)
        switch filter {
        case .all: return "\(month) · TÜM HARCAMALAR"
        case .cash: return "\(month) · NAKİT"
        case .card(let id):
            let name = store.card(id: id)?.pillTitle ?? "KART"
            return "\(month) · \(name.uppercased(with: KurusDate.locale))"
        }
    }

    private func usageChip(spend: Decimal) -> some View {
        let budget = store.monthlyBudget
        let usage = budget > 0 ? (spend / budget).doubleValue : 0
        let tint = usage > 1 ? Theme.coral : (usage > 0.8 ? Theme.amber : Theme.emerald)
        return Text("%\(Int((usage * 100).rounded()))")
            .font(.system(size: 12, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.14), in: Capsule())
            .contentTransition(.numericText(value: usage))
            .privacyBlur()
    }

    // MARK: - Satır içi bütçe düzenleme

    @ViewBuilder
    private var budgetLimit: some View {
        if isEditingBudget {
            HStack(spacing: 4) {
                Text("/ ₺")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                TextField("30000", text: $budgetDraft)
                    .keyboardType(.numberPad)
                    .focused($budgetFocused)
                    .font(.system(size: 17, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .tint(Theme.emerald)
                    .frame(width: 84)
                    .onChange(of: budgetFocused) { _, focused in
                        if !focused { commitBudget() }
                    }
                Button(action: commitBudget) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Theme.emerald)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Bütçeyi kaydet")
            }
            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .leading)))
        } else {
            Button {
                budgetDraft = NSDecimalNumber(decimal: store.monthlyBudget.rounded(0)).stringValue
                withAnimation(Theme.spring) { isEditingBudget = true }
                budgetFocused = true
                Haptics.selection()
            } label: {
                AmountText(
                    amount: store.monthlyBudget,
                    size: 17,
                    weight: .semibold,
                    color: Theme.textMuted,
                    showsFraction: false,
                    prefix: "/ "
                )
                .privacyBlur()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Aylık bütçe limiti, düzenlemek için dokun")
        }
    }

    private func commitBudget() {
        guard isEditingBudget else { return }
        let digits = budgetDraft.filter(\.isNumber)
        if let value = Decimal(string: digits), value > 0 {
            withAnimation(Theme.spring) { store.setBudget(value) }
            Haptics.success()
        }
        budgetFocused = false
        withAnimation(Theme.spring) { isEditingBudget = false }
    }

    // MARK: - Bütçe açıklaması

    @ViewBuilder
    private func budgetCaption(spend: Decimal) -> some View {
        Group {
            if filter == .all {
                let remaining = store.monthlyBudget - spend
                if remaining >= 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "gauge.with.dots.needle.33percent")
                            .foregroundStyle(Theme.emerald)
                        Text("\(CurrencyFormat.string(remaining, fraction: false)) kaldı · günde \(CurrencyFormat.string(dailyAllowance(remaining), fraction: false))")
                    }
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.coral)
                        Text("Bütçe \(CurrencyFormat.string(-remaining, fraction: false)) aşıldı")
                            .foregroundStyle(Theme.coral)
                    }
                }
            } else {
                let all = Ledger.spending(Ledger.inMonth(store.expenses))
                let share = all > 0 ? (spend / all).doubleValue : 0
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease.circle.fill")
                        .foregroundStyle(Theme.ocean)
                    Text("Bu ayki harcamanın %\(Int((share * 100).rounded()))’i bu havuzda")
                }
            }
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(Theme.textSecondary)
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .privacyBlur()
    }

    private func dailyAllowance(_ remaining: Decimal) -> Decimal {
        let cal = Ledger.calendar
        let today = cal.component(.day, from: .now)
        let daysInMonth = cal.range(of: .day, in: .month, for: .now)?.count ?? 30
        let left = max(1, daysInMonth - today + 1)
        return remaining / Decimal(left)
    }

    // MARK: - Gerçek Harcama / Birikim çubuğu

    private func ratioBar(spend: Decimal, saved: Decimal) -> some View {
        let total = (spend + saved).doubleValue
        let spendShare = total > 0 ? spend.doubleValue / total : 1
        let savedShare = total > 0 ? 1 - spendShare : 0

        return VStack(spacing: 10) {
            GeometryReader { geo in
                if total <= 0 {
                    Capsule().fill(Theme.elevated)
                } else {
                    let gap: CGFloat = (spendShare > 0 && spendShare < 1) ? 3 : 0
                    let width = geo.size.width - gap
                    HStack(spacing: gap) {
                        Capsule().fill(Theme.ocean).frame(width: width * spendShare)
                        Capsule().fill(Theme.violet).frame(width: width * savedShare)
                    }
                }
            }
            .frame(height: 6)
            .animation(Theme.spring, value: spendShare)

            HStack {
                legend(color: Theme.ocean, title: "Gerçek Harcama", share: total > 0 ? spendShare : 0)
                Spacer(minLength: 8)
                legend(color: Theme.violet, title: "Birikim / Yatırım", share: savedShare)
            }
        }
    }

    private func legend(color: Color, title: String, share: Double) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title)
                .foregroundStyle(Theme.textSecondary)
            Text("%\(Int((share * 100).rounded()))")
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
                .contentTransition(.numericText(value: share))
        }
        .font(.system(size: 12, weight: .medium))
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }

    // MARK: - Kart filtre hapları

    private var cardPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                pill(title: "Tümü", symbol: "square.stack.fill", value: .all)
                pill(title: "Nakit", symbol: "banknote.fill", value: .cash)
                ForEach(store.cards) { card in
                    pill(title: card.pillTitle, symbol: "creditcard.fill", value: .card(card.id))
                        .contextMenu { cardMenu(card) }
                }
            }
        }
        .contentMargins(.horizontal, Theme.gutter, for: .scrollContent)
    }

    private func pill(title: String, symbol: String, value: CardFilter) -> some View {
        let selected = filter == value
        return Button {
            guard filter != value else { return }
            withAnimation(Theme.spring) { filter = value }
            Haptics.selection()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .foregroundStyle(selected ? Theme.background : Theme.textSecondary)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(selected ? Theme.textPrimary : Theme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(selected ? Color.clear : Theme.hairline, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func cardMenu(_ card: PaymentCard) -> some View {
        Button {
            renameDraft = card.displayName
            renamingCard = card
        } label: {
            Label("Kart Adını Değiştir", systemImage: "pencil")
        }

        Menu {
            Picker("Hesap Kesim Günü", selection: Binding(
                get: { card.statementDay ?? 0 },
                set: { newValue in
                    withAnimation(Theme.spring) {
                        store.setStatementDay(newValue == 0 ? nil : newValue, forCard: card.id)
                    }
                    Haptics.success()
                }
            )) {
                Text("Belirtilmedi").tag(0)
                ForEach(1...31, id: \.self) { day in
                    Text("Her ayın \(day). günü").tag(day)
                }
            }
        } label: {
            Label(
                card.statementDay.map { "Hesap Kesim Günü · \($0)" } ?? "Hesap Kesim Günü Seç",
                systemImage: "calendar"
            )
        }
    }

    // MARK: - Yaklaşan ödemeler / kesim tarihleri şeridi

    @ViewBuilder
    private var upcomingStrip: some View {
        let items = Ledger.upcoming(in: store.snapshot)
        let nextMonth = Ledger.load(monthOffset: 1, in: store.snapshot)

        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "calendar.badge.clock")
                    Text("Yaklaşan Ödemeler")
                    Spacer(minLength: 8)
                    if nextMonth > 0, let date = Ledger.calendar.date(byAdding: .month, value: 1, to: .now) {
                        Text("\(KurusDate.monthName(date)) yükü \(CurrencyFormat.string(nextMonth, fraction: false))")
                            .monospacedDigit()
                            .foregroundStyle(Theme.amber)
                            .privacyBlur()
                    }
                }
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, Theme.gutter)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(items) { item in
                            UpcomingChip(item: item)
                        }
                    }
                }
                .contentMargins(.horizontal, Theme.gutter, for: .scrollContent)
            }
            .transition(.opacity)
        }
    }
}

// MARK: - Yaklaşan ödeme hapı

private struct UpcomingChip: View {
    let item: UpcomingPayment

    var body: some View {
        HStack(spacing: 10) {
            if item.kind == .statement {
                Image(systemName: "creditcard.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.ocean)
                    .frame(width: 28, height: 28)
                    .background(Theme.ocean.opacity(0.16), in: RoundedRectangle(cornerRadius: 8.5, style: .continuous))
            } else {
                ExpenseBadge(brand: item.brand, category: item.category, size: 28)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text("\(item.subtitle) · \(KurusDate.relative(item.date))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(item.kind == .statement ? Theme.ocean : Theme.textSecondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }

            if let amount = item.amount {
                AmountText(amount: amount, size: 13, weight: .semibold, showsFraction: false)
                    .privacyBlur()
                    .padding(.leading, 2)
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 12)
        .padding(.vertical, 8)
        .craftCard(radius: 14)
        .accessibilityElement(children: .combine)
    }
}
