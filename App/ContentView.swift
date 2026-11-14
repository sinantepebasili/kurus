//
//  ContentView.swift
//  Kuruş — Ana ekran: soru sormayan canlı demo, özet, liste, sürtünmesiz düzenleme/silme
//
//  Hedef: App
//

import SwiftUI

struct ContentView: View {
    @Environment(SharedExpenseStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("kurus.privacyMode") private var isPrivate = false

    @State private var inputText = ""
    @FocusState private var inputFocused: Bool
    @State private var filter: CardFilter = .all
    @State private var selectedMonth = Ledger.startOfMonth(.now)

    @State private var showGuide = false
    @State private var categoryTarget: Expense?

    @State private var toast: UndoToastState?
    @State private var toastTask: Task<Void, Never>?

    @State private var demoTask: Task<Void, Never>?
    @State private var isDemoTyping = false

    @State private var freshIDs: Set<UUID> = []

    // MARK: - Türetilmiş veri

    /// Seçili ayın kayıtları; gelecek aylarda tahmini abonelikler de dahil.
    private var monthEntries: (items: [Expense], projectedIDs: Set<UUID>) {
        Ledger.monthEntries(in: store.snapshot, month: selectedMonth)
    }

    private var visibleExpenses: [Expense] {
        monthEntries.items
            .filter { filter.includes($0) }
            .sorted { $0.date > $1.date }
    }

    private var dayGroups: [DayGroup] {
        let cal = Ledger.calendar
        return Dictionary(grouping: visibleExpenses) { cal.startOfDay(for: $0.date) }
            .map { DayGroup(day: $0.key, items: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.day > $1.day }
    }

    private var showsDemoBanner: Bool {
        !store.hasCompletedOnboarding && (isDemoTyping || store.expenses.contains { $0.isDemo })
    }

    // MARK: - Gövde

    var body: some View {
        let projectedIDs = monthEntries.projectedIDs

        ZStack(alignment: .bottom) {
            Theme.background.ignoresSafeArea()

            List {
                header
                    .plainRow(EdgeInsets(top: 8, leading: Theme.gutter, bottom: 6, trailing: Theme.gutter))

                SummaryCardView(filter: $filter, isPrivate: $isPrivate, month: $selectedMonth)
                    .plainRow(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))

                if showsDemoBanner {
                    demoBanner
                        .plainRow(EdgeInsets(top: 8, leading: Theme.gutter, bottom: 4, trailing: Theme.gutter))
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if dayGroups.isEmpty && !isDemoTyping {
                    emptyState
                        .plainRow(EdgeInsets(top: 28, leading: Theme.gutter, bottom: 0, trailing: Theme.gutter))
                }

                ForEach(dayGroups) { group in
                    dayHeader(group)
                        .plainRow(EdgeInsets(top: 18, leading: Theme.gutter + 4, bottom: 6, trailing: Theme.gutter + 4))

                    ForEach(group.items) { expense in
                        let isProjected = projectedIDs.contains(expense.id)
                        ExpenseRowView(
                            expense: expense,
                            card: expense.cardID.flatMap { store.card(id: $0) },
                            isFresh: freshIDs.contains(expense.id),
                            isProjected: isProjected,
                            onIconTap: {
                                // Tahmini kayıtlar kalıcı değildir; düzenlenemez.
                                guard !isProjected else { return }
                                Haptics.selection()
                                categoryTarget = expense
                            }
                        )
                        .plainRow(EdgeInsets(top: 3, leading: Theme.gutter, bottom: 3, trailing: Theme.gutter))
                        .swipeActions(edge: .trailing, allowsFullSwipe: !isProjected) {
                            if !isProjected {
                                Button(role: .destructive) {
                                    delete(expense)
                                } label: {
                                    Label("Sil", systemImage: "trash.fill")
                                }
                                .tint(Theme.coral)
                            }
                        }
                    }
                }

                Color.clear
                    .frame(height: 16)
                    .plainRow(EdgeInsets())
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .environment(\.defaultMinListRowHeight, 0)

            if let toast {
                UndoToast(state: toast) { undo(toast) }
                    .padding(.bottom, 10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .environment(\.privacyMode, isPrivate)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SmartInputBarView(
                text: $inputText,
                isFocused: $inputFocused,
                isDemoTyping: isDemoTyping
            ) { parsed in
                commit(parsed, isDemo: false)
            }
        }
        .sheet(isPresented: $showGuide) {
            AutomationGuideSheet()
        }
        .sheet(item: $categoryTarget) { expense in
            CategoryPickerSheet(expense: expense) { category in
                withAnimation(Theme.spring) { store.setCategory(category, for: expense) }
                Haptics.success()
                categoryTarget = nil
            }
        }
        .onAppear(perform: startDemoIfNeeded)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.reloadFromDisk() }
        }
        .onChange(of: inputFocused) { _, focused in
            // Kullanıcı demo sürerken yazmaya başlarsa demo anında çekilir.
            if focused && isDemoTyping { stopDemoTyping() }
        }
        .onOpenURL(perform: handle)
        .preferredColorScheme(.dark)
    }

    // MARK: - Üst başlık

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            BrandHeaderView()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Kuruş")
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 8)

            Button {
                withAnimation(Theme.spring) { isPrivate.toggle() }
                Haptics.tap()
            } label: {
                Image(systemName: isPrivate ? "eye.slash" : "eye")
                    .contentTransition(.symbolEffect(.replace))
                    .circleIcon()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPrivate ? "Tutarları göster" : "Tutarları gizle")

            Menu {
                Button {
                    showGuide = true
                } label: {
                    Label("Banka SMS Otomasyonu Rehberi", systemImage: "text.bubble")
                }

                Divider()

                ShareLink(
                    item: PDFExport(
                        month: selectedMonth,
                        expenses: Ledger.inMonth(store.expenses, of: selectedMonth),
                        cards: store.cards,
                        budget: Ledger.effectiveBudget(
                            Ledger.inMonth(store.expenses, of: selectedMonth),
                            manual: store.monthlyBudget
                        ),
                        fileName: "\(ExportManager.fileStem(for: selectedMonth))-Ekstre.pdf"
                    ),
                    preview: SharePreview("Kuruş Ekstresi", image: Image(systemName: "doc.richtext"))
                ) {
                    Label("Ekstre Oluştur (PDF)", systemImage: "doc.richtext")
                }

                ShareLink(
                    item: CSVExport(
                        expenses: store.expenses,
                        cards: store.cards,
                        fileName: "\(ExportManager.fileStem()).csv"
                    ),
                    preview: SharePreview("Kuruş Harcamaları", image: Image(systemName: "tablecells"))
                ) {
                    Label("Excel / CSV Paylaş", systemImage: "tablecells")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .circleIcon()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Menü")
        }
    }

    // MARK: - Demo afişi

    private var demoBanner: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.amber)
                    .frame(width: 34, height: 34)
                    .background(Theme.amber.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Kuruş böyle çalışır")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Yaz ve Return’e bas. Marka, kart ve taksit kendiliğinden anlaşılır.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button(action: clearAndStart) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                    Text("Temizle ve Başla")
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.background)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(Theme.textPrimary, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .craftCard(radius: 18, fill: Theme.elevated)
    }

    // MARK: - Boş durum

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "text.cursor")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.textMuted)
            Text(emptyTitle)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(emptySubtitle)
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private var emptyTitle: String {
        let name = KurusDate.monthName(selectedMonth)
        if Ledger.isFutureMonth(selectedMonth) { return "\(name) için planlı ödeme yok" }
        if !Ledger.isCurrentMonth(selectedMonth) { return "\(name) ayında kayıt yok" }
        return filter == .all ? "Bu ay henüz harcama yok" : "Bu havuzda bu ay harcama yok"
    }

    private var emptySubtitle: String {
        if Ledger.isFutureMonth(selectedMonth) { return "Taksitler ve abonelikler burada kendiliğinden belirir." }
        if !Ledger.isCurrentMonth(selectedMonth) { return "Bugüne dönmek için ay başlığına dokun." }
        return "Aşağıya “Kahve 145” ya da “+Maaş 65000” yazıp Return’e bas."
    }

    private func dayHeader(_ group: DayGroup) -> some View {
        HStack {
            Text(KurusDate.dayHeader(group.day))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            let spent = Ledger.spending(group.items)
            let earned = Ledger.income(group.items)
            if spent > 0 || earned == 0 {
                AmountText(amount: spent, size: 13, weight: .semibold, color: Theme.textSecondary, showsFraction: false)
                    .privacyBlur()
            } else {
                AmountText(amount: earned, size: 13, weight: .semibold, color: Theme.emerald.opacity(0.8), showsFraction: false, prefix: "+")
                    .privacyBlur()
            }
        }
    }

    // MARK: - Eylemler

    private func commit(_ parsed: ParsedExpense, isDemo: Bool) {
        let created = withAnimation(Theme.spring) {
            store.add(parsed, isDemo: isDemo)
        }
        guard let first = created.first else { return }

        // Geçmiş/gelecek bir ay açıkken eklenen kayıt bugüne düşer: kullanıcı onu görsün.
        if !Ledger.isCurrentMonth(selectedMonth) {
            withAnimation(Theme.spring) { selectedMonth = Ledger.startOfMonth(.now) }
        }

        if !filter.includes(first) {
            withAnimation(Theme.spring) { filter = .all }
        }

        withAnimation(Theme.spring) { inputText = "" }
        markFresh(created.map(\.id))

        if !isDemo {
            Haptics.success()
            // Hızlı art arda giriş için klavye açık kalır.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(60))
                inputFocused = true
            }
        }
    }

    private func delete(_ expense: Expense) {
        let removed = withAnimation(Theme.spring) { store.delete(expense) }
        guard !removed.isEmpty else { return }
        Haptics.warning()
        showToast(UndoToastState(title: expense.title, removed: removed))
    }

    private func undo(_ state: UndoToastState) {
        toastTask?.cancel()
        withAnimation(Theme.spring) {
            store.restore(state.removed)
            toast = nil
        }
        markFresh(state.removed.map(\.id))
        Haptics.success()
    }

    private func showToast(_ state: UndoToastState) {
        toastTask?.cancel()
        withAnimation(Theme.spring) { toast = state }
        toastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(Theme.spring) { toast = nil }
        }
    }

    private func markFresh(_ ids: [UUID]) {
        withAnimation(Theme.spring) { freshIDs.formUnion(ids) }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1400))
            withAnimation(.easeOut(duration: 0.6)) { freshIDs.subtract(ids) }
        }
    }

    private func handle(_ url: URL) {
        guard url.scheme == "kurus" else { return }
        if url.host == "quick-add" {
            if isDemoTyping || store.expenses.contains(where: { $0.isDemo }) { clearAndStart() }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                inputFocused = true
            }
        }
    }

    // MARK: - Soru sormayan canlı açılış demosu

    private func startDemoIfNeeded() {
        guard !store.hasCompletedOnboarding, store.expenses.isEmpty, demoTask == nil else { return }

        demoTask = Task { @MainActor in
            withAnimation(Theme.spring) { isDemoTyping = true }
            try? await Task.sleep(for: .milliseconds(800))

            for phrase in ["Netflix 229", "Turkcell 450"] {
                for character in phrase {
                    guard !Task.isCancelled else { return }
                    inputText.append(character)
                    try? await Task.sleep(for: .milliseconds(85))
                }
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled, let parsed = ExpenseParser.parse(inputText) else { return }
                commit(parsed, isDemo: true)
                Haptics.tap()
                try? await Task.sleep(for: .milliseconds(700))
            }

            guard !Task.isCancelled else { return }
            withAnimation(Theme.spring) { isDemoTyping = false }
            demoTask = nil
        }
    }

    private func stopDemoTyping() {
        demoTask?.cancel()
        demoTask = nil
        inputText = ""
        withAnimation(Theme.spring) { isDemoTyping = false }
    }

    private func clearAndStart() {
        stopDemoTyping()
        withAnimation(Theme.spring) { store.clearDemo() }
        Haptics.tap()
        inputFocused = true
    }
}

