//
//  PaywallView.swift
//  Kuruş / Cent — Sakin, iCloud+ sadeliğinde Pro sayfası
//
//  Hedef: App
//
//  Bağırmayan, kolay kapatılan bir sayfa: logo, tek cümlelik değer önerisi, 4 süper güç,
//  3 ince plan satırı (varsayılan: Ömür Boyu), tek "Devam Et" butonu ve App Store Review'un
//  istediği geri yükleme / koşullar / gizlilik bağlantıları.
//

import SwiftUI

enum LegalLinks {
    /// Apple'ın standart son kullanıcı lisans sözleşmesi (özel EULA tanımlanmadıysa geçerli olan)
    static let terms = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    /// Depodaki PRIVACY.md — App Store Connect'teki Gizlilik Politikası URL'siyle aynı olmalı
    static let privacy = URL(string: "https://github.com/sinantepebasili/kurus/blob/main/PRIVACY.md")!
}

struct PaywallView: View {
    var feature: ProFeature = .general

    @Environment(StoreManager.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var selected: StoreManager.Plan = .lifetime
    /// Bu sayfadan yapılan başarılı satın alma → teşekkür + "gider olarak ekle" teklifi
    @State private var purchasedPlan: StoreManager.Plan?
    /// Satın alma sürerken isPro değişse de sayfa kendiliğinden kapanmasın
    @State private var awaitingPurchase = false
    /// Kısa ekran (iPhone SE): özellik satırları ve üst boşluk biraz daha sıkılaşır
    @State private var isCompactHeight = false

    private var brand: String { AppLanguage.brandName }

    var body: some View {
        Group {
            if let plan = purchasedPlan {
                ProWelcomeView(plan: plan) { dismiss() }
                    .transition(.opacity)
            } else {
                shopContent
            }
        }
        .background(Theme.background)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.background)
        .presentationCornerRadius(28)
        .preferredColorScheme(.dark)
        .onChange(of: store.isPro) { _, isPro in
            // Geri yükleme ya da başka cihazdan gelen alım: sayfa kapanır.
            // Bu sayfadan yapılan alım: teşekkür ekranı gösterilir.
            if isPro, !awaitingPurchase, purchasedPlan == nil { dismiss() }
        }
        .task {
            if store.products.isEmpty { await store.loadProducts() }
        }
        .onDisappear { store.clearRestoreState() }
    }

