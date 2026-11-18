//
//  SettingsSheetView.swift
//  Kuruş / Cent — Ayarlar & Abonelik (satın alma sonrası yönetim)
//
//  Hedef: App
//
//  • Üyelik Durumu: aktif plan, yenilenme / sona erme tarihi, Aboneliği Yönet (yerel
//    .manageSubscriptionsSheet), Pro'ya Geç, Satın Alımları Geri Yükle (App Review 3.1.1)
//  • Nasıl Kullanılır?: dört örnek komut (Heuristic #10)
//  • iCloud & Veri Yönetimi: iCloud durumu, kayıtlı kartlar (düzenle / sil), "Tüm Verileri Sıfırla"
//  • Hakkında: Gizlilik Politikası, Apple Standart EULA ve sürüm / build numarası
//

import StoreKit
import SwiftUI

struct SettingsSheetView: View {
    @Environment(SharedExpenseStore.self) private var store
    @Environment(StoreManager.self) private var storeManager
    @Environment(\.dismiss) private var dismiss

    @State private var showPaywall = false
    @State private var showManageSubscriptions = false
    @State private var confirmReset = false
    @State private var didReset = false
    @State private var editingCard: CardEditTarget?
    @State private var pendingDelete: PaymentCard?
    @State private var showAddCard = false