// MARK: - Gün grubu

private struct DayGroup: Identifiable {
    let day: Date
    let items: [Expense]
    var id: Date { day }
}

// MARK: - Harcama satırı

struct ExpenseRowView: View {
    let expense: Expense
    let card: PaymentCard?
    var isFresh: Bool = false
    var isProjected: Bool = false
    var onIconTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onIconTap) {
                ExpenseBadge(brand: expense.brand, category: expense.category, size: 42)
                    .overlay(alignment: .bottomTrailing) {
                        if expense.isRecurring {
                            Image(systemName: "repeat")
                                .font(.system(size: 8, weight: .heavy))
                                .foregroundStyle(Theme.violet)
                                .frame(width: 17, height: 17)
                                .background(Theme.elevated, in: Circle())
                                .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 1))
                                .offset(x: 5, y: 5)
                        }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Kategori: \(expense.category.title). Değiştirmek için dokun")

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(expense.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    if let installment = expense.installment {
                        Text(installment.label)
                            .font(.system(size: 10.5, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.amber)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.amber.opacity(0.14), in: Capsule())
                            .fixedSize()
                    }
                    if isProjected {
                        Text("Tahmini")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(Theme.ocean)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.ocean.opacity(0.14), in: Capsule())
                            .fixedSize()
                    }
                    if expense.isDemo {
                        Text("Örnek")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.elevated, in: Capsule())
                            .fixedSize()
                    }
                }

                Text(subtitle)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                AmountText(
                    amount: expense.amount,
                    size: 16,
                    weight: .semibold,
                    color: amountColor,
                    prefix: expense.category.isIncome ? "+" : ""
                )
                if let installment = expense.installment {
                    Text("toplam \(CurrencyFormat.string(installment.total, fraction: false))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textMuted)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
            .privacyBlur()
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .craftCard(radius: Theme.rowRadius)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous)
                .strokeBorder(Theme.emerald.opacity(isFresh ? 0.55 : 0), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .opacity(isProjected ? 0.72 : 1)
    }

    private var amountColor: Color {
        if expense.category.isIncome { return Theme.emerald }
        if expense.category.isSavings { return Theme.violet }
        return Theme.textPrimary
    }

    private var subtitle: String {
        var parts = [expense.category.title]
        if let card {
            parts.append(card.pillTitle)
        } else if !expense.category.isIncome {
            parts.append("Nakit")
        }
        // Tahmini kayıtlarda saat anlamsız; gün gösterilir.
        parts.append(isProjected ? KurusDate.shortDay(expense.date) : KurusDate.time(expense.date))
        return parts.joined(separator: " · ")
    }
}

