//
//  AutomationGuideSheet.swift
//  Kuruş / Cent — 30 saniyelik otomasyon rehberi
//  Türkçe: Banka SMS Otomasyonu · English: Auto-Capture (Apple Pay + Bank SMS)
//
//  Hedef: App
//

import SwiftUI

struct AutomationGuideSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private var brand: String { AppLanguage.brandName }

    /// Dile göre örnek bildirim — rehberdeki önizleme bunu gerçek ayrıştırıcıyla okur.
    private var sampleNotice: String {
        L(
            "4532 ile biten Bonus kartınızla MIGROS işyerinde 642,50 TL harcama yapılmıştır.",
            "Card ending in 4532 at Whole Foods for $84.50"
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    hero

                    if AppLanguage.isTurkish {
                        bankSMSSteps
                    } else {
                        sectionLabel("APPLE PAY", symbol: "wave.3.right.circle.fill", tint: Theme.emerald)
                        applePaySteps
                        sectionLabel("BANK SMS", symbol: "message.fill", tint: Theme.ocean)
                        bankSMSSteps
                    }

                    preview

                    privacyNote

                    Button {
                        if let url = URL(string: "shortcuts://") { openURL(url) }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.up.forward.app.fill")
                            Text(L("Kestirmeler’i Aç", "Open Shortcuts"))
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
            .navigationTitle(L("SMS Otomasyonu", "Auto-Capture"))
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
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.background)
        .presentationCornerRadius(28)
    }

    // MARK: - Adımlar

    /// English: Shortcuts › Automation › Transaction (Wallet / Apple Pay)
    private var applePaySteps: some View {
        VStack(spacing: 12) {
            GuideStep(
                number: 1,
                symbol: "wave.3.right",
                tint: Theme.emerald,
                title: "Create the automation",
                detail: "Open **Shortcuts › Automation › ＋** and choose **Transaction**. Pick your Apple Pay cards, keep all categories, and select **Run Immediately**."
            )
            GuideStep(
                number: 2,
                symbol: "square.stack.3d.up.fill",
                tint: Theme.ocean,
                title: "Connect \(brand)",
                detail: "Tap **New Blank Automation › Add Action** and choose **\(brand) › Add Expense**. In *Expense Text*, insert **Shortcut Input › Merchant**, a space, then **Shortcut Input › Amount**."
            )
            GuideStep(
                number: 3,
                symbol: "checkmark.seal.fill",
                tint: Theme.violet,
                title: "Done — tap to pay, it’s logged",
                detail: "Every Apple Pay purchase now lands in \(brand) with the merchant, amount and category — no typing."
            )
        }
    }

    /// Kestirmeler › Otomasyon › Mesaj (banka SMS'i)
    private var bankSMSSteps: some View {
        VStack(spacing: 12) {
            GuideStep(
                number: 1,
                symbol: "message.fill",
                tint: Theme.emerald,
                title: L("Otomasyonu başlat", "Create the automation"),
                detail: L(
                    "**Kestirmeler › Otomasyon › ＋** yolunu izleyip **Mesaj**’ı seç. *Gönderen* olarak bankanı (ör. Garanti BBVA), *Mesaj şunu içeriyor* alanına **harcama** yaz ve **Hemen Çalıştır**’ı işaretle.",
                    "Open **Shortcuts › Automation › ＋** and choose **Message**. Set *Sender* to your bank, *Message Contains* to **spent** (or **purchase**), and select **Run Immediately**."
                )
            )
            GuideStep(
                number: 2,
                symbol: "square.stack.3d.up.fill",
                tint: Theme.ocean,
                title: L("\(brand)’a bağla", "Connect \(brand)"),
                detail: L(
                    "**Yeni Boş Otomasyon › Eylem Ekle** ile **\(brand) › Harcama Ekle**’yi seç. *Harcama Metni* alanına dokunup **Kestirme Girdisi › İçerik** değişkenini yerleştir.",
                    "Tap **New Blank Automation › Add Action** and choose **\(brand) › Add Expense**. In *Expense Text*, insert **Shortcut Input › Content**."
                )
            )
            GuideStep(
                number: 3,
                symbol: "checkmark.seal.fill",
                tint: Theme.violet,
                title: L("Bitti — gerisi otomatik", "Done — the rest is automatic"),
                detail: L(
                    "Bir sonraki SMS’te tutar, iş yeri ve kartın (**••4532**) kendiliğinden kaydedilir. Aynı kartla yapılan harcamalar o kartın havuzunda toplanır.",
                    "The amount, merchant and card (**••4532**) are captured from the next SMS. Purchases on the same card are grouped under that card."
                )
            )
        }
    }

    private func sectionLabel(_ title: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
            Text(title)
                .tracking(0.8)
                .foregroundStyle(Theme.textSecondary)
        }
        .font(.system(size: 12, weight: .semibold))
        .padding(.bottom, -16)
    }

    // MARK: - Bölümler

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                heroIcon(AppLanguage.isTurkish ? "message.fill" : "wave.3.right", tint: Theme.emerald)
                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.textMuted)
                heroIcon("bolt.fill", tint: Theme.amber)
                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.textMuted)
                Text(CurrencyFormat.style().symbol)
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(Theme.background)
                    .frame(width: 44, height: 44)
                    .background(Theme.textPrimary, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }

            Text(L("30 saniyede\notomatik takip", "Set up once,\ncapture forever"))
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.75)

            Text(L(
                "Banka SMS’i geldiği anda iPhone’un yerleşik Kestirmeler uygulaması metni \(brand)’a iletir. Kurulum bir kez yapılır.",
                "The built-in Shortcuts app hands every Apple Pay purchase or bank SMS to \(brand) the moment it happens. Takes 30 seconds."
            ))
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
            Text(L(
                "\(brand) BU SMS’İ ŞÖYLE OKUR".uppercased(with: KurusDate.locale),
                "HOW \(brand.uppercased()) READS THIS"
            ))
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Theme.textSecondary)

            Text(sampleNotice)
                .font(.system(size: 14))
                .foregroundStyle(Theme.textPrimary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            if let parsed = ExpenseParser.parse(sampleNotice) {
                VStack(spacing: 0) {
                    resultRow(L("Tutar", "Amount")) {
                        AmountText(amount: parsed.amount ?? 0, size: 15, weight: .semibold, currency: parsed.currencyCode)
                    }
                    divider
                    resultRow(L("İş yeri", "Merchant")) {
                        HStack(spacing: 8) {
                            ExpenseBadge(brand: parsed.brand, category: parsed.category, size: 22)
                            Text(parsed.title).font(.system(size: 15, weight: .semibold))
                        }
                    }
                    divider
                    resultRow(L("Kart", "Card")) {
                        // Banka adı biliniyorsa "Bonus ••4532", yoksa yalnızca "••4532"
                        Text((parsed.bankName == nil ? parsed.compactCardLabel : parsed.cardLabel) ?? "—")
                            .font(.system(size: 15, weight: .semibold))
                            .monospacedDigit()
                    }
                    divider
                    resultRow(L("Kategori", "Category")) {
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
            Text(L(
                "SMS’lerin cihazından hiç çıkmaz. Kestirme yalnızca metni \(brand)’a verir; sunucu, hesap ya da üçüncü taraf yok.",
                "Nothing leaves your iPhone. Shortcuts only hands the text to \(brand) — no server, no account, no third party."
            ))
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
    /// Markdown destekli (kalın / italik) çalışma zamanı metni
    let detail: String

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
                Text(markdown)
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

    private var markdown: AttributedString {
        (try? AttributedString(
            markdown: detail,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(detail)
    }
}