    private var shopContent: some View {
        ScrollView {
            // Kompakt kompozisyon: iPhone 13–16'da logo, 4 özellik, 3 plan ve "Devam Et" kaydırmadan görünür.
            // Yalnızca SE gibi çok küçük ekranlarda ScrollView devreye girer.
            VStack(spacing: 12) {
                header
                powers
                planPicker
                legalNote
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, isCompactHeight ? 12 : 18)
            .padding(.bottom, 8)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { isCompactHeight = proxy.size.height < 700 }
                    .onChange(of: proxy.size.height) { _, height in isCompactHeight = height < 700 }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        .overlay(alignment: .topTrailing) { closeButton }
    }

    // MARK: - Üst bölüm

    private var header: some View {
        VStack(spacing: 6) {
            KurusMarkShape(size: 28)
                .padding(7)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))

            Text("\(brand) Pro")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .tracking(-0.6)
                .foregroundStyle(Theme.textPrimary)

            Text(L(
                "Otomatik SMS yakalama, taksit takibi ve interaktif widget’larla tam kontrol.",
                "Full control with automatic SMS capture, installment tracking and interactive widgets."
            ))
            .font(.system(size: 14))
            .foregroundStyle(Theme.textSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 4 süper güç

    private var powers: some View {
        let rows: [(symbol: String, tint: Color, text: String)] = [
            ("wand.and.stars", Theme.emerald, L(
                "Banka SMS’i ile otomatik harcama ve kart yakalama",
                "Automatic expense & card capture from bank SMS and Apple Pay")),
            ("creditcard.fill", Theme.ocean, L(
                "Taksit bölme (3t) ve sınırsız kart ayrımı",
                "Installment splitting (3x) and unlimited cards")),
            ("calendar.badge.clock", Theme.amber, L(
                "Geçmiş aylar arşivi ve gelecek ay taksit yükü",
                "Past-month archive and upcoming installment load")),
            ("square.grid.2x2.fill", Theme.violet, L(
                "İnteraktif ana ekran widget’ları ve PDF/Excel çıktı",
                "Interactive Home Screen widgets and PDF/Excel export")),
        ]

        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 {
                    Rectangle().fill(Theme.hairline).frame(height: 1).padding(.leading, 40)
                }
                let highlighted = feature.highlightIndex == index
                HStack(spacing: 12) {
                    Image(systemName: row.symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(row.tint)
                        .frame(width: 28, height: 28)
                        .background(row.tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 8.5, style: .continuous))
                    Text(row.text)
                        .font(.system(size: 13.5, weight: highlighted ? .semibold : .medium))
                        .foregroundStyle(highlighted ? Theme.textPrimary : Theme.textPrimary.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if highlighted {
                        Image(systemName: "lock.open.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.emerald)
                    }
                }
                .padding(.vertical, isCompactHeight ? 6 : 8)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 3)
        .craftCard(radius: 18)
    }

    // MARK: - Plan seçici (iCloud+ tarzı ince satırlar)

    private var planPicker: some View {
        VStack(spacing: 0) {
            ForEach(Array(StoreManager.Plan.allCases.enumerated()), id: \.element.id) { index, plan in
                if index > 0 {
                    Rectangle().fill(Theme.hairline).frame(height: 1).padding(.leading, 45)
                }
                planRow(plan)
            }
        }
        .craftCard(radius: 18)
    }

    private func planRow(_ plan: StoreManager.Plan) -> some View {
        let isSelected = plan == selected
        return Button {
            guard selected != plan else { return }
            withAnimation(Theme.spring) { selected = plan }
            Haptics.selection()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(isSelected ? Theme.emerald : Theme.textMuted)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title(for: plan))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        if let badge = badge(for: plan) {
                            Text(badge)
                                .font(.system(size: 10.5, weight: .bold))
                                .foregroundStyle(Theme.emerald)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2.5)
                                .background(Theme.emerald.opacity(0.15), in: Capsule())
                                .fixedSize()
                        }
                    }
                    Text(caption(for: plan))
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                Spacer(minLength: 8)

                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(store.displayPrice(for: plan))
                        .font(.system(size: 16, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                    Text(periodSuffix(for: plan))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .fixedSize()
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 11)
            .background(isSelected ? Theme.elevated.opacity(0.6) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func title(for plan: StoreManager.Plan) -> String {
        switch plan {
        case .lifetime: L("Ömür Boyu", "Lifetime")
        case .yearly: L("Yıllık", "Yearly")
        case .monthly: L("Aylık", "Monthly")
        }
    }

    private func badge(for plan: StoreManager.Plan) -> String? {
        switch plan {
        case .lifetime:
            return L("Tek Seferlik", "One-time")
        case .yearly:
            let saving = store.yearlySavingsPercent
            return saving > 0 ? L("%\(saving) tasarruf", "Save \(saving)%") : nil
        case .monthly:
            return nil
        }
    }

    private func caption(for plan: StoreManager.Plan) -> String {
        switch plan {
        case .lifetime: L("Bir kez öde, hep senin", "Pay once, yours forever")
        case .yearly: L("Yıllık · her yıl yenilenir", "Yearly · renews every year")
        case .monthly: L("Aylık · her ay yenilenir", "Monthly · renews every month")
        }
    }

    private func periodSuffix(for plan: StoreManager.Plan) -> String {
        switch plan {
        case .lifetime: ""
        case .yearly: L("/yıl", "/yr")
        case .monthly: L("/ay", "/mo")
        }
    }

    /// Otomatik yenilenen abonelik açıklaması (App Store Review Kılavuzu 3.1.2)
    private var legalNote: some View {
        Text(selected.isSubscription
            ? L(
                "Abonelik, dönem bitiminden en az 24 saat önce iptal edilmezse otomatik olarak yenilenir ve ücret Apple hesabından alınır. App Store hesap ayarlarından dilediğin zaman yönetebilir ya da iptal edebilirsin.",
                "Your subscription renews automatically unless cancelled at least 24 hours before the end of the current period, and is charged to your Apple Account. Manage or cancel anytime in your App Store account settings."
            )
            : L(
                "Tek seferlik ödeme. Abonelik yok, yenileme yok.",
                "One-time payment. No subscription, no renewals."
            ))
            .font(.system(size: 11.5))
            .foregroundStyle(Theme.textMuted)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .contentTransition(.opacity)
            .animation(Theme.spring, value: selected)
    }

    // MARK: - Alt bölüm

    private var footer: some View {
        VStack(spacing: 10) {
            if let error = store.lastError {
                Text(error)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.coral)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }

            Button {
                Haptics.tap()
                Task {
                    let plan = selected
                    awaitingPurchase = true
                    let success = await store.purchase(plan)
                    awaitingPurchase = false
                    if success {
                        Haptics.success()
                        withAnimation(Theme.spring) { purchasedPlan = plan }
                    } else if store.lastError != nil {
                        Haptics.error()
                    }
                }
            } label: {
                ZStack {
                    if store.isPurchasing {
                        ProgressView().tint(Theme.background)
                    } else {
                        Text(L("Devam Et", "Continue"))
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
                .foregroundStyle(Theme.background)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Theme.textPrimary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(SpringPressStyle())
            .disabled(store.isPurchasing || store.isRestoring)

            // App Store Review 3.1.1 / 3.1.2: geri yükleme, gizlilik politikası ve EULA her zaman erişilebilir
            LegalFooterLinks()
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Theme.background)
        .animation(Theme.spring, value: store.lastError)
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 30, height: 30)
                .background(Theme.surface, in: Circle())
                .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 1))
                // Görünür 30pt, dokunma alanı 44pt
                .padding(7)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 9)
        .padding(.trailing, Theme.gutter - 7)
        .accessibilityLabel(L("Kapat", "Close"))
    }
}

/// Basılıyken hafifçe küçülen, yay fiziğiyle geri dönen buton stili
struct SpringPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(Theme.spring, value: configuration.isPressed)
    }
}

