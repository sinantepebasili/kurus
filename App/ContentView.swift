//
//  ContentView.swift
//  Kuruş / Cent — Ana ekran: soru sormayan canlı demo, özet, liste, sürtünmesiz düzenleme/silme
//
//  Hedef: App
//

import SwiftUI

struct ContentView: View {
    @Environment(SharedExpenseStore.self) private var store
    @Environment(StoreManager.self) private var storeManager
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("kurus.privacyMode") private var isPrivate = false

    @State private var inputText = ""
    /// Başarılı kayıttan sonra giriş alanını kesin olarak temizlemek için (bkz. SmartInputBarView.resetToken)
    @State private var inputResetToken = 0
    @FocusState private var inputFocused: Bool
    @State private var filter: CardFilter = .all
    @State private var selectedMonth = Ledger.startOfMonth(.now)

    @State private var showGuide = false
    @State private var categoryTarget: Expense?
    /// Pro kilidine takılan özellik → PaywallView (ilgili satır vurgulu)
    @State private var paywallFeature: ProFeature?

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

                SummaryCardView(
                    filter: $filter,
                    isPrivate: $isPrivate,
                    month: $selectedMonth,
                    onRequirePro: { paywallFeature = $0 }
                )
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
                                    Label(L("Sil", "Delete"), systemImage: "trash.fill")
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
                isDemoTyping: isDemoTyping,
                lockedFeature: lockedFeature(for:),
                resetToken: inputResetToken
            ) { parsed in
                commit(parsed, isDemo: false)
            }
        }
        .sheet(isPresented: $showGuide) {
            AutomationGuideSheet()
                .environment(storeManager)
        }
        .sheet(item: $paywallFeature) { feature in
            PaywallView(feature: feature)
                .environment(storeManager)
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
            if phase == .active {
                store.reloadFromDisk()
                Task { await storeManager.refreshEntitlements() }
            }
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
                .accessibilityLabel(AppLanguage.brandName)
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
            .accessibilityLabel(isPrivate ? L("Tutarları göster", "Show amounts") : L("Tutarları gizle", "Hide amounts"))

            Menu {
                if !storeManager.isPro {
                    Button {
                        paywallFeature = .general
                    } label: {
                        Label("\(AppLanguage.brandName) Pro", systemImage: "sparkles")
                    }
                    Divider()
                }

                Button {
                    showGuide = true
                } label: {
                    Label(L("Banka SMS Otomasyonu Rehberi", "Auto-Capture Guide (Apple Pay & SMS)"), systemImage: "text.bubble")
                }

                Divider()

                if storeManager.isPro {
                    ShareLink(
                        item: PDFExport(
                            month: selectedMonth,
                            expenses: Ledger.inMonth(store.expenses, of: selectedMonth),
                            cards: store.cards,
                            budget: Ledger.effectiveBudget(
                                Ledger.inMonth(store.expenses, of: selectedMonth),
                                manual: store.monthlyBudget
                            ),
                            fileName: "\(ExportManager.fileStem(for: selectedMonth))-\(L("Ekstre", "Statement")).pdf"
                        ),
                        preview: SharePreview(L("\(AppLanguage.brandName) Ekstresi", "\(AppLanguage.brandName) Statement"), image: Image(systemName: "doc.richtext"))
                    ) {
                        Label(L("Ekstre Oluştur (PDF)", "Create Statement (PDF)"), systemImage: "doc.richtext")
                    }

                    ShareLink(
                        item: CSVExport(
                            expenses: store.expenses,
                            cards: store.cards,
                            fileName: "\(ExportManager.fileStem()).csv"
                        ),
                        preview: SharePreview(L("\(AppLanguage.brandName) Harcamaları", "\(AppLanguage.brandName) Expenses"), image: Image(systemName: "tablecells"))
                    ) {
                        Label(L("Excel / CSV Paylaş", "Share Excel / CSV"), systemImage: "tablecells")
                    }
                } else {
                    // Ücretsiz planda dışa aktarma Pro sayfasını açar
                    Button {
                        paywallFeature = .export
                    } label: {
                        Label(L("Ekstre Oluştur (PDF)", "Create Statement (PDF)"), systemImage: "lock.fill")
                    }
                    Button {
                        paywallFeature = .export
                    } label: {
                        Label(L("Excel / CSV Paylaş", "Share Excel / CSV"), systemImage: "lock.fill")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .circleIcon()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("Menü", "Menu"))
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
                    Text(L("\(AppLanguage.brandName) böyle çalışır", "This is how \(AppLanguage.brandName) works"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(L("Yaz ve Return’e bas. Marka, kart ve taksit kendiliğinden anlaşılır.", "Type and hit Return. Brand, card and installments are understood automatically."))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button(action: clearAndStart) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                    Text(L("Temizle ve Başla", "Clear & Start"))
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
        if Ledger.isFutureMonth(selectedMonth) { return L("\(name) için planlı ödeme yok", "No scheduled payments for \(name)") }
        if !Ledger.isCurrentMonth(selectedMonth) { return L("\(name) ayında kayıt yok", "Nothing logged in \(name)") }
        return filter == .all
            ? L("Bu ay henüz harcama yok", "No expenses this month yet")
            : L("Bu havuzda bu ay harcama yok", "Nothing on this card this month")
    }

    private var emptySubtitle: String {
        if Ledger.isFutureMonth(selectedMonth) { return L("Taksitler ve abonelikler burada kendiliğinden belirir.", "Installments and subscriptions appear here automatically.") }
        if !Ledger.isCurrentMonth(selectedMonth) { return L("Bugüne dönmek için ay başlığına dokun.", "Tap the month title to jump back to today.") }
        return L("Aşağıya “Kahve 145” ya da “+Maaş 65000” yazıp Return’e bas.", "Type “Coffee 5” or “+Salary 5000” below and hit Return.")
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

    /// Ücretsiz planda bu giriş bir Pro özelliğine mi takılıyor?
    /// Taksit ("3t", "6 taksit") ya da ikinci bir kart → Pro. Yazı/dikte girişi her zaman serbest.
    private func lockedFeature(for parsed: ParsedExpense) -> ProFeature? {
        guard !storeManager.isPro else { return nil }
        if parsed.installmentCount > 1 { return .installments }
        if store.cards.count >= ProStatus.freeCardLimit, store.wouldCreateCard(for: parsed) {
            return .multipleCards
        }
        return nil
    }

    private func commit(_ parsed: ParsedExpense, isDemo: Bool) {
        // Kilitli özellik: metin kutuda kalır, yükseltince tek Return ile kaydedilir.
        if !isDemo, let feature = lockedFeature(for: parsed) {
            Haptics.warning()
            inputFocused = false
            paywallFeature = feature
            return
        }

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

        // Kayıt başarılı: giriş alanını temizle. Bağlam boşaltılır ve TextField yeniden oluşturulur;
        // yalnızca `inputText = ""` yapmak, Return sırasında alanın eski metni göstermesini engellemiyordu.
        inputText = ""
        inputResetToken &+= 1
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
        if url.host == "pro" {
            // Kilitli widget'tan gelindi
            if !storeManager.isPro { paywallFeature = .widgets }
            return
        }
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

            // Dile göre: "Kahve 145", "Migros 640", "Altın 4500" / "Coffee 5", "Whole Foods 85", "S&P 500 500"
            for phrase in QuickSamples.all.map(\.command) {
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
            .accessibilityLabel(L("Kategori: \(expense.category.title). Değiştirmek için dokun", "Category: \(expense.category.title). Tap to change"))

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
                        Text(L("Tahmini", "Projected"))
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(Theme.ocean)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.ocean.opacity(0.14), in: Capsule())
                            .fixedSize()
                    }
                    if expense.isDemo {
                        Text(L("Örnek", "Sample"))
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
                    prefix: expense.category.isIncome ? "+" : "",
                    currency: expense.currencyCode
                )
                if let installment = expense.installment {
                    Text(L("toplam", "total") + " " + CurrencyFormat.string(installment.total, fraction: false, currency: expense.currencyCode))
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
            parts.append(L("Nakit", "Cash"))
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
                    Text(L("Kategori seç", "Choose a category"))
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
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .minimumScaleFactor(0.75)
                                .frame(height: 28, alignment: .top)
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
        .presentationDetents([.height(580), .large])
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
            Text(L("Silindi", "Deleted"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("— \(state.title)")
                .font(.system(size: 15))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 8)
            Button(action: onUndo) {
                Text(L("Geri Al", "Undo"))
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
