//
//  Theme.swift
//  Kuruş / Cent — Zanaatkar Fintech tasarım sistemi
//
//  Hedefler: App + Widget Extension
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Hex renk

extension Color {
    /// `Color(hex: "0C0C0E")` — saf `.black` / `.white` yerine her zaman palet kullanılır.
    init(hex: String, opacity: Double = 1) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}

// MARK: - Tasarım anayasası

enum Theme {
    // Yüzeyler
    static let background = Color(hex: "0C0C0E")   // Derin Antrasit
    static let surface    = Color(hex: "16161A")   // Kart yüzeyi
    static let elevated   = Color(hex: "1F1F24")   // Yükseltilmiş yüzey
    static let hairline   = Color.white.opacity(0.08) // 1pt kenarlık — gölge yok

    // Metin
    static let textPrimary   = Color(hex: "F4F4F6")
    static let textSecondary = Color(hex: "8E8E93")
    static let textMuted     = Color(hex: "48484A")

    // Vurgular
    static let emerald = Color(hex: "30D158")  // Zümrüt
    static let coral   = Color(hex: "FF453A")  // Mercan
    static let amber   = Color(hex: "FF9F0A")  // Kehribar
    static let ocean   = Color(hex: "0A84FF")  // Okyanus
    static let violet  = Color(hex: "BF5AF2")  // Birikim Moru
    static let indigo  = Color(hex: "5E5CE6")  // Teknoloji
    static let brass   = Color(hex: "D4A72C")  // Vergi & Resmi (Kehribar'dan ayrışan pirinç tonu)

    // Açık zeminli rozetlerde koyu glif ve PDF kâğıdı
    static let ink   = Color(hex: "141417")
    static let paper = Color(hex: "FAFAF7")

    // Ölçüler
    static let gutter: CGFloat = 20
    static let cardRadius: CGFloat = 20
    static let rowRadius: CGFloat = 16

    // Hareket — "Hareketi Azalt" açıksa yay fiziği yerine kısa, sakin bir geçiş (WCAG 2.3.3 / HIG)
    static var spring: Animation {
        reduceMotion ? .easeInOut(duration: 0.18) : .spring(response: 0.35, dampingFraction: 0.75)
    }

    /// Sistem "Hareketi Azalt" tercihi (görünüm dışı kodda da okunabilsin diye UIKit'ten)
    static var reduceMotion: Bool {
        #if os(iOS)
        UIAccessibility.isReduceMotionEnabled
        #else
        false
        #endif
    }
}

// MARK: - Zanaat kartı (gölgesiz, 1pt hairline)

struct CraftCard: ViewModifier {
    var radius: CGFloat = Theme.cardRadius
    var fill: Color = Theme.surface

    func body(content: Content) -> some View {
        content
            .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
    }
}

extension View {
    func craftCard(radius: CGFloat = Theme.cardRadius, fill: Color = Theme.surface) -> some View {
        modifier(CraftCard(radius: radius, fill: fill))
    }
}

// MARK: - Gizlilik modu

private struct PrivacyModeKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// `true` olduğunda tüm parasal değerler `.blur(radius: 8)` ile gizlenir.
    var privacyMode: Bool {
        get { self[PrivacyModeKey.self] }
        set { self[PrivacyModeKey.self] = newValue }
    }
}

struct PrivacyBlur: ViewModifier {
    @Environment(\.privacyMode) private var hidden

    func body(content: Content) -> some View {
        content
            .blur(radius: hidden ? 8 : 0)
            .animation(Theme.spring, value: hidden)
    }
}

extension View {
    func privacyBlur() -> some View { modifier(PrivacyBlur()) }
}

// MARK: - Tutar tipografisi

/// Yerel tutar: ana kısım tam boy, kuruş/cent haneleri küçük ve %50 opak.
/// tr: `₺12.000,50` · en_US: `$12,000.50` · de_DE: `12.000,50 €` (sembol sonda).
/// Tüm rakamlar `.monospacedDigit()`; değişimler `.numericText()` ile akar.
struct AmountText: View {
    let amount: Decimal
    var size: CGFloat = 17
    var weight: Font.Weight = .semibold
    var color: Color = Theme.textPrimary
    var showsFraction: Bool = true
    var prefix: String = ""
    /// ISO para birimi; `nil` → cihazın ana para birimi.
    var currency: String? = nil

    var body: some View {
        let parts = CurrencyFormat.parts(showsFraction ? amount : amount.rounded(0), currency: currency)
        let style = parts.style
        let leading = style.symbolFirst ? style.symbol + style.spacing : ""
        let trailing = style.symbolFirst ? "" : style.spacing + style.symbol
        let mainFont = Font.system(size: size, weight: weight)

        let main = Text(verbatim: "\(prefix)\(parts.sign)\(leading)\(parts.integer)")
            .font(mainFont)
            .monospacedDigit()
        let fraction = Text(verbatim: "\(style.decimal)\(parts.fraction)")
            .font(.system(size: size * 0.56, weight: weight))
            .monospacedDigit()
            .foregroundStyle(color.opacity(0.5))
        let suffix = Text(verbatim: trailing)
            .font(mainFont)

        Group {
            if showsFraction {
                Text("\(main)\(fraction)\(suffix)")
            } else {
                Text("\(main)\(suffix)")
            }
        }
        .foregroundStyle(color)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .contentTransition(.numericText(value: amount.doubleValue))
        .accessibilityLabel(Text(verbatim: CurrencyFormat.string(amount, fraction: showsFraction, currency: currency)))
    }
}

// MARK: - İnce kapsül ölçer

struct CapsuleMeter: View {
    let progress: Double
    var tint: Color = Theme.emerald
    var track: Color = Theme.elevated
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            let clamped = min(max(progress, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule()
                    .fill(tint)
                    .frame(width: clamped > 0 ? max(height, geo.size.width * clamped) : 0)
            }
        }
        .frame(height: height)
    }
}

// MARK: - Geçersiz girişte sarsıntı

struct ShakeEffect: GeometryEffect {
    var travel: CGFloat = 7
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(
            CGAffineTransform(translationX: travel * sin(animatableData * .pi * 4), y: 0)
        )
    }
}

// MARK: - Dokunsal geri bildirim

@MainActor
enum Haptics {
    static func success() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    static func warning() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif
    }

    static func error() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        #endif
    }

    static func tap() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    static func selection() {
        #if os(iOS)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }
}