    private var brand: String { AppLanguage.brandName }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    membershipSection
                    tipsSection
                    dataSection
                    legalSection
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 6)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background(Theme.background)
            .navigationTitle(L("Ayarlar & Abonelik", "Settings & Subscription"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("Bitti", "Done")) { dismiss() }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.emerald)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.background)
        .presentationCornerRadius(28)
        .preferredColorScheme(.dark)
        .tint(Theme.emerald)
        // Yerel abonelik yönetimi (iptal, plan değiştirme) — App Store'un kendi sayfası
        .manageSubscriptionsSheet(isPresented: $showManageSubscriptions)
        .onChange(of: showManageSubscriptions) { _, isShowing in
            // Sayfa kapanınca iptal / plan değişikliği hemen yansısın
            if !isShowing { Task { await storeManager.refreshEntitlements() } }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(feature: .general)
                .environment(storeManager)
                .environment(store)
        }
        .sheet(isPresented: $showAddCard) {
            AddCardSheet()
                .environment(store)
                .environment(storeManager)
        }
        .sheet(item: $editingCard) { target in
            CardEditorSheet(cardID: target.id)
                .environment(store)
        }
        .confirmationDialog(
            L("Tüm Verileri Sıfırla", "Reset All Data"),
            isPresented: $confirmReset,
            titleVisibility: .visible
        ) {
            Button(L("Tüm Verileri Sil", "Delete All Data"), role: .destructive) {
                withAnimation(Theme.spring) {
                    store.resetAllData()
                    didReset = true
                }
                Haptics.success()
            }
            Button(L("Vazgeç", "Cancel"), role: .cancel) {}
        } message: {
            Text(L(
                "Tüm harcama, kart ve bütçe kayıtlarınız cihazınızdan ve iCloud’dan kalıcı olarak silinecektir. Emin misiniz?",
                "All of your expenses, cards and budget will be permanently deleted from this device and iCloud. Are you sure?"
            ))
        }
        .task { await storeManager.refreshEntitlements() }
        .onDisappear { storeManager.clearRestoreState() }
    }

    // MARK: - Üyelik Durumu

    private var membershipSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(L("ÜYELİK DURUMU", "MEMBERSHIP"))

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: storeManager.isPro ? "checkmark.seal.fill" : "sparkles")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(storeManager.isPro ? Theme.emerald : Theme.textSecondary)
                        .frame(width: 38, height: 38)
                        .background(
                            (storeManager.isPro ? Theme.emerald : Theme.textSecondary).opacity(0.14),
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text(planTitle)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(storeManager.isPro ? Theme.emerald : Theme.textPrimary)
                        Text(statusLine)
                            .font(.system(size: 13))
                            .foregroundStyle(statusIsWarning ? Theme.amber : Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }

                if storeManager.activePlan?.isSubscription == true {
                    Button {
                        showManageSubscriptions = true
                    } label: {
                        actionLabel(L("Aboneliği Yönet / İptal Et", "Manage / Cancel Subscription"), symbol: "creditcard.and.123")
                    }
                    .buttonStyle(SpringPressStyle())
                } else if !storeManager.isPro {
                    Button {
                        Haptics.tap()
                        showPaywall = true
                    } label: {
                        Text(L("\(brand) Pro’ya Geç", "Upgrade to \(brand) Pro"))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.background)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(Theme.textPrimary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(SpringPressStyle())
                }

                Button {
                    Task { await storeManager.restorePurchases() }
                } label: {
                    HStack(spacing: 8) {
                        if storeManager.isRestoring {
                            ProgressView().controlSize(.small).tint(Theme.textPrimary)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        Text(L("Satın Alımları Geri Yükle", "Restore Purchases"))
                            .font(.system(size: 15, weight: .medium))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(storeManager.isRestoring || storeManager.isPurchasing)

                if let message = storeManager.restoreState.message {
                    Text(message)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(storeManager.restoreState.isError ? Theme.coral : Theme.emerald)
                        .transition(.opacity)
                }

                // Satın alma bu sayfadan yapılmadıysa (ör. geri yükleme) teklif burada bir kez sunulur
                if storeManager.shouldOfferSelfExpense, let plan = storeManager.activePlan {
                    ProSelfExpenseOffer(plan: plan)
                        .transition(.opacity)
                }
            }
            .padding(16)
            .craftCard(radius: 18)
            .animation(Theme.spring, value: storeManager.restoreState)
            .animation(Theme.spring, value: storeManager.isPro)
        }
    }

    private var planTitle: String {
        if let plan = storeManager.activePlan { return plan.membershipTitle }
        return storeManager.isPro ? "\(brand) Pro" : L("Ücretsiz Plan", "Free Plan")
    }

    /// Aboneliği iptal edilmiş (otomatik yenileme kapalı) ise uyarı tonu
    private var statusIsWarning: Bool {
        storeManager.activePlan?.isSubscription == true && storeManager.willAutoRenew == false
    }

    private var statusLine: String {
        guard storeManager.isPro else {
            return L(
                "Yazı ve sesli giriş, iCloud yedekleme ve bu ayın analizi ücretsiz.",
                "Typing and dictation, iCloud backup and this month’s breakdown are free."
            )
        }
        switch storeManager.activePlan {
        case .lifetime?:
            return L("Tek seferlik satın alma · süresiz erişim", "One-time purchase · access forever")
        case .monthly?, .yearly?:
            guard let date = storeManager.expirationDate else {
                return L("Abonelik aktif", "Subscription active")
            }
            let day = date.formatted(.dateTime.day().month(.wide).year().locale(KurusDate.locale))
            switch storeManager.willAutoRenew {
            case true?: return L("\(day) tarihinde yenilenecek", "Renews on \(day)")
            case false?: return L("\(day) tarihinde sona erecek", "Expires on \(day)")
            case nil: return L("Dönem sonu: \(day)", "Current period ends \(day)")
            }
        case nil:
            return L("Pro aktif", "Pro is active")
        }
    }

    // MARK: - Nasıl Kullanılır? (Heuristic #10 — yardım ve dokümantasyon)

    private var tipsSection: some View {
        let tips: [(command: String, meaning: String)] = AppLanguage.isTurkish
            ? [
                ("Kahve 85", "Tutar ve başlık; kategori ile marka kendiliğinden"),
                ("Kahve 85 bonus", "Kart adı her zaman tutardan sonra yazılır"),
                ("+Maaş 65000", "Başta + ile gelir; o ayın bütçesi olur"),
                ("Market 450 dün", "“dün” yazınca dünün tarihiyle kaydedilir"),
                ("Telefon 36000 3t", "Taksitler gelecek aylara bölünür (Pro)"),
            ]
            : [
                ("Coffee 5", "Amount and title; category and brand are detected"),
                ("Coffee 5 chase", "The card name always goes after the amount"),
                ("+Salary 5000", "A leading + logs income; it becomes the month’s budget"),
                ("Lunch 12 yesterday", "“yesterday” logs it with yesterday’s date"),
                ("Laptop 1200 3x", "Installments are spread over the coming months (Pro)"),
            ]

        return VStack(alignment: .leading, spacing: 8) {
            sectionHeader(L("NASIL KULLANILIR? (İPUÇLARI)", "HOW TO USE (TIPS)"))

            VStack(alignment: .leading, spacing: 12) {
                ForEach(tips, id: \.command) { tip in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(tip.command)
                            .font(.system(size: 13.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.emerald)
                            .fixedSize()
                        Text(tip.meaning)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
                Text(L("Kart haplarına basılı tutarak kartın adını, hesap kesim gününü düzenleyebilir ya da kartı silebilirsin.",
                       "Touch and hold a card chip to rename it, set its statement day or delete it."))
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .craftCard(radius: 18)
        }
    }

    // MARK: - iCloud & Veri Yönetimi

    /// iCloud hesabı açık mı? (Anahtar-değer eşitlemesi kişisel iCloud hesabıyla çalışır)
    private var isICloudAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(L("iCLOUD & VERİ YÖNETİMİ", "iCLOUD & DATA"))

            // iCloud durumu (Heuristic #1)
            HStack(spacing: 12) {
                Image(systemName: isICloudAvailable ? "icloud.fill" : "icloud.slash.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isICloudAvailable ? Theme.emerald : Theme.amber)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isICloudAvailable
                         ? L("iCloud Senkronizasyonu: Aktif", "iCloud Sync: On")
                         : L("iCloud Senkronizasyonu: Kapalı", "iCloud Sync: Off"))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Text(isICloudAvailable
                         ? L("Kayıtlar kişisel iCloud hesabınla eşitleniyor.", "Records sync with your personal iCloud account.")
                         : L("Yalnızca bu cihazda. Ayarlar › [Adın] › iCloud’dan açabilirsin.", "This device only. Turn it on in Settings › [Your Name] › iCloud."))
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .craftCard(radius: 16)
            .accessibilityElement(children: .combine)

            // Kayıtlı kartlar
            VStack(spacing: 0) {
                if store.cards.isEmpty {
                    Text(L("Henüz kart yok. Banka SMS’i ya da “Kahve 85 bonus” gibi bir girişle kendiliğinden eklenir; listede olmayan kartını aşağıdan ekleyebilirsin.",
                           "No cards yet. They’re added automatically from a bank SMS or an entry like “Coffee 5 chase”; add a card that isn’t recognized below."))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(Array(store.cards.enumerated()), id: \.element.id) { index, card in
                        if index > 0 {
                            Rectangle().fill(Theme.hairline).frame(height: 1).padding(.leading, 50)
                        }
                        cardRow(card)
                    }
                }
            }
            .craftCard(radius: 16)
            // Ayrı görünümde: sayfadaki "Tüm Verileri Sıfırla" onayıyla çakışmasın
            .cardDeletionDialog(card: $pendingDelete)

            // Listede olmayan banka / kart (ör. Nkolay): adı ayrıştırıcının kart sözlüğüne girer.
            Button {
                showAddCard = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                    Text(L("Kart Ekle", "Add Card"))
                        .font(.system(size: 15, weight: .semibold))
                    Spacer(minLength: 0)
                    if !storeManager.isPro && store.realCardCount >= ProStatus.freeCardLimit {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.textMuted)
                            .accessibilityLabel("Pro")
                    }
                }
                .foregroundStyle(Theme.emerald)
                .padding(.horizontal, 16)
                .frame(height: 50)
                .craftCard(radius: 16)
            }
            .buttonStyle(.plain)

            Button(role: .destructive) {
                confirmReset = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text(L("Tüm Verileri Sıfırla", "Reset All Data"))
                        .font(.system(size: 15, weight: .semibold))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Theme.coral)
                .padding(.horizontal, 16)
                .frame(height: 50)
                .craftCard(radius: 16)
            }
            .buttonStyle(.plain)

            Text(didReset
                ? L("Tüm kayıtlar bu cihazdan ve iCloud’dan silindi.", "All records were deleted from this device and iCloud.")
                : L("Kayıtlarınız yalnızca bu cihazda ve kişisel iCloud hesabınızda tutulur.",
                    "Your records are kept only on this device and in your personal iCloud account."))
                .font(.system(size: 12.5))
                .foregroundStyle(didReset ? Theme.emerald : Theme.textSecondary)
                .padding(.horizontal, 4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func cardRow(_ card: PaymentCard) -> some View {
        let count = store.expenseCount(forCard: card.id)
        return HStack(spacing: 12) {
            Button {
                editingCard = CardEditTarget(id: card.id)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "creditcard.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.ocean)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(card.pillTitle)
                            .font(.system(size: 15, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Text([
                            card.statementDay.map { L("Hesap kesimi: her ayın \($0). günü", "Statement: day \($0)") }
                                ?? L("Hesap kesim günü yok", "No statement day"),
                            L("\(count) harcama", "\(count) expense(s)"),
                        ].joined(separator: " · "))
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(L("Düzenlemek için dokun", "Tap to edit"))

            Button {
                pendingDelete = card
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.coral)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("\(card.pillTitle) kartını sil", "Delete \(card.pillTitle)"))
        }
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
    }

    // MARK: - Hakkında (yasal & sürüm)

    private var legalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(L("HAKKINDA", "ABOUT"))

            VStack(spacing: 0) {
                legalRow(L("Gizlilik Politikası", "Privacy Policy"), symbol: "hand.raised.fill", url: LegalLinks.privacy)
                Rectangle().fill(Theme.hairline).frame(height: 1).padding(.leading, 48)
                legalRow(L("Kullanım Koşulları (EULA)", "Terms of Use (EULA)"), symbol: "doc.text.fill", url: LegalLinks.terms)
            }
            .craftCard(radius: 16)

            Text("\(brand) \(versionString)")
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(Theme.textMuted)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
        }
    }

    private func legalRow(_ title: String, symbol: String, url: URL) -> some View {
        Link(destination: url) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 24)
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .contentShape(Rectangle())
        }
    }

    /// Bundle.main → "v1.0 (2)"
    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "v\(version) (\(build))"
    }

    // MARK: - Yardımcılar

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 4)
    }

    private func actionLabel(_ title: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textMuted)
        }
        .foregroundStyle(Theme.emerald)
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(Theme.emerald.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.emerald.opacity(0.25), lineWidth: 1))
    }
}

