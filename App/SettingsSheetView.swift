//
//  SettingsSheetView.swift
//  Kuruş / Cent — Ayarlar & Abonelik (satın alma sonrası yönetim)
//
//  Hedef: App
//
//  • Üyelik Durumu: aktif plan, yenilenme / sona erme tarihi, Aboneliği Yönet (yerel
//    .manageSubscriptionsSheet), Pro'ya Geç, Satın Alımları Geri Yükle (App Review 3.1.1)
//  • Veri Yönetimi: hesap olmadığı için "Tüm Verileri Sıfırla" (cihaz + iCloud), onaylı
//  • Yasal: Gizlilik Politikası, Apple Standart EULA ve sürüm / build numarası
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

    private var brand: String { AppLanguage.brandName }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    membershipSection
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

    // MARK: - Veri Yönetimi

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(L("VERİ YÖNETİMİ", "DATA"))

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

    // MARK: - Yasal & Sürüm

    private var legalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(L("YASAL", "LEGAL"))

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
