//
//  SmartInputBarView.swift
//  Kuruş / Cent — Klavyenin üstünde yaşayan akıllı komut çubuğu ve canlı cam hap
//
//  Hedef: App
//

import SwiftUI

struct SmartInputBarView: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    var isDemoTyping: Bool = false
    /// Ücretsiz planda bu giriş bir Pro özelliğine takılıyorsa (taksit, ikinci kart) — hapta kilit gösterilir
    var lockedFeature: (ParsedExpense) -> ProFeature? = { _ in nil }
    /// Her başarılı kayıtta artar; TextField yeniden oluşturulur ve ekrandaki metin kesin olarak temizlenir.
    var resetToken: Int = 0
    /// Kullanıcının kart adları (Ayarlar → Kart Ekle): "Kahve 85 nkolay" → Nkolay kartı
    var cardNames: [String] = []
    var onSubmit: (ParsedExpense) -> Void

    @State private var shakes: CGFloat = 0
    /// "Tutar eklemeyi unuttunuz" mikro uyarısı (2,5 sn) — Heuristic #9
    @State private var amountHint: String?
    @State private var hintTask: Task<Void, Never>?
    /// Kutu boşken dönen örnek komut — Heuristic #10
    @State private var placeholderIndex = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let parsed = ExpenseParser.parse(text, userCards: cardNames)
        let isValid = parsed?.isValid ?? false

        VStack(spacing: 10) {
            if let amountHint {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(Theme.amber)
                        .accessibilityHidden(true)
                    Text(amountHint)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                .font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.amber.opacity(0.35), lineWidth: 1))
                .padding(.horizontal, Theme.gutter)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else if let parsed {
                LiveParsePill(parsed: parsed, locked: lockedFeature(parsed))
                    .padding(.horizontal, Theme.gutter)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .scale(scale: 0.92).combined(with: .opacity)
                        )
                    )
            }

            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: isDemoTyping ? "wand.and.stars" : "sparkles")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isDemoTyping ? Theme.amber : Theme.textMuted)
                        .contentTransition(.symbolEffect(.replace))

                    TextField(text: $text, prompt: Text(currentHint).foregroundStyle(Theme.textMuted)) {
                        Text(L("Harcama", "Expense"))
                    }
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .tint(Theme.emerald)
                    .focused(isFocused)
                    // Klavyedeki "Gönder" tuşu, yukarı ok butonuyla aynı işi yapar (Heuristic #7)
                    .submitLabel(.send)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.sentences)
                    .onSubmit(submit)
                    // Return'de klavye oturumu kapanırken UITextField, bağlam ("") boşalsa bile eski metni
                    // gösterebiliyor. Kimlik değişince alan sıfırdan çizilir; odak ContentView'da geri verilir.
                    .id(resetToken)

                    if !text.isEmpty && !isDemoTyping {
                        Button {
                            withAnimation(Theme.spring) { text = "" }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(Theme.textMuted)
                                .frame(width: 32, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L("Temizle", "Clear"))
                        .transition(.opacity)
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 46)
                .background(Theme.surface.opacity(0.85), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(isFocused.wrappedValue ? Theme.emerald.opacity(0.35) : Theme.hairline, lineWidth: 1)
                )

                Button(action: submit) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(isValid ? Theme.background : Theme.textMuted)
                        .frame(width: 46, height: 46)
                        .background(isValid ? Theme.emerald : Theme.elevated, in: Circle())
                        .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 1))
                        .scaleEffect(isValid ? 1 : 0.92)
                }
                .buttonStyle(.plain)
                // Tutarsız metinde de basılabilir: sessizce başarısız olmak yerine yapıcı uyarı gösterilir
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel(L("Kaydet", "Save"))
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .modifier(ShakeEffect(animatableData: shakes))
            .background(alignment: .top) {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(alignment: .top) {
                        Rectangle().fill(Theme.hairline).frame(height: 1)
                    }
                    .ignoresSafeArea(edges: .bottom)
            }
        }
        .animation(Theme.spring, value: parsed != nil)
        .onChange(of: text) { _, newText in
            // Kullanıcı tutarı ekleyince uyarı hemen kalkar
            if amountHint != nil, ExpenseParser.parse(newText, userCards: cardNames)?.isValid == true {
                hintTask?.cancel()
                withAnimation(Theme.spring) { amountHint = nil }
            }
        }
        .task {
            // Kutu boşken örnek komutlar birkaç saniyede bir döner
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                if text.isEmpty && !isDemoTyping { placeholderIndex &+= 1 }
            }
        }
        .animation(Theme.spring, value: isValid)
    }

    private var currentHint: String {
        let hints = QuickSamples.hints
        return hints[placeholderIndex % hints.count]
    }

    private func submit() {
        guard let parsed = ExpenseParser.parse(text, userCards: cardNames), parsed.isValid else {
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            // Metin korunur; kullanıcı yalnızca sayıyı ekleyebilir
            Haptics.warning()
            if !reduceMotion {
                withAnimation(.linear(duration: 0.4)) { shakes += 1 }
            }
            showAmountHint()
            return
        }
        hintTask?.cancel()
        amountHint = nil
        onSubmit(parsed)
    }

    private func showAmountHint() {
        let message = L("Tutar eklemeyi unuttunuz (Örn: Kahve 85)", "Please include an amount (e.g., Coffee 5)")
        hintTask?.cancel()
        withAnimation(Theme.spring) { amountHint = message }
        AccessibilityNotification.Announcement(message).post()
        hintTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(2500))
            guard !Task.isCancelled else { return }
            withAnimation(Theme.spring) { amountHint = nil }
        }
    }
}