// MARK: - Kart Ekle

/// Ayarlar → "Kart Ekle". Banka sözlüğünde olmayan kartlar ("Nkolay") için: verilen ad,
/// tutardan sonra yazılınca bu karta bağlanır ("Kahve 85 Nkolay").
struct AddCardSheet: View {
    @Environment(SharedExpenseStore.self) private var store
    @Environment(StoreManager.self) private var storeManager
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var last4 = ""
    @State private var errorText: String?
    @State private var showPaywall = false
    @FocusState private var focusedField: Field?

    private enum Field { case name, last4 }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var exampleName: String { trimmedName.isEmpty ? "Nkolay" : trimmedName }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                field(
                    title: L("KART ADI", "CARD NAME"),
                    prompt: L("Örn. Nkolay", "e.g. Chime"),
                    text: $name,
                    focus: .name
                )
                .onChange(of: name) { _, newValue in
                    errorText = nil
                    if newValue.count > 24 { name = String(newValue.prefix(24)) }
                }

                field(
                    title: L("SON 4 HANE (İSTEĞE BAĞLI)", "LAST 4 DIGITS (OPTIONAL)"),
                    prompt: "1234",
                    text: $last4,
                    focus: .last4,
                    keyboard: .numberPad
                )
                .onChange(of: last4) { _, newValue in
                    errorText = nil
                    let digits = String(newValue.filter { $0.isASCII && $0.isNumber }.prefix(4))
                    if digits != newValue { last4 = digits }
                }