// MARK: - Kategori seçici

struct CategoryPickerSheet: View {
    let expense: Expense
    var onPick: (ExpenseCategory) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                ExpenseBadge(brand: expense.brand, category: expense.category, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(expense.title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text("Kategori seç")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(ExpenseCategory.allCases) { category in
                    let selected = category == expense.category
                    Button {
                        onPick(category)
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: category.symbol)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(category.color)
                                .frame(width: 42, height: 42)
                                .background(category.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                            Text(category.title)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(selected ? Theme.elevated : Color.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(selected ? Theme.hairline : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(Theme.gutter)
        .padding(.top, 8)
        .presentationDetents([.height(470), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.surface)
        .presentationCornerRadius(28)
    }
}

// MARK: - "Silindi — Geri Al" bildirimi

struct UndoToastState: Equatable {
    let id = UUID()
    let title: String
    let removed: [Expense]
}

struct UndoToast: View {
    let state: UndoToastState
    var onUndo: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "trash.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.coral)
            Text("Silindi")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("— \(state.title)")
                .font(.system(size: 15))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 8)
            Button(action: onUndo) {
                Text("Geri Al")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.emerald)
                    .padding(.horizontal, 6)
                    .frame(height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .frame(height: 50)
        .background(Theme.elevated, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
        .padding(.horizontal, Theme.gutter)
    }
}

// MARK: - Yardımcılar

private extension View {
    func plainRow(_ insets: EdgeInsets) -> some View {
        self
            .listRowInsets(insets)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    /// Üst başlık ikonları: arka plansız, 44pt dokunma alanı.
    func circleIcon() -> some View {
        self
            .font(.system(size: 21, weight: .regular))
            .foregroundStyle(Theme.textPrimary)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }
}