// MARK: - Canlı cam hap: marka/kategori, taksit, kart ve tutar

struct LiveParsePill: View {
    let parsed: ParsedExpense
    /// Pro kilidi: ilgili etiket kilit simgesiyle gösterilir, Return'de Pro sayfası açılır
    var locked: ProFeature? = nil

    var body: some View {
        HStack(spacing: 10) {
            ExpenseBadge(brand: parsed.brand, category: parsed.category, size: 32)
                .id(parsed.brandID ?? parsed.category.rawValue)
                .transition(.scale(scale: 0.6).combined(with: .opacity))

            VStack(alignment: .leading, spacing: 4) {
                Text(parsed.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                ViewThatFits(in: .horizontal) {
                    tagRow(compact: false)
                    tagRow(compact: true)
                }
            }

            Spacer(minLength: 6)

            amountColumn
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
        .animation(Theme.spring, value: parsed)
    }

    private func tagRow(compact: Bool) -> some View {
        HStack(spacing: 5) {
            ParseTag(symbol: parsed.category.symbol, text: compact ? nil : parsed.category.title, tint: parsed.category.color)
            if parsed.installmentCount > 1 {
                ParseTag(
                    symbol: locked == .installments ? "lock.fill" : "square.stack.3d.up.fill",
                    text: L("\(parsed.installmentCount) taksit", "\(parsed.installmentCount)x") + (locked == .installments ? " · Pro" : ""),
                    tint: Theme.amber
                )
            }
            if parsed.dayOffset == -1 {
                ParseTag(symbol: "calendar", text: compact ? nil : L("Dün", "Yesterday"), tint: Theme.textSecondary)
            }
            if let card = compact ? parsed.compactCardLabel : parsed.cardLabel {
                ParseTag(
                    symbol: locked == .multipleCards ? "lock.fill" : (parsed.isCash ? "banknote.fill" : "creditcard.fill"),
                    text: card + (locked == .multipleCards ? " · Pro" : ""),
                    tint: Theme.ocean
                )
            }
            // Abonelik kategorisi zaten "repeat" simgesiyle görünür; ikinci döngü simgesi gösterilmez.
            if parsed.isRecurring && parsed.category != .subscription {
                ParseTag(symbol: "repeat", text: compact ? nil : (parsed.isIncome ? L("Aylık", "Monthly") : L("Abonelik", "Subscription")), tint: Theme.violet)
            }
        }
    }

    @ViewBuilder
    private var amountColumn: some View {
        VStack(alignment: .trailing, spacing: 2) {
            if let amount = parsed.amount, amount > 0 {
                if parsed.installmentCount > 1, let per = parsed.perInstallment {
                    AmountText(amount: per, size: 17, weight: .bold, currency: parsed.currencyCode)
                    Text(L(
                        "1/\(parsed.installmentCount) · toplam \(CurrencyFormat.string(amount, fraction: false, currency: parsed.currencyCode))",
                        "1/\(parsed.installmentCount) · total \(CurrencyFormat.string(amount, fraction: false, currency: parsed.currencyCode))"
                    ))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                } else {
                    AmountText(
                        amount: amount,
                        size: 17,
                        weight: .bold,
                        color: parsed.isIncome ? Theme.emerald : Theme.textPrimary,
                        prefix: parsed.isIncome ? "+" : "",
                        currency: parsed.currencyCode
                    )
                }
            } else {
                Text(L("tutar?", "amount?"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.amber)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct ParseTag: View {
    let symbol: String
    let text: String?
    let tint: Color

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
            if let text {
                Text(text)
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
            }
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(tint.opacity(0.14), in: Capsule())
        .lineLimit(1)
        .fixedSize()
    }
}