                if let errorText {
                    Label(errorText, systemImage: "exclamationmark.circle.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.amber)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                }

                // Kısa ve ayırt edici ad; harcamanın SONUNA yazılır (Heuristic #10)
                Text(L(
                    "Kısa ve ayırt edici bir ad ver. Harcamanın sonuna yazınca bu karta kaydedilir: “Kahve 85 \(exampleName)”. Son 4 hane, banka SMS’lerini de bu karta bağlar.",
                    "Use a short, distinctive name. Type it after the amount to log to this card: “Coffee 5 \(exampleName)”. The last 4 digits also match bank notifications to this card."
                ))
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(Theme.gutter)
            .background(Theme.surface)
            .navigationTitle(L("Kart Ekle", "Add Card"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.surface, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L("Vazgeç", "Cancel")) { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("Ekle", "Add"), action: save)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.emerald)
                        .disabled(trimmedName.count < 2)
                }
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(feature: .multipleCards)
                .environment(storeManager)
                .environment(store)
        }
        .presentationDetents([.height(400)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.surface)
        .presentationCornerRadius(28)
        .onAppear { focusedField = .name }
    }

    private func field(title: String, prompt: String, text: Binding<String>, focus: Field,
                       keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Theme.textSecondary)
            TextField(text: text, prompt: Text(prompt).foregroundStyle(Theme.textMuted)) {
                Text(title)
            }
            .font(.system(size: 16, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(Theme.textPrimary)
            .tint(Theme.emerald)
            .autocorrectionDisabled()
            .keyboardType(keyboard)
            .focused($focusedField, equals: focus)
            .submitLabel(focus == .name ? .next : .done)
            .onSubmit {
                if focus == .name { focusedField = .last4 } else { save() }
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
        }
    }

    private func save() {
        let allowNew = storeManager.isPro || store.realCardCount < ProStatus.freeCardLimit
        let result = withAnimation(Theme.spring) {
            store.addCard(name: name, last4: last4.isEmpty ? nil : last4, allowNewCard: allowNew)
        }
        switch result {
        case .success:
            Haptics.success()
            dismiss()
        case .failure(let error):
            Haptics.warning()
            withAnimation(Theme.spring) {
                switch error {
                case .invalidName:
                    errorText = L("En az 2 harfli, “Kart” ya da “Nakit” dışında bir ad yaz.",
                                  "Enter a name with at least 2 letters, other than “Card” or “Cash”.")
                case .invalidLast4:
                    errorText = L("Son 4 hane tam 4 rakam olmalı ya da boş kalmalı.",
                                  "The last 4 digits must be exactly 4 numbers, or left empty.")
                case .duplicate:
                    errorText = L("Bu kart zaten kayıtlı.", "This card is already saved.")
                case .limitReached:
                    errorText = nil
                    focusedField = nil
                    showPaywall = true
                }
            }
        }
    }
}