/// Paywall ve Ayarlar'da ortak, kompakt yasal satır:
/// Satın Alımları Geri Yükle · Gizlilik Politikası · Kullanım Koşulları (EULA)
struct LegalFooterLinks: View {
    @Environment(StoreManager.self) private var store

    var body: some View {
        HStack(spacing: 6) {
            Button {
                Task { await store.restorePurchases() }
            } label: {
                HStack(spacing: 4) {
                    if store.isRestoring {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(Theme.textSecondary)
                    }
                    Text(L("Satın Alımları Geri Yükle", "Restore Purchases"))
                }
            }
            .disabled(store.isRestoring || store.isPurchasing)

            Text("·")

            Link(L("Gizlilik Politikası", "Privacy Policy"), destination: LegalLinks.privacy)

            Text("·")

            Link(L("Kullanım Koşulları (EULA)", "Terms of Use (EULA)"), destination: LegalLinks.terms)
        }
        .font(.footnote)
        .foregroundStyle(Theme.textSecondary)
        .tint(Theme.textSecondary)
        .buttonStyle(.plain)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

// MARK: - Satın alma sonrası (Heuristic #1 — sistem durumu görünürlüğü)

/// Başarılı satın almadan sonra: net onay + isteğe bağlı "gider olarak ekle" + Bitti
struct ProWelcomeView: View {
    let plan: StoreManager.Plan
    var onDone: () -> Void

    @Environment(StoreManager.self) private var storeManager
    @State private var showOffer = false
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(Theme.emerald)
                // Sembol efektleri sistemin "Hareketi Azalt" ayarına kendiliğinden uyar
                .symbolEffect(.bounce, value: appeared)

            VStack(spacing: 6) {
                Text(L("\(AppLanguage.brandName) Pro aktif", "\(AppLanguage.brandName) Pro is active"))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text(plan.membershipTitle)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.emerald)
                Text(L("Tüm Pro özellikleri şimdi açık. Teşekkürler!", "All Pro features are unlocked. Thank you!"))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            if showOffer {
                ProSelfExpenseOffer(plan: plan)
                    .padding(.top, 6)
            }

            Spacer(minLength: 0)

            Button(action: onDone) {
                Text(L("Bitti", "Done"))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.background)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Theme.textPrimary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(SpringPressStyle())
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.vertical, 24)
        .onAppear {
            showOffer = storeManager.shouldOfferSelfExpense
            appeared = true
            AccessibilityNotification.Announcement(L("\(AppLanguage.brandName) Pro aktif", "\(AppLanguage.brandName) Pro is active")).post()
        }
        .accessibilityElement(children: .contain)
    }
}

/// "Cent Pro aboneliğini yaklaşan sabit ödemelerime ekle" (aylık) /
/// "Cent Pro ödemesini bugünkü harcamalarıma kaydet" (yıllık, ömür boyu) — tek dokunuş, isteğe bağlı
struct ProSelfExpenseOffer: View {
    let plan: StoreManager.Plan

    @Environment(StoreManager.self) private var storeManager
    @Environment(SharedExpenseStore.self) private var store
    @State private var added = false

    private var price: String { storeManager.selfExpensePrice(for: plan) }
    private var brand: String { AppLanguage.brandName }

    private var offerTitle: String {
        plan == .monthly
            ? L("\(brand) Pro aboneliğini (\(price)/ay) yaklaşan sabit ödemelerime de ekle",
                "Also add \(brand) Pro (\(price)/mo) to my upcoming fixed payments")
            : L("\(brand) Pro ödemesini (\(price)) bugünkü harcamalarıma kaydet",
                "Log the \(brand) Pro payment (\(price)) in today’s expenses")
    }

    var body: some View {
        VStack(spacing: 8) {
            if added {
                Label(plan == .monthly ? L("Sabit ödemelere eklendi", "Added to fixed payments") : L("Bugüne kaydedildi", "Logged for today"),
                      systemImage: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.emerald)
                    .frame(maxWidth: .infinity, minHeight: 44)
            } else {
                Button {
                    withAnimation(Theme.spring) {
                        storeManager.logSelfExpense(in: store)
                        added = true
                    }
                    Haptics.success()
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: plan == .monthly ? "calendar.badge.plus" : "plus.circle.fill")
                            .font(.system(size: 15, weight: .semibold))
                        Text(offerTitle)
                            .font(.system(size: 14, weight: .semibold))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(Theme.emerald)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.emerald.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.emerald.opacity(0.25), lineWidth: 1))
                }
                .buttonStyle(SpringPressStyle())

                Button(L("Şimdi değil", "Not now")) {
                    withAnimation(Theme.spring) { storeManager.dismissSelfExpenseOffer() }
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .frame(minHeight: 44)
            }
        }
    }
}
