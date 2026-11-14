//
//  SummaryCardView.swift
//  Kuruş — Aylık özet, ay geçişi, satır içi bütçe / gelir havuzu, harcama-birikim çubuğu,
//  kart hapları, yaklaşan ödemeler ve kategori analizi girişi
//
//  Hedef: App
//

import SwiftUI

struct SummaryCardView: View {
    @Environment(SharedExpenseStore.self) private var store
    @Environment(\.privacyMode) private var privacyMode

    @Binding var filter: CardFilter
    @Binding var isPrivate: Bool
    /// Görüntülenen ayın ilk günü (`Ledger.startOfMonth`).
    @Binding var month: Date

    @State private var isEditingBudget = false
    @State private var budgetDraft = ""
    @FocusState private var budgetFocused: Bool

    @State private var renamingCard: PaymentCard?
    @State private var renameDraft = ""

    @State private var showBreakdown = false

    // MARK: - Ay durumu

    private var isCurrentMonth: Bool { Ledger.isCurrentMonth(month) }
    private var isFutureMonth: Bool { Ledger.isFutureMonth(month) }

    /// En eski kayıtlı ay (kayıt yoksa bu ay).
    private var earliestMonth: Date {
        let oldest = store.expenses.map(\.date).min() ?? .now
        return Ledger.startOfMonth(min(oldest, .now))
    }

    /// Taksit ve abonelik yükünü görmek için 12 ay ileri.
    private var latestMonth: Date {
        Ledger.startOfMonth(Ledger.calendar.date(byAdding: .month, value: 12, to: .now) ?? .now)
    }

    private var canGoBack: Bool { month > earliestMonth }
    private var canGoForward: Bool { month < latestMonth }

    // MARK: - Gövde

