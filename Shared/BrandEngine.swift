//
//  BrandEngine.swift
//  Kuruş — Marka tanıma ve marka rozetleri
//
//  Hedefler: App + Widget Extension
//
//  Not: Tescilli logolar uygulamaya gömülmez (marka hakları). Her marka; kendi kurumsal
//  rengi üzerinde monogram ya da SF Symbol gliften oluşan özel bir rozetle temsil edilir.
//

import SwiftUI

// MARK: - Marka

struct Brand: Identifiable, Hashable, Sendable {
    enum Glyph: Hashable, Sendable {
        case monogram(String)
        case symbol(String)
    }

    let id: String
    let name: String
    /// `kurusNormalized` biçiminde (küçük harf, aksansız) anahtar kelimeler.
    let keywords: [String]
    let hex: String
    let glyph: Glyph
    let category: ExpenseCategory
    let isSubscription: Bool
    var darkGlyph: Bool = false

    var color: Color { Color(hex: hex) }
    var glyphColor: Color { darkGlyph ? Theme.ink : Theme.textPrimary }
}

// MARK: - Motor

enum BrandEngine {
    static let all: [Brand] = [
        // Dijital abonelikler
        Brand(id: "netflix", name: "Netflix", keywords: ["netflix"], hex: "E50914",
              glyph: .monogram("N"), category: .subscription, isSubscription: true),
        Brand(id: "spotify", name: "Spotify", keywords: ["spotify"], hex: "1DB954",
              glyph: .symbol("waveform"), category: .subscription, isSubscription: true, darkGlyph: true),
        Brand(id: "youtube", name: "YouTube Premium", keywords: ["youtube", "yt premium"], hex: "FF0033",
              glyph: .symbol("play.fill"), category: .subscription, isSubscription: true),
        Brand(id: "icloud", name: "iCloud+", keywords: ["icloud"], hex: "3D8BFF",
              glyph: .symbol("icloud.fill"), category: .subscription, isSubscription: true),
        Brand(id: "disney", name: "Disney+", keywords: ["disney"], hex: "113CCF",
              glyph: .monogram("D+"), category: .subscription, isSubscription: true),
        Brand(id: "prime", name: "Prime Video", keywords: ["prime video", "amazon prime"], hex: "00A8E1",
              glyph: .monogram("P"), category: .subscription, isSubscription: true),
        Brand(id: "chatgpt", name: "ChatGPT Plus", keywords: ["chatgpt", "openai"], hex: "10A37F",
              glyph: .symbol("sparkle"), category: .subscription, isSubscription: true),

        // Operatörler
        Brand(id: "turkcell", name: "Turkcell", keywords: ["turkcell"], hex: "FFC20E",
              glyph: .monogram("T"), category: .bills, isSubscription: true, darkGlyph: true),
        Brand(id: "vodafone", name: "Vodafone", keywords: ["vodafone"], hex: "E60000",
              glyph: .symbol("quote.closing"), category: .bills, isSubscription: true),
        Brand(id: "turktelekom", name: "Türk Telekom", keywords: ["turk telekom", "turktelekom", "ttnet"], hex: "1D4F91",
              glyph: .monogram("tt"), category: .bills, isSubscription: true),

        // Market, yemek, kahve
        Brand(id: "yemeksepeti", name: "Yemeksepeti", keywords: ["yemeksepeti", "yemek sepeti"], hex: "FA0050",
              glyph: .symbol("fork.knife"), category: .food, isSubscription: false),
        Brand(id: "migros", name: "Migros", keywords: ["migros"], hex: "F28C00",
              glyph: .monogram("M"), category: .market, isSubscription: false),
        Brand(id: "getir", name: "Getir", keywords: ["getir"], hex: "5D3EBC",
              glyph: .monogram("g"), category: .market, isSubscription: false),
        Brand(id: "starbucks", name: "Starbucks", keywords: ["starbucks"], hex: "00704A",
              glyph: .symbol("cup.and.saucer.fill"), category: .coffee, isSubscription: false),

        // Seyahat ve alışveriş
        Brand(id: "thy", name: "Türk Hava Yolları", keywords: ["thy", "turk hava yollari", "turkish airlines"], hex: "C8102E",
              glyph: .symbol("airplane"), category: .travel, isSubscription: false),
        Brand(id: "trendyol", name: "Trendyol", keywords: ["trendyol"], hex: "F27A1A",
              glyph: .monogram("t"), category: .shopping, isSubscription: false),
        Brand(id: "hepsiburada", name: "Hepsiburada", keywords: ["hepsiburada"], hex: "FF6000",
              glyph: .monogram("h"), category: .shopping, isSubscription: false),
    ]

    static func brand(id: String) -> Brand? {
        all.first { $0.id == id }
    }

    /// Normalize edilmiş metinde tam kelime olarak geçen ilk markayı döndürür.
    /// ("getirdim" Getir sayılmaz, "Migros'ta" Migros sayılır.)
    static func detect(inNormalized text: String) -> Brand? {
        all.first { brand in
            brand.keywords.contains { text.containsWord($0) }
        }
    }
}

// MARK: - Rozet

/// Marka varsa kurumsal renkli squircle rozet; yoksa kategori renginde tonlu ikon.
struct ExpenseBadge: View {
    let brand: Brand?
    let category: ExpenseCategory
    var size: CGFloat = 40

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)

        ZStack {
            if let brand {
                shape.fill(brand.color)
                glyph(for: brand)
                    .foregroundStyle(brand.glyphColor)
            } else {
                shape.fill(category.color.opacity(0.16))
                Image(systemName: category.symbol)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(category.color)
            }
        }
        .frame(width: size, height: size)
        .overlay(shape.strokeBorder(Theme.hairline, lineWidth: 1))
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func glyph(for brand: Brand) -> some View {
        switch brand.glyph {
        case .monogram(let letters):
            Text(verbatim: letters)
                .font(.system(size: size * (letters.count > 1 ? 0.38 : 0.5), weight: .black, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(size * 0.1)
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: size * 0.44, weight: .bold))
        }
    }
}
