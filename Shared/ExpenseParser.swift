//
//  ExpenseParser.swift
//  Kuruş — Doğal dil, taksit ve Türk bankası SMS motoru
//
//  Hedefler: App + Widget Extension
//
//  Örnekler:
//   "Netflix 229"                         → Netflix · ₺229 · Abonelik (tekrarlayan)
//   "Telefon 36000 3t"                    → Telefon · 3 × ₺12.000 · 1/3 taksit
//   "Bilet 4500 3 taksit"                 → Bilet · 3 × ₺1.500
//   "Kahve 145 bonus"                     → Kahve · ₺145 · Bonus kartı
//   "4532 ile biten Bonus kartınızla MIGROS işyerinde 642,50 TL harcama yapılmıştır."
//                                          → Migros · ₺642,50 · Bonus ••4532 · Market
//

import Foundation

// MARK: - Sonuç

struct ParsedExpense: Equatable, Sendable {
    var rawText: String
    var title: String
    /// Toplam tutar (taksitliyse tüm taksitlerin toplamı)
    var amount: Decimal?
    var installmentCount: Int = 1
    var category: ExpenseCategory = .other
    var brandID: String?
    var cardLast4: String?
    var bankName: String?
    var isCash: Bool = false
    var isRecurring: Bool = false
    var isFromSMS: Bool = false

    var isValid: Bool { (amount ?? 0) > 0 }

    var isIncome: Bool { category == .income }

    var brand: Brand? { brandID.flatMap(BrandEngine.brand(id:)) }

    var perInstallment: Decimal? {
        guard let amount else { return nil }
        return (amount / Decimal(max(installmentCount, 1))).rounded(2)
    }

    var cardLabel: String? {
        if isCash { return "Nakit" }
        switch (bankName, cardLast4) {
        case let (bank?, last4?): return "\(bank) ••\(last4)"
        case let (bank?, nil): return bank
        case let (nil, last4?): return "Kart ••\(last4)"
        default: return nil
        }
    }

    var compactCardLabel: String? {
        if let cardLast4 { return "••\(cardLast4)" }
        return cardLabel
    }
}

// MARK: - Motor

enum ExpenseParser {

    static func parse(_ input: String) -> ParsedExpense? {
        let raw = input
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }

        let norm = raw.kurusNormalized
        var working = raw
        var result = ParsedExpense(rawText: raw, title: "")

        // 1) Taksit: "3t", "3 t", "3 taksit", "6 taksitli"
        if let m = match(Patterns.installment, in: working),
           let g = m.group(1),
           let count = Int(working[g]),
           (2...48).contains(count) {
            result.installmentCount = count
            working.replaceSubrange(m.whole, with: " ")
        }

        // 2) Kartın son 4 hanesi
        for pattern in Patterns.cardLast4 {
            if let m = match(pattern, in: norm), let g = m.group(1) {
                result.cardLast4 = String(norm[g])
                break
            }
        }
        if let last4 = result.cardLast4 {
            working = working.replacingOccurrences(
                of: "(?<!\\d)\(last4)(?!\\d)", with: " ", options: .regularExpression
            )
        }

        // 3) Banka / kart programı
        result.bankName = Patterns.banks.first { norm.containsWord($0.keyword) }?.name

        // 4) Nakit
        result.isCash = norm.containsWord("nakit")

        // 4b) Gelir: başta "+" ("+Maaş 65000"), sayıya yapışık "+" ("İade +450") ya da gelir kelimeleri.
        //     Harfe yapışık "+" ("Disney+ 349") gelir sayılmaz.
        let incomeBySign = raw.hasPrefix("+")
            || raw.range(of: #"(?<![\p{L}\p{N}])\+\s*\d"#, options: .regularExpression) != nil
        let incomeByWord = Patterns.incomeWords.contains { keyword in
            let exact = keyword.hasSuffix("!")
            return norm.containsWord(exact ? String(keyword.dropLast()) : keyword, prefixOnly: !exact)
        }
        let isIncome = incomeBySign || incomeByWord
        if isIncome { result.installmentCount = 1 }

        // 5) Tutar — önce TL/TRY/₺ ile etiketli olan, yoksa en büyük sayı
        let candidates: [Candidate] = matches(Patterns.number, in: working).compactMap { m in
            guard let g = m.group(1), let value = decimal(from: String(working[g])), value > 0 else { return nil }
            return Candidate(value: value, tagged: isCurrencyTagged(g, in: working), range: m.whole)
        }
        if let chosen = candidates.first(where: { $0.tagged }) ?? candidates.max(by: { $0.value < $1.value }) {
            result.amount = chosen.value
            working.replaceSubrange(chosen.range, with: " ")
        }

        // 6) SMS mi?
        result.isFromSMS = result.cardLast4 != nil
            || norm.contains("isyeri")
            || (norm.contains("harcama") && norm.contains("kart"))

        // 7) Marka
        let brand = BrandEngine.detect(inNormalized: norm)
        result.brandID = brand?.id

        // 8) Başlık
        let title: String
        if let brand {
            title = brand.name
        } else if result.isFromSMS {
            title = extractMerchant(from: raw) ?? "\(result.bankName ?? "Kart") harcaması"
        } else {
            title = freeTitle(from: working)
        }

        // 9) Kategori ve tekrarlayan gider
        if isIncome {
            result.category = .income
            result.isRecurring = Patterns.recurringIncomeWords.contains { norm.containsWord($0, prefixOnly: true) }
        } else {
            // Kategori, taksit/kart/tutar ayıklanmış metinden çıkarılır: "3 taksit" içindeki
            // "taksi" önekinin Ulaşım'a düşmesi ("Yazıcı 4500 3 taksit" → Ulaşım) böylece engellenir.
            result.category = brand?.category ?? inferCategory(working.kurusNormalized) ?? .other
            result.isRecurring = (brand?.isSubscription ?? false)
                || Patterns.recurringWords.contains { norm.containsWord($0, prefixOnly: true) }
        }

        let finalTitle = title.isEmpty ? result.category.title : title
        result.title = String(finalTitle.prefix(42))
        return result
    }