    var body: some View {
        let all = Ledger.monthEntries(in: store.snapshot, month: month).items
        let filtered = all.filter { filter.includes($0) }
        let spend = Ledger.spending(filtered)
        let saved = Ledger.savings(filtered)
        let allSpend = Ledger.spending(all)
        let incomeDriven = Ledger.income(all) > 0
        let budget = Ledger.effectiveBudget(all, manual: store.monthlyBudget)

        VStack(alignment: .leading, spacing: 16) {
            mainCard(
                spend: spend,
                saved: saved,
                allSpend: allSpend,
                budget: budget,
                incomeDriven: incomeDriven
            )
            .padding(.horizontal, Theme.gutter)

            cardPills

            if isCurrentMonth {
                upcomingStrip
            }
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
        .sheet(isPresented: $showBreakdown) {
            CategoryBreakdownSheet(
                month: month,
                expenses: filtered,
                scopeTitle: scopeTitle,
                isProjection: isFutureMonth
            )
            .environment(\.privacyMode, privacyMode)
        }
    }

    // MARK: - Ana kart

    private func mainCard(
        spend: Decimal,
        saved: Decimal,
        allSpend: Decimal,
        budget: Decimal,
        incomeDriven: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 8) {
                monthStepper
                Spacer(minLength: 8)
                analysisChip(spend: spend, budget: budget)
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

                budgetLimit(budget: budget, incomeDriven: incomeDriven)
                    .fixedSize()

                Spacer(minLength: 0)
            }

            budgetCaption(spend: spend, allSpend: allSpend, budget: budget, incomeDriven: incomeDriven)

            ratioBar(spend: spend, saved: saved)
        }
        .padding(20)
        .craftCard()
    }

    // MARK: - Ay geçişi  ‹ KASIM · TÜM HARCAMALAR ›

    private var monthStepper: some View {
        HStack(spacing: 6) {
            stepButton("chevron.left", enabled: canGoBack, label: "Önceki ay") { shiftMonth(by: -1) }

            Button {
                guard !isCurrentMonth else { return }
                withAnimation(Theme.spring) { month = Ledger.startOfMonth(.now) }
                Haptics.selection()
            } label: {
                Text(headerTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(isCurrentMonth ? Theme.textSecondary : Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .contentTransition(.interpolate)
            }
            .buttonStyle(.plain)
            .accessibilityHint(isCurrentMonth ? "" : "Bu aya dönmek için dokun")

            stepButton("chevron.right", enabled: canGoForward, label: "Sonraki ay") { shiftMonth(by: 1) }
        }
    }

    private func stepButton(_ symbol: String, enabled: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(enabled ? Theme.textSecondary : Theme.textMuted)
                .frame(width: 24, height: 24)
                .background(Theme.elevated, in: Circle())
                .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 1))
                .padding(4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .padding(-4)
        .accessibilityLabel(label)
    }

    private func shiftMonth(by delta: Int) {
        guard let target = Ledger.calendar.date(byAdding: .month, value: delta, to: month) else { return }
        if isEditingBudget { commitBudget() }
        withAnimation(Theme.spring) { month = Ledger.startOfMonth(target) }
        Haptics.selection()
    }

    private var monthLabel: String {
        let sameYear = Ledger.calendar.isDate(month, equalTo: .now, toGranularity: .year)
        let text = sameYear ? KurusDate.monthName(month) : KurusDate.monthYear(month)
        return text.uppercased(with: KurusDate.locale)
    }

    private var filterLabel: String {
        switch filter {
        case .all: return isFutureMonth ? "PLANLANAN" : "TÜM HARCAMALAR"
        case .cash: return "NAKİT"
        case .card(let id):
            return (store.card(id: id)?.pillTitle ?? "KART").uppercased(with: KurusDate.locale)
        }
    }

    private var headerTitle: String { "\(monthLabel) · \(filterLabel)" }

    private var scopeTitle: String {
        let scope: String
        switch filter {
        case .all: scope = "Tüm harcamalar"
        case .cash: scope = "Nakit"
        case .card(let id): scope = store.card(id: id)?.pillTitle ?? "Kart"
        }
        return "\(KurusDate.monthYear(month)) · \(scope)"
    }

    // MARK: - % rozeti → kategori analizi

    private func analysisChip(spend: Decimal, budget: Decimal) -> some View {
        let usage = budget > 0 ? (spend / budget).doubleValue : 0
        let tint: Color = filter != .all
            ? Theme.ocean
            : (usage > 1 ? Theme.coral : (usage > 0.8 ? Theme.amber : Theme.emerald))

        return Button {
            showBreakdown = true
            Haptics.selection()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chart.pie.fill")
                    .font(.system(size: 9, weight: .bold))
                if filter == .all {
                    Text("%\(Int((usage * 100).rounded()))")
                        .font(.system(size: 12, weight: .bold))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: usage))
                        .privacyBlur()
                }
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(tint.opacity(0.14), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Kategori analizi")
    }

    // MARK: - Bütçe limiti / gelir havuzu

    @ViewBuilder
    private func budgetLimit(budget: Decimal, incomeDriven: Bool) -> some View {
        if incomeDriven {
            // O ay gelir girildiyse limit = toplam gelir (salt okunur).
            AmountText(
                amount: budget,
                size: 17,
                weight: .semibold,
                color: Theme.emerald.opacity(0.75),
                showsFraction: false,
                prefix: "/ "
            )
            .privacyBlur()
            .accessibilityLabel("Bu ayın geliri \(CurrencyFormat.string(budget, fraction: false))")
        } else if isEditingBudget {
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

    private func budgetCaption(spend: Decimal, allSpend: Decimal, budget: Decimal, incomeDriven: Bool) -> some View {
        let remaining = budget - spend
        let pool = incomeDriven ? "Gelirden " : ""

        return Group {
            if filter != .all {
                let share = allSpend > 0 ? (spend / allSpend).doubleValue : 0
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease.circle.fill")
                        .foregroundStyle(Theme.ocean)
                    Text("Bu ayki harcamanın %\(Int((share * 100).rounded()))’i bu havuzda")
                }
            } else if isFutureMonth {
                HStack(spacing: 6) {
                    Image(systemName: "calendar.badge.clock")
                        .foregroundStyle(Theme.ocean)
                    Text("Taksit ve aboneliklerden tahmini yük")
                }
            } else if remaining < 0 {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.coral)
                    Text("\(incomeDriven ? "Gelir" : "Bütçe") \(CurrencyFormat.string(-remaining, fraction: false)) aşıldı")
                        .foregroundStyle(Theme.coral)
                }
            } else if isCurrentMonth {
                HStack(spacing: 6) {
                    Image(systemName: incomeDriven ? "arrow.down.left.circle.fill" : "gauge.with.dots.needle.33percent")
                        .foregroundStyle(Theme.emerald)
                    Text("\(pool)\(CurrencyFormat.string(remaining, fraction: false)) kaldı · günde \(CurrencyFormat.string(dailyAllowance(remaining), fraction: false))")
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.emerald)
                    Text("Ay kapandı · \(pool.lowercased(with: KurusDate.locale))\(CurrencyFormat.string(remaining, fraction: false)) arttı")
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
