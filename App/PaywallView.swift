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
    @Environment(\.openURL) private var openURL

    @State private var selected: StoreManager.Plan = .lifetime

    private var brand: String { AppLanguage.brandName }

    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                header
                powers
                planPicker
                legalNote
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 28)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        .overlay(alignment: .topTrailing) { closeButton }
        .background(Theme.background)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.background)
        .presentationCornerRadius(28)
        .preferredColorScheme(.dark)
        .onChange(of: store.isPro) { _, isPro in
            if isPro { dismiss() }
        }
        .task {
            if store.products.isEmpty { await store.loadProducts() }
        }
    }

    // MARK: - Üst bölüm

    private var header: some View {
        VStack(spacing: 12) {
            KurusMarkShape(size: 36)
                .padding(10)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))

            Text("\(brand) Pro")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .tracking(-0.6)
                .foregroundStyle(Theme.textPrimary)

            Text(L(
                "Otomatik SMS yakalama, taksit takibi ve interaktif widget’larla tam kontrol.",
                "Full control with automatic SMS capture, installment tracking and interactive widgets."
            ))
            .font(.system(size: 15))
            .foregroundStyle(Theme.textSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
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
                    Rectangle().fill(Theme.hairline).frame(height: 1).padding(.leading, 52)
                }
                let highlighted = feature.highlightIndex == index
                HStack(spacing: 14) {
                    Image(systemName: row.symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(row.tint)
                        .frame(width: 32, height: 32)
                        .background(row.tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Text(row.text)
                        .font(.system(size: 14.5, weight: highlighted ? .semibold : .medium))
                        .foregroundStyle(highlighted ? Theme.textPrimary : Theme.textPrimary.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if highlighted {
                        Image(systemName: "lock.open.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.emerald)
                    }
                }
                .padding(.vertical, 11)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .craftCard(radius: 18)
    }

    // MARK: - Plan seçici (iCloud+ tarzı ince satırlar)

    private var planPicker: some View {
        VStack(spacing: 0) {
            ForEach(Array(StoreManager.Plan.allCases.enumerated()), id: \.element.id) { index, plan in
                if index > 0 {
                    Rectangle().fill(Theme.hairline).frame(height: 1).padding(.leading, 48)
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
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(isSelected ? Theme.emerald : Theme.textMuted)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 3) {
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
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
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
        VStack(spacing: 12) {
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
                    let success = await store.purchase(selected)
                    if success { Haptics.success() } else if store.lastError != nil { Haptics.error() }
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
                .frame(height: 54)
                .background(Theme.textPrimary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(SpringPressStyle())
            .disabled(store.isPurchasing || store.isRestoring)

            HStack(spacing: 6) {
                Button {
                    Task { await store.restorePurchases() }
                } label: {
                    Text(store.isRestoring ? L("Geri yükleniyor…", "Restoring…") : L("Satın Alımları Geri Yükle", "Restore Purchases"))
                }
                .disabled(store.isRestoring || store.isPurchasing)
                Text("·")
                Button(L("Kullanım Koşulları", "Terms of Use")) { openURL(LegalLinks.terms) }
                Text("·")
                Button(L("Gizlilik Politikası", "Privacy Policy")) { openURL(LegalLinks.privacy) }
            }
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(Theme.textSecondary)
            .buttonStyle(.plain)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 12)
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
        }
        .buttonStyle(.plain)
        .padding(.top, 16)
        .padding(.trailing, Theme.gutter)
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