    // MARK: Kategori çıkarımı

    private static func inferCategory(_ norm: String) -> ExpenseCategory? {
        for rule in Patterns.categoryRules {
            for keyword in rule.keywords {
                let exact = keyword.hasSuffix("!")
                let word = exact ? String(keyword.dropLast()) : keyword
                if norm.containsWord(word, prefixOnly: !exact) { return rule.category }
            }
        }
        return nil
    }

    // MARK: Başlık

    private static func freeTitle(from working: String) -> String {
        let stop: Set<String> = [
            "tl", "try", "lira", "nakit", "kart", "kartla", "kartiyla", "ile",
            "taksit", "taksitle", "taksitli", "kredi", "harcama"
        ]
        let bankWords = Set(Patterns.banks.map { $0.keyword }.filter { !$0.contains(" ") })
        let trimSet = CharacterSet.punctuationCharacters.union(.symbols)

        let tokens = working
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { token in
                let n = token.kurusNormalized.trimmingCharacters(in: trimSet)
                return !n.isEmpty && !stop.contains(n) && !bankWords.contains(n)
            }

        let joined = tokens.joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " -–—,.;:/*•+"))
        return joined.capitalizedFirstTR
    }

    /// "4532 ile biten Bonus kartınızla MIGROS TICARET A.S. işyerinde …" → "Migros"
    private static func extractMerchant(from raw: String) -> String? {
        let tokens = raw.split(whereSeparator: \.isWhitespace).map(String.init)
        let norms = tokens.map { $0.kurusNormalized.trimmingCharacters(in: .punctuationCharacters) }

        guard let anchor = norms.firstIndex(where: {
            $0.hasPrefix("isyeri") || $0.hasPrefix("firmasi") || $0.hasPrefix("magazasi")
        }), anchor > 0 else { return nil }

        var stop: Set<String> = [
            "ile", "kartinizla", "kartinizdan", "kartiniz", "kartinizin", "kartla", "karti",
            "kredi", "banka", "biten", "tarihinde", "saat", "tl", "try", "harcama", "nolu",
            "no'lu", "kartinizi", "tutarinda", "tutarli"
        ]
        Patterns.banks.map { $0.keyword }.filter { !$0.contains(" ") }.forEach { stop.insert($0) }
        let legal: Set<String> = ["a.s", "as", "ltd", "sti", "ltd.sti", "tic", "ticaret", "san", "ve", "a.ş"]

        var picked: [String] = []
        var i = anchor - 1
        while i >= 0, picked.count < 4 {
            let n = norms[i]
            if n.isEmpty || stop.contains(n) || n.contains(where: \.isNumber) { break }
            picked.insert(tokens[i], at: 0)
            i -= 1
        }

        let cleaned = picked.filter {
            !legal.contains($0.kurusNormalized.trimmingCharacters(in: .punctuationCharacters))
        }
        guard !cleaned.isEmpty else { return nil }

        return cleaned.joined(separator: " ")
            .trimmingCharacters(in: .punctuationCharacters)
            .lowercased(with: Locale(identifier: "en_US"))
            .capitalized(with: Locale(identifier: "tr_TR"))
    }

    // MARK: Tutar yardımcıları

    private struct Candidate {
        let value: Decimal
        let tagged: Bool
        let range: Range<String.Index>
    }

    /// "1.250,75" → 1250.75 · "12.000" → 12000 · "642,50" → 642.5 · "12.5" → 12.5
    static func decimal(from token: String) -> Decimal? {
        var s = token
        if s.contains(",") {
            s = s.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        } else if s.range(of: #"^\d{1,3}(\.\d{3})+$"#, options: .regularExpression) != nil {
            s = s.replacingOccurrences(of: ".", with: "")
        }
        return Decimal(string: s, locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func isCurrencyTagged(_ range: Range<String.Index>, in text: String) -> Bool {
        let after = text[range.upperBound...].drop(while: { $0 == " " }).prefix(4).lowercased()
        if after.hasPrefix("tl") || after.hasPrefix("try") || after.hasPrefix("₺") || after.hasPrefix("lira") {
            return true
        }
        let before = String(text[..<range.lowerBound].reversed().drop(while: { $0 == " " }).prefix(2)).lowercased()
        return before.hasPrefix("₺") || before.hasPrefix("lt")
    }

    // MARK: Regex yardımcıları

    private struct Match {
        let whole: Range<String.Index>
        let groups: [Range<String.Index>?]

        func group(_ index: Int) -> Range<String.Index>? {
            index >= 1 && index - 1 < groups.count ? groups[index - 1] : nil
        }
    }

    private static func match(_ pattern: String, in text: String) -> Match? {
        matches(pattern, in: text).first
    }

    private static func matches(_ pattern: String, in text: String) -> [Match] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { m in
            guard let whole = Range(m.range, in: text) else { return nil }
            let groups = (0..<max(m.numberOfRanges - 1, 0)).map { Range(m.range(at: $0 + 1), in: text) }
            return Match(whole: whole, groups: groups)
        }
    }
}

