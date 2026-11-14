//
//  AutomationGuideSheet.swift
//  Kuruş — 30 saniyelik Banka SMS Otomasyonu rehberi
//
//  Hedef: App
//

import SwiftUI

struct AutomationGuideSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private let sampleSMS = "4532 ile biten Bonus kartınızla MIGROS işyerinde 642,50 TL harcama yapılmıştır."

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    hero

                    VStack(spacing: 12) {
                        GuideStep(
                            number: 1,
                            symbol: "message.fill",
                            tint: Theme.emerald,
                            title: "Otomasyonu başlat",
                            detail: "**Kestirmeler › Otomasyon › ＋** yolunu izleyip **Mesaj**’ı seç. *Gönderen* olarak bankanı (ör. Garanti BBVA), *Mesaj şunu içeriyor* alanına **harcama** yaz ve **Hemen Çalıştır**’ı işaretle."
                        )
                        GuideStep(
                            number: 2,
                            symbol: "square.stack.3d.up.fill",
                            tint: Theme.ocean,
                            title: "Kuruş’a bağla",
                            detail: "**Yeni Boş Otomasyon › Eylem Ekle** ile **Kuruş › Harcama Ekle**’yi seç. *Harcama Metni* alanına dokunup **Kestirme Girdisi › İçerik** değişkenini yerleştir."
                        )
                        GuideStep(
                            number: 3,
                            symbol: "checkmark.seal.fill",
                            tint: Theme.violet,
                            title: "Bitti — gerisi otomatik",
                            detail: "Bir sonraki SMS’te tutar, iş yeri ve kartın (**••4532**) kendiliğinden kaydedilir. Aynı kartla yapılan harcamalar o kartın havuzunda toplanır."
                        )
                    }

                    preview

                    privacyNote

                    Button {
                        if let url = URL(string: "shortcuts://") { openURL(url) }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.up.forward.app.fill")
                            Text("Kestirmeler’i Aç")
                        }
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.background)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Theme.textPrimary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.vertical, 12)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
            .background(Theme.background)
            .navigationTitle("SMS Otomasyonu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Bitti") { dismiss() }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.emerald)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.background)
        .presentationCornerRadius(28)
    }

    // MARK: - Bölümler

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                heroIcon("message.fill", tint: Theme.emerald)
                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.textMuted)
                heroIcon("bolt.fill", tint: Theme.amber)
                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.textMuted)
                Text("₺")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.background)
                    .frame(width: 44, height: 44)
                    .background(Theme.textPrimary, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }

            Text("30 saniyede\notomatik takip")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.75)

            Text("Banka SMS’i geldiği anda iPhone’un yerleşik Kestirmeler uygulaması metni Kuruş’a iletir. Kurulum bir kez yapılır.")
                .font(.system(size: 15))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
    }

    private func heroIcon(_ symbol: String, tint: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 44, height: 44)
            .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("KURUŞ BU SMS’İ ŞÖYLE OKUR")
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Theme.textSecondary)

            Text(sampleSMS)
                .font(.system(size: 14))
                .foregroundStyle(Theme.textPrimary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            if let parsed = ExpenseParser.parse(sampleSMS) {
                VStack(spacing: 0) {
                    resultRow("Tutar") {
                        AmountText(amount: parsed.amount ?? 0, size: 15, weight: .semibold)
                    }
                    divider
                    resultRow("İş yeri") {
                        HStack(spacing: 8) {
                            ExpenseBadge(brand: parsed.brand, category: parsed.category, size: 22)
                            Text(parsed.title).font(.system(size: 15, weight: .semibold))
                        }
                    }
                    divider
                    resultRow("Kart") {
                        Text(parsed.cardLabel ?? "—")
                            .font(.system(size: 15, weight: .semibold))
                            .monospacedDigit()
                    }
                    divider
                    resultRow("Kategori") {
                        Text(parsed.category.title).font(.system(size: 15, weight: .semibold))
                    }
                }
                .foregroundStyle(Theme.textPrimary)
            }
        }
        .padding(16)
        .craftCard()
    }

    private var divider: some View {
        Rectangle().fill(Theme.hairline).frame(height: 1)
    }

    private func resultRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 12)
            content()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.vertical, 10)
    }

    private var privacyNote: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.emerald)
            Text("SMS’lerin cihazından hiç çıkmaz. Kestirme yalnızca metni Kuruş’a verir; sunucu, hesap ya da üçüncü taraf yok.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.emerald.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.emerald.opacity(0.18), lineWidth: 1))
    }
}

// MARK: - Adım kartı

private struct GuideStep: View {
    let number: Int
    let symbol: String
    let tint: Color
    let title: String
    let detail: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.16), in: Circle())

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(tint)
                }
                Text(detail)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
                    .tint(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .craftCard(radius: 18)
    }
}
