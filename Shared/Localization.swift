//
//  Localization.swift
//  Kuruş / Cent — Dil, marka adı ve yerel para biçimi
//
//  Hedefler: App + Widget Extension
//
//  • Cihaz dili Türkçe ise marka "Kuruş", diğer tüm dillerde "Cent".
//  • Para birimi ve ayırıcılar `Locale.current`'tan gelir: tr_TR → ₺1.250,50 · en_US → $1,250.50
//    · de_DE → 1.250,50 € · en_GB → £1,250.50. Sembolün önde/arkada olması da yereldir.
//

import Foundation

// MARK: - Dil ve marka

enum AppLanguage {
    /// Uygulamanın görüntülediği dil Türkçe mi?
    static var isTurkish: Bool {
        Locale.current.language.languageCode?.identifier == "tr"
    }

    /// Uygulama içi marka adı: "Kuruş" (tr) / "Cent" (diğer diller)
    static var brandName: String { isTurkish ? "Kuruş" : "Cent" }

    /// Dosya adları için ASCII marka: "Kurus" / "Cent"
    static var brandSlug: String { isTurkish ? "Kurus" : "Cent" }
}

/// Çift dilli metin: Türkçe cihazda ilk, diğer dillerde ikinci (İngilizce) değer.
/// SwiftUI'de `Text(L(...))` String başlatıcısını kullanır; katalog araması yapılmaz.
func L(_ turkish: String, _ english: String) -> String {
    AppLanguage.isTurkish ? turkish : english
}

// MARK: - Para birimi

enum Money {
    /// Cihaz bölgesinin para birimi (TR → TRY, US → USD, DE → EUR, GB → GBP).
    /// `Expense.currencyCode == nil` olan kayıtlar bu para birimindedir.
    static var homeCurrency: String {
        Locale.current.currency?.identifier ?? (AppLanguage.isTurkish ? "TRY" : "USD")
    }

    /// Ayrıştırıcının tanıdığı sembol/kod/kelime → ISO kod.
    static let symbols: [String: String] = ["₺": "TRY", "$": "USD", "€": "EUR", "£": "GBP"]
    static let codes: [String: String] = ["try": "TRY", "tl": "TRY", "usd": "USD", "eur": "EUR", "gbp": "GBP"]
    /// Yalnızca tutarın ARDINDAN gelince para birimi sayılır ("Kahve 5 dolar"); önde gelen
    /// "Dolar 1000" döviz alımı (Birikim) olarak kalır.
    static let trailingWords: [String: String] = [
        "lira": "TRY", "dolar": "USD", "dollar": "USD", "dollars": "USD", "bucks": "USD",
        "euro": "EUR", "euros": "EUR", "avro": "EUR", "pound": "GBP", "pounds": "GBP", "sterlin": "GBP",
    ]
}

// MARK: - Yerel para biçimi

enum CurrencyFormat {

    struct Style: Sendable {
        let symbol: String
        let symbolFirst: Bool
        let spacing: String
        let grouping: String
        let decimal: String
    }

    /// `NumberFormatter` her çizimde yeniden kurulmasın diye (yerel ayar + para birimi) başına önbellek.
    private final class Cache: @unchecked Sendable {
        private let lock = NSLock()
        private var styles: [String: Style] = [:]

        func style(for key: String, make: () -> Style) -> Style {
            lock.lock()
            defer { lock.unlock() }
            if let cached = styles[key] { return cached }
            let made = make()
            styles[key] = made
            return made
        }
    }

    private static let cache = Cache()

    static func style(for currency: String? = nil) -> Style {
        let code = currency ?? Money.homeCurrency
        let locale = Locale.current
        return cache.style(for: "\(locale.identifier)|\(code)") {
            let f = NumberFormatter()
            f.locale = locale
            f.numberStyle = .currency
            f.currencyCode = code
            let symbol = f.currencySymbol ?? code
            let pattern = (f.positiveFormat ?? "¤#,##0.00").trimmingCharacters(in: .whitespaces)
            let symbolFirst = pattern.hasPrefix("¤")
            let spacedPattern = pattern.contains("¤ ") || pattern.contains(" ¤")
                || pattern.contains("¤\u{00A0}") || pattern.contains("\u{00A0}¤")
            // "TRY1,250.00" gibi harfli sembollerde boşluk şart.
            let needsSpace = spacedPattern || symbol.contains(where: \.isLetter)
            return Style(
                symbol: symbol,
                symbolFirst: symbolFirst,
                spacing: needsSpace ? "\u{00A0}" : "",
                grouping: f.currencyGroupingSeparator ?? locale.groupingSeparator ?? ",",
                decimal: f.currencyDecimalSeparator ?? locale.decimalSeparator ?? "."
            )
        }
    }