// MARK: - Desenler ve sözlükler

private enum Patterns {
    static let installment = #"(?<![\d.,])(\d{1,2})\s*(?:taksit\w*|tk|t)(?![\p{L}\d])"#

    static let number = #"(?<![\p{L}\d.,:/])(\d{1,3}(?:\.\d{3})+(?:,\d{1,2})?|\d+(?:[.,]\d{1,2})?)(?![\d:/]|[.,]\d)"#

    /// Normalize edilmiş metin üzerinde çalışır.
    static let cardLast4: [String] = [
        #"(\d{4})\s*ile\s*biten"#,
        #"(?:\*{2,}|•{2,}|x{3,})\s?(\d{4})(?!\d)"#,
        #"son\s*(?:4|dort)\s*hane\w*\s*:?\s*(\d{4})"#,
        #"(\d{4})\s*(?:no'?lu|numarali)\s*kart"#,
    ]

    /// Önce kart programları (Bonus, World…), sonra bankalar.
    static let banks: [(keyword: String, name: String)] = [
        ("bonus", "Bonus"), ("world", "World"), ("maximum", "Maximum"), ("axess", "Axess"),
        ("cardfinans", "CardFinans"), ("paraf", "Paraf"), ("bankkart", "Bankkart"),
        ("advantage", "Advantage"), ("wings", "Wings"), ("miles&smiles", "Miles&Smiles"),
        ("shop&fly", "Shop&Fly"), ("enpara", "Enpara"), ("papara", "Papara"),
        ("garanti", "Garanti BBVA"), ("akbank", "Akbank"), ("yapi kredi", "Yapı Kredi"),
        ("is bankasi", "İş Bankası"), ("isbank", "İş Bankası"), ("ziraat", "Ziraat"),
        ("halkbank", "Halkbank"), ("vakifbank", "VakıfBank"), ("qnb", "QNB"),
        ("denizbank", "DenizBank"), ("teb", "TEB"), ("ing", "ING"),
        ("kuveyt turk", "Kuveyt Türk"), ("albaraka", "Albaraka"),
    ]

    static let recurringWords = ["abonelik", "aylik", "uyelik", "premium"]

    /// Gelir kelimeleri ("!" → tam kelime). "Bonus" bir kart adı olduğu için bilinçli olarak yok.
    static let incomeWords = ["maas", "gelir", "iade", "prim!", "ikramiye", "kira geliri"]
    static let recurringIncomeWords = ["maas", "kira geliri"]

    struct CategoryRule {
        let category: ExpenseCategory
        /// Sonu "!" ile biten kelimeler tam eşleşir; diğerleri kelime başı (önek) eşleşir.
        let keywords: [String]
    }

