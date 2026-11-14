//
//  SmartInputBarView.swift
//  Kuruş — Klavyenin üstünde yaşayan akıllı komut çubuğu ve canlı cam hap
//
//  Hedef: App
//

import SwiftUI

struct SmartInputBarView: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    var isDemoTyping: Bool = false
    var onSubmit: (ParsedExpense) -> Void

    @State private var shakes: CGFloat = 0

    var body: some View {
        let parsed = ExpenseParser.parse(text)
        let isValid = parsed?.isValid ?? false

        VStack(spacing: 10) {
            if let parsed {
                LiveParsePill(parsed: parsed)
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

                    TextField(text: $text, prompt: Text("Netflix 229, Kahve 145…").foregroundStyle(Theme.textMuted)) {
                        Text("Harcama")
                    }
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .tint(Theme.emerald)
                    .focused(isFocused)
                    .submitLabel(.return)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.sentences)
                    .onSubmit(submit)

                    if !text.isEmpty && !isDemoTyping {
                        Button {
                            withAnimation(Theme.spring) { text = "" }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(Theme.textMuted)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Temizle")
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
                .disabled(!isValid)
                .accessibilityLabel("Kaydet")
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
        .animation(Theme.spring, value: isValid)
    }

    private func submit() {
        guard let parsed = ExpenseParser.parse(text), parsed.isValid else {
            guard !text.isEmpty else { return }
            Haptics.error()
            withAnimation(.linear(duration: 0.4)) { shakes += 1 }
            return
        }
        onSubmit(parsed)
    }
}

// MARK: - Canlı cam hap: marka/kategori, taksit, kart ve tutar

struct LiveParsePill: View {
    let parsed: ParsedExpense

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
                ParseTag(symbol: "square.stack.3d.up.fill", text: "\(parsed.installmentCount) taksit", tint: Theme.amber)
            }
            if let card = compact ? parsed.compactCardLabel : parsed.cardLabel {
                ParseTag(symbol: parsed.isCash ? "banknote.fill" : "creditcard.fill", text: card, tint: Theme.ocean)
            }
            if parsed.isRecurring {
                ParseTag(symbol: "repeat", text: compact ? nil : "Abonelik", tint: Theme.violet)
            }
        }
    }

    @ViewBuilder
    private var amountColumn: some View {
        VStack(alignment: .trailing, spacing: 2) {
            if let amount = parsed.amount, amount > 0 {
                if parsed.installmentCount > 1, let per = parsed.perInstallment {
                    AmountText(amount: per, size: 17, weight: .bold)
                    Text("1/\(parsed.installmentCount) · toplam \(CurrencyFormat.string(amount, fraction: false))")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                } else {
                    AmountText(amount: amount, size: 17, weight: .bold)
                }
            } else {
                Text("tutar?")
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