    /// Tutar parçaları: işaret, gruplanmış tam kısım, iki haneli kuruş/cent ve yerel stil.
    static func parts(_ value: Decimal, currency: String? = nil) -> (sign: String, integer: String, fraction: String, style: Style) {
        let style = style(for: currency)
        let rounded = value.rounded(2)
        let negative = rounded < 0
        let absolute = negative ? -rounded : rounded
        let cents = NSDecimalNumber(decimal: absolute * 100).int64Value
        return (
            negative ? "−" : "",
            grouped(cents / 100, separator: style.grouping),
            String(format: "%02lld", cents % 100),
            style
        )
    }

    static func grouped(_ value: Int64, separator: String) -> String {
        let digits = String(value)
        var out = ""
        for (index, char) in digits.enumerated() {
            if index > 0, (digits.count - index) % 3 == 0 { out.append(separator) }
            out.append(char)
        }
        return out
    }

    /// "₺12.000,50" · "$12,000.50" · "12.000,50 €" — `fraction: false` ile yuvarlanmış tam sayı.
    static func string(_ value: Decimal, fraction: Bool = true, currency: String? = nil) -> String {
        let p = parts(fraction ? value : value.rounded(0), currency: currency)
        let s = p.style
        let number = p.integer + (fraction ? s.decimal + p.fraction : "")
        return s.symbolFirst
            ? "\(p.sign)\(s.symbol)\(s.spacing)\(number)"
            : "\(p.sign)\(number)\(s.spacing)\(s.symbol)"
    }

    /// CSV için: gruplamasız, yerel ondalık ayırıcı ("642,50" / "642.50").
    static func plain(_ value: Decimal) -> String {
        let p = parts(value)
        return "\(p.sign.isEmpty ? "" : "-")\(p.integer.replacingOccurrences(of: p.style.grouping, with: ""))\(p.style.decimal)\(p.fraction)"
    }
}

// MARK: - Dile göre örnekler (açılış demosu, widget çipleri, giriş ipucu)

struct QuickSample: Identifiable, Sendable {
    let id: String
    let title: String
    let amount: Decimal
    let category: ExpenseCategory

    /// Ayrıştırıcıya giden komut: "Kahve 145", "S&P 500 500"
    var command: String { "\(title) \(NSDecimalNumber(decimal: amount).stringValue)" }
}

enum QuickSamples {
    static var all: [QuickSample] {
        AppLanguage.isTurkish
            ? [
                QuickSample(id: "coffee", title: "Kahve", amount: 145, category: .coffee),
                QuickSample(id: "market", title: "Migros", amount: 640, category: .market),
                QuickSample(id: "savings", title: "Altın", amount: 4500, category: .savings),
            ]
            : [
                QuickSample(id: "coffee", title: "Coffee", amount: 5, category: .coffee),
                QuickSample(id: "market", title: "Whole Foods", amount: 85, category: .market),
                QuickSample(id: "savings", title: "S&P 500", amount: 500, category: .savings),
            ]
    }

    /// İlk açılış demosu — "Aha!" anı: marka, kart, abonelik, taksit ve birikim dört girişte.
    /// (Widget çipleri `all` listesini kullanır; demo ondan bağımsızdır.)
    /// 1) Günlük harcama + marka  2) Karta bağlı abonelik  3) Kartla taksitli alışveriş  4) Birikim
    /// İngilizcede "Chase" banka sözlüğünde olmadığı için kart adı yazılmaz.
    static var demoCommands: [String] {
        AppLanguage.isTurkish
            ? ["Migros 850", "Netflix 109 Yapı Kredi", "Apple 6000 3 taksit Yapı Kredi", "Altın 2000"]
            : ["Whole Foods 85", "Netflix 15", "Apple 600 3x", "S&P 500 500"]
    }

    /// Giriş çubuğu ipucu (ilk görünen)
    static var placeholder: String { hints[0] }

    /// Giriş kutusu boşken birkaç saniyede bir dönen örnek komutlar (Heuristic #10).
    /// Yalnızca ayrıştırıcının gerçekten anladığı komutlar: tutar, marka, taksit, gelir, "dün".
    static var hints: [String] {
        AppLanguage.isTurkish
            ? ["Kahve 85 TL", "Netflix 109", "Market 450 dün", "Telefon 36000 3t", "+Maaş 65000", "Kira 25000"]
            : ["Coffee $5", "Spotify 11", "Lunch 12 yesterday", "Laptop 1200 3x", "+Salary 5000", "$45 Walmart"]
    }
}

// MARK: - Yüzde

enum Percent {
    /// tr: "%62" · en: "62%" · çok küçük paylar: "<%1" / "<1%"
    static func string(_ share: Double) -> String {
        if share > 0, share < 0.01 { return L("<%1", "<1%") }
        let value = Int((share * 100).rounded())
        return L("%\(value)", "\(value)%")
    }
}