    /// Sıra önemlidir; daha özgül kurallar önce gelir:
    /// "telefon faturası" → Fatura (Teknoloji'den önce), "yarım ekmek" → Yemek (Birikim'den önce),
    /// "tam pansiyon" → Seyahat. Tüm eşleşmeler `\b` kelime sınırıyla yapılır.
    static let categoryRules: [CategoryRule] = [
        CategoryRule(category: .bills, keywords: [
            "fatura", "elektrik", "dogalgaz", "su faturasi", "internet", "kira", "aidat",
            "telefon faturasi", "enerjisa", "igdas", "iski", "superonline"
        ]),
        CategoryRule(category: .coffee, keywords: [
            "kahve", "espresso", "latte", "americano", "cappuccino", "cafe", "kafe",
            "nero!", "cay!", "mocha"
        ]),
        CategoryRule(category: .food, keywords: [
            "yemek", "restoran", "lokanta", "doner", "burger", "pizza", "kebap", "kebab",
            "lahmacun", "simit", "pide", "sushi", "kofte", "kahvalti", "ogle", "aksam yemegi",
            "tatli", "baklava", "manti", "ekmek"
        ]),
        CategoryRule(category: .market, keywords: [
            "market", "a101!", "bim!", "sok!", "carrefour", "file!", "macrocenter", "manav",
            "kasap", "firin", "bakkal", "sarkuteri"
        ]),
        CategoryRule(category: .travel, keywords: [
            "ucak", "otel", "pansiyon", "pegasus", "sunexpress", "ajet", "tatil", "airbnb",
            "booking", "vize", "pasaport", "obilet"
        ]),
        CategoryRule(category: .savings, keywords: [
            "birikim", "yatirim", "altin", "gumus", "gram!", "ceyrek", "yarim!", "tam!",
            "cumhuriyet", "ons!", "fon!", "hisse", "borsa", "kripto", "dolar", "euro",
            "bitcoin", "doviz", "kumbara", "mevduat", "bes!", "usd!", "eur!"
        ]),
        CategoryRule(category: .transport, keywords: [
            "taksi", "uber", "bitaksi", "benzin", "akaryakit", "mazot", "dizel", "otopark",
            "otobus", "metro", "istanbulkart", "marmaray", "shell", "opet", "bp!", "petrol",
            "otoyol", "hgs!", "ogs!", "kopru", "marti!", "vapur", "dolmus"
        ]),
        CategoryRule(category: .subscription, keywords: [
            "abonelik", "uyelik", "exxen", "blutv", "gain!", "tod!", "apple music", "tabii"
        ]),
        CategoryRule(category: .entertainment, keywords: [
            "sinema", "bilet", "konser", "tiyatro", "steam", "playstation", "xbox", "bowling",
            "muze", "mac bileti", "festival", "oyun"
        ]),
        CategoryRule(category: .health, keywords: [
            "eczane", "ilac", "hastane", "doktor", "dis!", "dishekimi", "muayene", "vitamin",
            "spor salonu", "gym!", "diyetisyen", "psikolog"
        ]),
        CategoryRule(category: .education, keywords: [
            "kurs", "kitap", "okul", "udemy", "egitim", "harc!", "kirtasiye", "ders"
        ]),
        CategoryRule(category: .technology, keywords: [
            "yazici", "bilgisayar", "laptop", "macbook", "telefon", "iphone", "ipad", "kulaklik",
            "airpods", "sarj", "kablo", "monitor", "klavye", "mouse", "tablet", "samsung",
            "teknosa", "mediamarkt", "vatan bilgisayar"
        ]),
        CategoryRule(category: .shopping, keywords: [
            "kiyafet", "ayakkabi", "zara", "h&m", "lcw", "amazon", "ikea", "koton",
            "mavi!", "defacto", "kozmetik", "parfum", "sephora", "watsons", "gratis"
        ]),
    ]
}

// MARK: - Metin yardımcıları

extension String {
    /// Türkçe duyarlı normalize: küçük harf, aksansız ("Türk Telekom" → "turk telekom", "MIGROS" → "migros").
    var kurusNormalized: String {
        self.replacingOccurrences(of: "ı", with: "i")
            .replacingOccurrences(of: "İ", with: "i")
            .replacingOccurrences(of: "I", with: "i")
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                     locale: Locale(identifier: "en_US_POSIX"))
    }

    /// Harf/rakam sınırlarına saygılı kelime araması (normalize metinde).
    func containsWord(_ word: String, prefixOnly: Bool = false) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: word)
        // \b kelime sınırı: anahtar kelime ancak bir kelimenin BAŞINDA eşleşir ("yazici" içindeki
        // alt diziler başka kurallara düşmez). prefixOnly=false ise kelimenin tamamı eşleşmelidir.
        let pattern = "\\b" + escaped + (prefixOnly ? "" : "\\b")
        return range(of: pattern, options: .regularExpression) != nil
    }

    var capitalizedFirstTR: String {
        guard let first else { return self }
        return String(first).uppercased(with: Locale(identifier: "tr_TR")) + dropFirst()
    }
}
