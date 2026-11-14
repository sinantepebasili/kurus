//
//  ExpenseParser.swift
//  Kuruş / Cent — Çift dilli (TR + EN) doğal dil, taksit, dikte ve SMS / Apple Pay motoru
//
//  Hedefler: App + Widget Extension
//
//  Örnekler:
//   "Netflix 229"                          → Netflix · 229 · Abonelik (tekrarlayan)
//   "Telefon 36000 3t" / "Tablet 12000 üç taksit"  → 3 taksit, başlık "Telefon" / "Tablet"
//   "Laptop 1,200.00 in 4 installments"    → 4 × 300 · "Laptop"
//   "Coffee 5 yesterday" / "Kahve 145 dün" → dünün tarihiyle
//   Sesli dikte: "Coffee five dollars" → 5 · "Coffee five cents" → 0,05 · "Cinema one dollar one" → 1, "Cinema"
//                "Kahve yüz kırk beş lira" → 145 · "Market iki yüz" → 200
//   "+Maaş 65000", "İade +450", "+Salary 5000", "Refund +120" → Gelir
//   "4532 ile biten Bonus kartınızla MIGROS işyerinde 642,50 TL harcama yapılmıştır."
//                                          → Migros · ₺642,50 · Bonus ••4532 · Market
//   "Card ending in 4532 at Whole Foods for $84.50"
//                                          → Whole Foods · $84.50 · ••4532 · Groceries
//

import Foundation

// MARK: - Sonuç

struct ParsedExpense: Equatable, Sendable {
    var rawText: String
    var title: String
    /// Toplam tutar (taksitliyse tüm taksitlerin toplamı)
    var amount: Decimal?
    /// Metinde açıkça yazılan yabancı para birimi (ör. "$14.50" → "USD"). `nil` → ana para birimi.
    var currencyCode: String?
    var installmentCount: Int = 1
    /// 0 → bugün, -1 → "dün" / "yesterday"
    var dayOffset: Int = 0
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
        if isCash { return L("Nakit", "Cash") }
        switch (bankName, cardLast4) {
        case let (bank?, last4?): return "\(bank) ••\(last4)"
        case let (bank?, nil): return bank
        case let (nil, last4?): return "\(L("Kart", "Card")) ••\(last4)"
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
        let normTokens = SmartCategoryMatcher.tokens(norm)
        var working = raw
        var result = ParsedExpense(rawText: raw, title: "")

        // 1) Taksit — rakamla: "3t", "3 taksit", "6 taksitli", "3x", "3 installments", "in 4 installments"
        //    ya da dikte: "üç taksit", "on iki taksitle", "four installments", "in twelve installments".
        //    Sayı ve taksit kelimesi başlıktan da temizlenir ("Tablet üç" kalmaz).
        if let m = match(Patterns.installment, in: working),
           let g = m.group(1),
           let count = Int(working[g]),
           (2...48).contains(count) {
            result.installmentCount = count
            working.replaceSubrange(m.whole, with: " ")
        } else if let spoken = extractSpokenInstallment(from: working) {
            result.installmentCount = spoken.count
            working = spoken.cleaned
        }

        // 1b) Tarih: "dün" / "yesterday" → dün, "bugün" / "today" → bugün (kelime başlıktan çıkar)
        if let day = extractDayWord(from: working) {
            result.dayOffset = day.offset
            working = day.cleaned
        }

        // 2) Kartın son 4 hanesi: "4532 ile biten", "card ending in 4532", "••4532", "**** 4532"
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

        // 4) Nakit / cash
        result.isCash = norm.containsWord("nakit") || norm.containsWord("cash")

        // 4b) Gelir: başta "+" ("+Maaş 65000", "+Salary 5000"), sayıya yapışık "+" ("İade +450",
        //     "Refund +120") ya da gelir kelimeleri. Harfe yapışık "+" ("Disney+ 349") gelir sayılmaz.
        let incomeBySign = raw.hasPrefix("+")
            || raw.range(of: #"(?<![\p{L}\p{N}])\+\s*[$€£₺]?\s*\d"#, options: .regularExpression) != nil
        let incomeByWord = SmartCategoryMatcher.matches(tokens: normTokens, keywords: Patterns.incomeWords)
        let isIncome = incomeBySign || incomeByWord
        if isIncome { result.installmentCount = 1 }

        // 5) Tutar ve para birimi. Öncelik sırası:
        //    a) rakamla + para birimi etiketli ("642,50 TL", "$14.50", "USD 25.00", "5 dollars")
        //    b) yazıyla + para birimi etiketli — sesli dikte ("five dollars", "yüz kırk beş lira", "five cents")
        //    c) rakamla, etiketsiz → en büyük sayı ("Kahve 145")
        //    d) yazıyla, etiketsiz — metinde hiç rakam yoksa ("Coffee five", "Market iki yüz")
        let candidates: [Candidate] = matches(Patterns.number, in: working).compactMap { m in
            guard let g = m.group(1), let value = decimal(from: String(working[g])), value > 0 else { return nil }
            let tag = currencyTag(for: m.whole, in: working)
            return Candidate(value: value, currency: tag?.code, range: tag?.range ?? m.whole)
        }
        let taggedDigits = candidates.first(where: { $0.currency != nil })
        let spoken = taggedDigits == nil ? extractSpokenAmount(from: working) : nil

        if let spoken, spoken.isTagged || candidates.isEmpty {
            result.amount = spoken.value
            result.currencyCode = spoken.currency
            working = spoken.cleaned
        } else if let chosen = taggedDigits ?? candidates.max(by: { $0.value < $1.value }) {
            result.amount = chosen.value
            if let code = chosen.currency, code != Money.homeCurrency {
                result.currencyCode = code
            }
            working.replaceSubrange(chosen.range, with: " ")
        }

        // 6) Bildirim mi? (Türk banka SMS'i ya da İngilizce banka / Apple Pay bildirimi)
        let isTurkishSMS = norm.contains("isyeri")
            || (norm.contains("harcama") && norm.contains("kart"))
            || (result.cardLast4 != nil && norm.contains("biten"))
        let isEnglishSMS = SmartCategoryMatcher.matches(tokens: normTokens, keywords: Patterns.englishNoticeWords)
            || (result.cardLast4 != nil && !isTurkishSMS)
        result.isFromSMS = result.cardLast4 != nil || isTurkishSMS || isEnglishSMS

        // 7) Marka
        let brand = BrandEngine.detect(inNormalized: norm)
        result.brandID = brand?.id

        // 8) Başlık
        let title: String
        if let brand {
            title = brand.name
        } else if isTurkishSMS {
            title = extractTurkishMerchant(from: raw)
                ?? "\(result.bankName ?? "Kart") harcaması"
        } else if isEnglishSMS {
            title = extractEnglishMerchant(from: raw) ?? freeTitle(from: working)
        } else {
            title = freeTitle(from: working)
        }

        // 9) Kategori ve tekrarlayan gider / gelir
        if isIncome {
            result.category = .income
            result.isRecurring = SmartCategoryMatcher.matches(tokens: normTokens, keywords: Patterns.recurringIncomeWords)
        } else {
            // Kategori, taksit/kart/tutar ayıklanmış metinden çıkarılır: "3 taksit" içindeki
            // "taksi" önekinin Ulaşım'a düşmesi böylece engellenir.
            result.category = brand?.category ?? inferCategory(working) ?? .other
            result.isRecurring = (brand?.isSubscription ?? false)
                || SmartCategoryMatcher.matches(tokens: normTokens, keywords: Patterns.recurringWords)
        }

        let finalTitle = title.isEmpty ? result.category.title : title
        result.title = String(finalTitle.prefix(42))
        return result
    }

    // MARK: Kategori çıkarımı

    private static func inferCategory(_ text: String) -> ExpenseCategory? {
        let tokens = SmartCategoryMatcher.tokens(text.kurusNormalized)
        // "=" ile başlayan anahtar kelimeler için aksanı korunmuş küçük harfli token'lar ("maç" ≠ "mac")
        let accentTokens = SmartCategoryMatcher.tokens(text.lowercased())
        for rule in Patterns.categoryRules
        where SmartCategoryMatcher.matches(tokens: tokens, keywords: rule.keywords, accentTokens: accentTokens) {
            return rule.category
        }
        return nil
    }

    // MARK: Dikte ile yazılı tutar (TR + EN)

    /// Sayı kelimeleri (normalize): değer < 100
    private static let numberWords: [String: Int] = [
        // Türkçe
        "bir": 1, "iki": 2, "uc": 3, "dort": 4, "bes": 5, "alti": 6, "yedi": 7, "sekiz": 8, "dokuz": 9,
        "on": 10, "yirmi": 20, "otuz": 30, "kirk": 40, "elli": 50, "altmis": 60, "yetmis": 70,
        "seksen": 80, "doksan": 90,
        // English
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15,
        "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19, "twenty": 20, "thirty": 30,
        "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
    ]
    private static let hundredWords: Set<String> = ["yuz", "hundred"]
    private static let thousandWords: Set<String> = ["bin", "thousand"]
    private static let turkishUnits: Set<String> = ["bir", "iki", "uc", "dort", "bes", "alti", "yedi", "sekiz", "dokuz"]

    /// Ana birim kelimeleri → ISO kod ("dollars", "bucks", "lira", "tl", "euro"…)
    private static func majorCurrency(_ word: String) -> String? {
        Money.trailingWords[word] ?? Money.codes[word] ?? (word == "buck" ? "USD" : nil)
    }

    /// Alt birim kelimeleri → ISO kod. "cent" ana para birimi USD/EUR ise onu, değilse USD'yi kullanır.
    private static func subunitCurrency(_ word: String) -> String? {
        switch word {
        case "cent", "cents":
            return ["USD", "EUR"].contains(Money.homeCurrency) ? Money.homeCurrency : "USD"
        case "kurus": return "TRY"
        case "penny", "pence": return "GBP"
        default: return nil
        }
    }

    private enum NumberWord: Equatable {
        case value(Int), hundred, thousand, connector, article
    }

    struct SpokenAmount: Equatable {
        let value: Decimal
        /// Ana para biriminden farklıysa ISO kod, değilse `nil`
        let currency: String?
        /// Bir para birimi kelimesine bağlı mı ("five dollars")
        let isTagged: Bool
        /// Sayı ve para birimi kelimeleri çıkarılmış metin
        let cleaned: String
    }

    /// Yazıyla söylenmiş tutarı bulur:
    /// "Coffee five dollars" → 5 · "Coffee five cents" → 0,05 · "two dollars fifty cents" → 2,50
    /// "Kahve yüz kırk beş lira" → 145 · "Market iki yüz" → 200 · "Cinema one dollar one" → 1 ("Cinema")
    static func extractSpokenAmount(from text: String) -> SpokenAmount? {
        // Tireli birleşikleri ayır: "twenty-five" → "twenty", "five"
        var raw: [String] = []
        for token in text.split(whereSeparator: \.isWhitespace).map(String.init) {
            let parts = token.split(separator: "-").map(String.init)
            if parts.count > 1, parts.allSatisfy({ numberWords[$0.kurusNormalized.trimmingCharacters(in: .punctuationCharacters)] != nil }) {
                raw.append(contentsOf: parts)
            } else {
                raw.append(token)
            }
        }
        let words = raw.map { $0.kurusNormalized.trimmingCharacters(in: .punctuationCharacters) }
        let count = words.count
        guard count > 0 else { return nil }

        func isCurrencyWord(_ i: Int) -> Bool {
            i < count && (majorCurrency(words[i]) != nil || subunitCurrency(words[i]) != nil)
        }

        // Sözcük türleri
        var kinds: [NumberWord?] = words.map { word in
            if let v = numberWords[word] { return .value(v) }
            if hundredWords.contains(word) { return .hundred }
            if thousandWords.contains(word) { return .thousand }
            if word == "and" { return .connector }
            if word == "a" { return .article }
            return nil
        }
        // "on" hem Türkçe 10 hem İngilizce edat: yalnızca sayı bağlamında sayı sayılır
        // ("on beş" ✓, "yüz on" ✓, "on lira" ✓ — "dinner on me" ✗, "twenty on lunch" ✗)
        for i in 0..<count where words[i] == "on" {
            let afterHundred = i > 0 && (words[i - 1] == "yuz" || words[i - 1] == "bin")
            let beforeUnit = i + 1 < count && turkishUnits.contains(words[i + 1])
            let beforeCurrency = isCurrencyWord(i + 1)
            let loneTurkish = AppLanguage.isTurkish && i == count - 1 && (i == 0 || kinds[i - 1] == nil)
            if !(afterHundred || beforeUnit || beforeCurrency || loneTurkish) { kinds[i] = nil }
        }

        func isNumeric(_ i: Int) -> Bool {
            guard i < count, let kind = kinds[i] else { return false }
            switch kind {
            case .value, .hundred, .thousand: return true
            default: return false
            }
        }

        // Ardışık sayı kelimelerini koşulara (run) ayır
        struct Run { var start: Int; var end: Int; var value: Int; var consumedEnd: Int; var amount: Decimal; var currency: String?; var tagged: Bool }
        var runs: [Run] = []
        var i = 0
        while i < count {
            let startsWithArticle = kinds[i] == .article && (i + 1 < count && (kinds[i + 1] == .hundred || kinds[i + 1] == .thousand))
            guard isNumeric(i) || startsWithArticle else { i += 1; continue }
            var j = i + 1
            while j < count {
                if isNumeric(j) { j += 1; continue }
                if kinds[j] == .connector, isNumeric(j + 1) { j += 1; continue }
                break
            }
            // Değer: "iki yüz" = 2×100, "bin iki yüz" = 1000+200, "twenty five" = 25
            var total = 0
            var current = 0
            for k in i..<j {
                switch kinds[k] {
                case .value(let v)?: current += v
                case .hundred?: current = max(current, 1) * 100
                case .thousand?: total += max(current, 1) * 1000; current = 0
                default: break
                }
            }
            let value = total + current
            var run = Run(start: i, end: j, value: value, consumedEnd: j, amount: Decimal(value), currency: nil, tagged: false)

            // Para birimi: "five dollars" · "five cents" · "two dollars (and) fifty cents"
            if j < count, let code = majorCurrency(words[j]) {
                run.currency = code
                run.tagged = true
                run.consumedEnd = j + 1
                var k = j + 1
                if k < count, kinds[k] == .connector { k += 1 }
                if isNumeric(k) {
                    var m = k
                    var cents = 0
                    while m < count, isNumeric(m) {
                        if case .value(let v)? = kinds[m] { cents += v }
                        m += 1
                    }
                    if m < count, subunitCurrency(words[m]) != nil, cents < 100 {
                        run.amount += Decimal(cents) / 100
                        run.consumedEnd = m + 1
                    }
                }
            } else if j < count, let code = subunitCurrency(words[j]) {
                run.currency = code
                run.tagged = true
                run.amount = Decimal(value) / 100
                run.consumedEnd = j + 1
            }

            if value > 0 { runs.append(run) }
            i = max(run.consumedEnd, j)
        }

        // Etiketli ilk koşu, yoksa sonuncusu ("Bir kahve otuz" → 30)
        guard let chosen = runs.first(where: { $0.tagged }) ?? runs.last else { return nil }

        // Seçilen koşu + para birimi kelimeleri ve aynı değerli dikte tekrarları ("one dollar one") çıkarılır
        var removed = Set<Int>()
        for run in runs where run.start == chosen.start || run.value == chosen.value {
            removed.formUnion(run.start..<run.consumedEnd)
        }
        let cleaned = raw.enumerated().filter { !removed.contains($0.offset) }.map(\.element).joined(separator: " ")

        let currency = chosen.currency.flatMap { $0 == Money.homeCurrency ? nil : $0 }
        return SpokenAmount(value: chosen.amount, currency: currency, isTagged: chosen.tagged, cleaned: cleaned)
    }

    // MARK: Dikte ile taksit (TR + EN)

    private static let spokenUnits: [String: Int] = [
        // Türkçe
        "bir": 1, "iki": 2, "uc": 3, "dort": 4, "bes": 5, "alti": 6, "yedi": 7, "sekiz": 8, "dokuz": 9,
        // English
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
    ]
    /// Tek başına kullanılan sayılar (EN 10–19)
    private static let spokenTeens: [String: Int] = [
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15,
        "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19,
    ]
    private static let spokenTens: [String: Int] = [
        "on": 10, "yirmi": 20, "otuz": 30, "kirk": 40,
        "twenty": 20, "thirty": 30, "forty": 40,
    ]

    /// "Telefon 36000 üç taksit" → (3, "Telefon 36000") · "Laptop 1200 in four installments" → (4, "Laptop 1200")
    /// "on iki taksitle" / "oniki taksit" / "twenty-four installments" da desteklenir.
    private static func extractSpokenInstallment(from text: String) -> (count: Int, cleaned: String)? {
        var tokens = text.split(whereSeparator: \.isWhitespace).map(String.init)
        let norms = tokens.map { $0.kurusNormalized.trimmingCharacters(in: .punctuationCharacters) }
        guard let anchor = norms.firstIndex(where: { $0.hasPrefix("taksit") || $0.hasPrefix("installment") }),
              anchor > 0 else { return nil }

        let previous = norms[anchor - 1]
        var value = 0
        var used = 0
        if let unit = spokenUnits[previous] {
            value = unit
            used = 1
            if anchor >= 2, let ten = spokenTens[norms[anchor - 2]] {
                value += ten
                used = 2
            }
        } else if let whole = spokenTeens[previous] ?? spokenTens[previous] {
            value = whole
            used = 1
        } else if let compound = compoundSpokenNumber(previous) {
            value = compound
            used = 1
        }

        guard used > 0, (2...48).contains(value) else { return nil }
        var start = anchor - used
        // "in four installments" → "in" de kalkar
        if start > 0, norms[start - 1] == "in" { start -= 1 }
        tokens.removeSubrange(start...anchor)
        return (value, tokens.joined(separator: " "))
    }

    /// Bitişik / tireli: "onaltı" → 16, "yirmidört" → 24, "twenty-four" → 24
    private static func compoundSpokenNumber(_ word: String) -> Int? {
        let pieces = word.split(separator: "-").map(String.init)
        if pieces.count == 2, let ten = spokenTens[pieces[0]], let unit = spokenUnits[pieces[1]] {
            return ten + unit
        }
        for (tenWord, tenValue) in spokenTens where word.hasPrefix(tenWord) {
            if let unit = spokenUnits[String(word.dropFirst(tenWord.count))] { return tenValue + unit }
        }
        return nil
    }

    // MARK: Tarih kelimeleri

    /// "Kahve 145 dün" → (-1, "Kahve 145") · "Lunch 12 yesterday" → (-1, "Lunch 12")
    private static func extractDayWord(from text: String) -> (offset: Int, cleaned: String)? {
        var tokens = text.split(whereSeparator: \.isWhitespace).map(String.init)
        let norms = tokens.map { $0.kurusNormalized.trimmingCharacters(in: .punctuationCharacters) }
        guard let index = norms.firstIndex(where: { Patterns.dayWords[$0] != nil }),
              let offset = Patterns.dayWords[norms[index]] else { return nil }
        tokens.remove(at: index)
        return (offset, tokens.joined(separator: " "))
    }

    // MARK: Başlık

    private static func freeTitle(from working: String) -> String {
        let stop: Set<String> = [
            "tl", "try", "lira", "nakit", "kart", "kartla", "kartiyla", "ile",
            "taksit", "taksitle", "taksitli", "kredi", "harcama",
            "cash", "card", "installment", "installments",
            "dollar", "dollars", "buck", "bucks", "cent", "cents",
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
    private static func extractTurkishMerchant(from raw: String) -> String? {
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

    /// "spent $18.40 at STARBUCKS" → "Starbucks" · "Card ending in 4532 at Whole Foods for $84.50" → "Whole Foods"
    private static func extractEnglishMerchant(from raw: String) -> String? {
        let tokens = raw.split(whereSeparator: \.isWhitespace).map(String.init)
        let norms = tokens.map { $0.kurusNormalized.trimmingCharacters(in: .punctuationCharacters) }
        guard let anchor = norms.firstIndex(where: { $0 == "at" || $0 == "@" }) ?? tokens.firstIndex(of: "@"),
              anchor + 1 < tokens.count else { return nil }

        let stop: Set<String> = [
            "for", "on", "with", "using", "via", "card", "ending", "was", "has", "have", "been",
            "is", "your", "from", "of", "and", "approved", "declined", "today", "yesterday",
        ]
        let legal: Set<String> = ["inc", "llc", "ltd", "co", "corp", "plc"]

        var picked: [String] = []
        var i = anchor + 1
        while i < tokens.count, picked.count < 4 {
            let token = tokens[i]
            let n = norms[i]
            if n.isEmpty || stop.contains(n) || n.contains(where: \.isNumber)
                || token.contains(where: { "$€£₺".contains($0) }) { break }
            if !legal.contains(n) { picked.append(token.trimmingCharacters(in: .punctuationCharacters)) }
            if let last = token.last, ".,;:!".contains(last) { break }
            i += 1
        }
        guard !picked.isEmpty else { return nil }

        let name = picked.joined(separator: " ")
        // Yalnızca tamamı büyük/küçük harfse düzelt ("STARBUCKS" → "Starbucks"); "Whole Foods" olduğu gibi kalır.
        let letters = name.filter(\.isLetter)
        let uniform = letters == letters.uppercased() || letters == letters.lowercased()
        return uniform
            ? name.lowercased(with: Locale(identifier: "en_US")).capitalized(with: Locale(identifier: "en_US"))
            : name
    }

    // MARK: Tutar yardımcıları

    private struct Candidate {
        let value: Decimal
        /// Etiketlenen para birimi (ISO); `nil` → etiketsiz
        let currency: String?
        /// Sayı + para birimi etiketi birlikte (başlıktan birlikte silinir)
        let range: Range<String.Index>
    }

    /// Her iki ondalık sistemi de okur:
    /// TR "1.250,75" → 1250.75 · "642,50" → 642.5 · "12.000" → 12000
    /// EN "1,250.75" → 1250.75 · "642.50" → 642.5 · "1,250" → 1250
    static func decimal(from token: String) -> Decimal? {
        var s = token
        let hasComma = s.contains(",")
        let hasDot = s.contains(".")

        if hasComma && hasDot {
            // Son görünen ayırıcı ondalıktır.
            let lastComma = s.lastIndex(of: ",")!
            let lastDot = s.lastIndex(of: ".")!
            if lastComma > lastDot {
                s = s.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
            } else {
                s = s.replacingOccurrences(of: ",", with: "")
            }
        } else if hasComma {
            // "1,250" / "12,000,000" → binlik (EN) · "642,50" → ondalık (TR)
            if s.range(of: #"^\d{1,3}(,\d{3})+$"#, options: .regularExpression) != nil {
                s = s.replacingOccurrences(of: ",", with: "")
            } else {
                s = s.replacingOccurrences(of: ",", with: ".")
            }
        } else if hasDot, s.range(of: #"^\d{1,3}(\.\d{3})+$"#, options: .regularExpression) != nil {
            // "12.000" → binlik (TR) · "642.50" → ondalık (EN)
            s = s.replacingOccurrences(of: ".", with: "")
        }
        return Decimal(string: s, locale: Locale(identifier: "en_US_POSIX"))
    }

    /// Sayının hemen önünde ya da ardında para birimi var mı? Varsa ISO kodu ve sayıyla birlikte aralığı.
    /// Sembol ($ € £ ₺) ve kod (TL, TRY, USD, EUR, GBP) iki yönde; "dolar/dollars/euro/pounds/lira"
    /// gibi kelimeler yalnızca sayıdan SONRA geçerlidir.
    private static func currencyTag(for range: Range<String.Index>, in text: String) -> (code: String, range: Range<String.Index>)? {
        let isGap: (Character) -> Bool = { $0 == " " || $0 == "\u{00A0}" }

        // Sonra
        var i = range.upperBound
        while i < text.endIndex, isGap(text[i]) { i = text.index(after: i) }
        if i < text.endIndex {
            if let code = Money.symbols[String(text[i])] {
                return (code, range.lowerBound..<text.index(after: i))
            }
            var j = i
            while j < text.endIndex, text[j].isLetter { j = text.index(after: j) }
            if j > i {
                let word = String(text[i..<j]).kurusNormalized
                if let code = Money.codes[word] ?? Money.trailingWords[word] {
                    return (code, range.lowerBound..<j)
                }
            }
        }

        // Önce
        var k = range.lowerBound
        while k > text.startIndex, isGap(text[text.index(before: k)]) { k = text.index(before: k) }
        if k > text.startIndex {
            let p = text.index(before: k)
            if let code = Money.symbols[String(text[p])] {
                return (code, p..<range.upperBound)
            }
            var start = k
            while start > text.startIndex, text[text.index(before: start)].isLetter { start = text.index(before: start) }
            if start < k, let code = Money.codes[String(text[start..<k]).kurusNormalized] {
                return (code, start..<range.upperBound)
            }
        }
        return nil
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
    /// "3t", "3 taksit", "6 taksitli", "3x", "3 installments", "in 4 installments"
    static let installment = #"(?:\bin\s+)?(?<![\d.,])(\d{1,2})\s*(?:taksit\w*|installments?|tk|t|x)(?![\p{L}\d])"#

    /// TR binlik "1.250,50" · EN binlik "1,250.50" · sade "642,50" / "642.50" / "36000"
    static let number = #"(?<![\p{L}\d.,:/])(\d{1,3}(?:\.\d{3})+(?:,\d{1,2})?|\d{1,3}(?:,\d{3})+(?:\.\d{1,2})?|\d+(?:[.,]\d{1,2})?)(?![\d:/]|[.,]\d)"#

    /// Normalize edilmiş metin üzerinde çalışır.
    static let cardLast4: [String] = [
        #"(\d{4})\s*ile\s*biten"#,
        #"ending\s*(?:in|with)?\s*:?\s*(\d{4})(?!\d)"#,
        #"(?:\*{2,}|•{2,}|x{3,})\s?(\d{4})(?!\d)"#,
        #"son\s*(?:4|dort)\s*hane\w*\s*:?\s*(\d{4})"#,
        #"(\d{4})\s*(?:no'?lu|numarali)\s*kart"#,
    ]

    /// İngilizce banka / Apple Pay bildirimlerini ele veren ifadeler
    static let englishNoticeWords = [
        "ending in", "card ending", "spent!", "purchase!", "transaction!", "charged!", "debit card", "credit card",
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

    /// "dün" / "yesterday" → -1 · "bugün" / "today" → 0
    static let dayWords: [String: Int] = ["dun": -1, "yesterday": -1, "bugun": 0, "today": 0]

    static let recurringWords = ["abonelik", "aylik", "uyelik", "premium", "subscription", "monthly", "membership"]

    /// Gelir kelimeleri ("!" → tam kelime). "Bonus" bir kart adı olduğu için bilinçli olarak yok.
    static let incomeWords = [
        "maas", "gelir", "iade", "prim!", "ikramiye", "kira geliri",
        "salary", "income", "refund", "paycheck", "payroll", "reimbursement",
    ]
    static let recurringIncomeWords = ["maas", "kira geliri", "salary", "paycheck", "payroll"]

    struct CategoryRule {
        let category: ExpenseCategory
        /// Doğal dilde yazılır; eşleştirmeden önce normalize edilir ("kulaklık" = "kulaklik").
        /// Sonu "!" ile biten kelime yalnızca tam kelime olarak eşleşir (bkz. SmartCategoryMatcher).
        let keywords: [String]
    }

    /// Sıra önemlidir; ilk eşleşen kural kazanır:
    /// "rent a car" → Ulaşım ("rent" Fatura'dan önce) · "telefon faturası" → Fatura (Teknoloji'den önce)
    /// "yarım ekmek" → Yemek (Birikim'den önce) · "uber eats" → Yemek ("uber" Ulaşım'dan önce)
    /// "metro market" → Market · "şarj istasyonu" → Ulaşım · "gas bill" → Fatura, "gas" → Ulaşım
    static let categoryRules: [CategoryRule] = [
        // 0. ARAÇ KİRALAMA (Fatura'daki "rent"/"kira"dan önce yakalanmalı)
        CategoryRule(category: .transport, keywords: [
            "araç kiralama", "rent a car", "car rental",
        ]),
        // 1. KONUT, KİRA, AİDAT, FATURA, VERGİ — HOUSING & BILLS
        CategoryRule(category: .bills, keywords: [
            "kira", "ev kirası", "aidat", "site aidatı", "apartman aidatı", "depozito", "emlak",
            "kombi", "petek", "tesisat", "tadilat", "çilingir", "nakliye",
            "fatura", "elektrik", "gediz", "enerjisa", "ck boğaziçi",
            "su faturası", "izsu", "iski", "aski", "doğalgaz", "igdaş", "izmirgaz", "başkentgaz",
            "internet", "fiber", "superonline", "turknet", "kablonet", "millenicom",
            "telekom", "hat faturası", "telefon faturası", "kontör",
            "vergi", "mtv", "emlak vergisi", "harç", "noter", "sigorta", "kasko", "dask",
            // English
            "rent", "mortgage", "hoa", "maintenance", "electricity", "electric bill", "water", "water bill",
            "gas bill", "utility", "utilities", "wifi", "phone bill", "verizon", "tmobile", "t mobile",
            "at&t", "att", "comcast", "xfinity", "insurance", "tax", "taxes",
        ]),
        // 2. KAHVE — COFFEE
        CategoryRule(category: .coffee, keywords: [
            "kahve", "espresso", "latte", "americano", "cappuccino", "mocha", "filtre kahve",
            "türk kahvesi", "çay", "espresso lab", "espressolab", "tchibo", "arabica",
            "nero!", "caffe nero", "caribou", "kafe", "cafe",
            "coffee", "dunkin", "peets", "tim hortons",
        ]),
        // 3. YEME & İÇME — FOOD
        CategoryRule(category: .food, keywords: [
            "yemek", "öğle yemeği", "akşam yemeği", "kahvaltı", "brunch", "restoran", "lokanta",
            "esnaf lokantası", "kebap", "kebab", "döner", "iskender", "lahmacun", "pide", "simit",
            "burger", "hamburger", "pizza", "sushi", "makarna", "salata", "çorba", "köfte",
            "kokoreç", "midye", "mantı", "tatlı", "baklava", "pastane", "kruvasan", "mado", "ekmek",
            "mcdonalds", "popeyes", "kfc", "dominos", "little caesars", "arbys", "happy moons",
            "bigchefs", "midpoint", "tavuk dünyası", "baydöner",
            "getiryemek", "getir yemek", "trendyol yemek", "migros yemek",
            // English
            "lunch", "dinner", "breakfast", "restaurant", "chipotle", "uber eats", "doordash", "grubhub",
            "deliveroo", "bakery", "sandwich", "tacos", "takeout",
        ]),
        // 4. MARKET & EV — GROCERIES
        CategoryRule(category: .market, keywords: [
            "market", "süpermarket", "macrocenter", "macro", "carrefour", "a101", "bim", "şok",
            "file!", "tarım kredi", "metro market", "onur market", "bakkal", "büfe", "manav",
            "pazar", "kasap", "şarküteri", "kuruyemiş", "fırın", "damacana", "erikli", "sırma",
            "su!", "getirbüyük", "istegelsin", "banabi", "yemeksepeti market", "trendyol hızlı market",
            "deterjan", "temizlik", "tuvalet kağıdı", "poşet",
            // English
            "grocery", "groceries", "supermarket", "whole foods", "trader joes", "trader joe", "walmart",
            "target", "costco", "aldi", "lidl", "tesco", "sainsburys", "sainsbury", "kroger", "safeway",
            "sam's club", "sams club",
        ]),
        // 5. SEYAHAT — TRAVEL
        CategoryRule(category: .travel, keywords: [
            "uçak", "otel", "pansiyon", "pegasus", "sunexpress", "ajet", "tatil", "airbnb",
            "booking", "vize", "pasaport", "obilet",
            "hotel", "vacation", "visa fee",
        ]),
        // 6. BİRİKİM & YATIRIM — SAVINGS (harcama toplamını şişirmez)
        CategoryRule(category: .savings, keywords: [
            "birikim", "yatırım", "altın", "gümüş", "gram!", "çeyrek", "yarım!", "tam!", "tam altın",
            "ata altın", "cumhuriyet", "ons!", "bilezik", "kuyumcu",
            "döviz", "dolar", "euro", "sterlin", "frank", "usd", "eur",
            "hisse", "bist", "borsa", "temettü", "fon!", "tefas", "mevduat", "kumbara",
            "bes!", "bireysel emeklilik", "kripto", "bitcoin", "btc", "eth", "midas",
            // English
            "gold", "silver", "stock", "stocks", "etf", "sp500", "s&p 500", "s&p", "crypto", "savings",
            "investment", "invest", "401k", "roth", "ira!", "vanguard", "fidelity", "robinhood",
        ]),
        // 7. ULAŞIM & ARAÇ — TRANSPORT
        CategoryRule(category: .transport, keywords: [
            "benzin", "mazot", "motorin", "dizel", "lpg", "otogaz", "yakıt", "akaryakıt",
            "şarj istasyonu", "zes", "trugo", "shell", "opet", "petrol", "petrol ofisi", "bp",
            "aytemiz", "go yakıt", "otopark", "ispark", "vale", "oto yıkama",
            "hgs", "ogs", "otoyol", "köprü", "avrasya", "osmangazi",
            "lastik", "jant", "periyodik bakım", "tüvtürk", "çekici",
            "taksi", "bitaksi", "uber", "martı", "binbin",
            "otobüs", "metro", "metrobüs", "tramvay", "izban", "marmaray", "vapur", "feribot",
            "ido", "budo", "istanbulkart", "izmirimkart", "ankarakart", "akbil", "dolmuş", "minibüs",
            "tren", "yht", "kamil koç",
            // English
            "lyft", "taxi", "cab", "gas", "fuel", "chevron", "exxon", "parking", "toll", "subway",
            "train", "flight", "airline", "delta", "united", "bus", "ferry",
        ]),
        // 8. ABONELİK & DİJİTAL SERVİSLER — SUBSCRIPTIONS
        CategoryRule(category: .subscription, keywords: [
            "abonelik", "üyelik", "apple music", "apple one", "app store", "google one",
            "prime!", "blutv", "exxen", "gain!", "mubi", "tod!", "beinsports", "tabii",
            "claude", "copilot", "cursor", "midjourney", "adobe", "canva", "notion",
            "subscription", "membership", "hbo", "hulu", "paramount", "peacock",
        ]),
        // 9. EĞLENCE — ENTERTAINMENT
        // "=" öneki: aksan korunarak eşleşir — "maç" (Eğlence) ile "Mac" (Teknoloji) karışmaz.
        CategoryRule(category: .entertainment, keywords: [
            "sinema", "bilet", "konser", "tiyatro", "oyun", "bowling", "müze",
            "=maç", "=maçı", "=maça", "=maç bileti", "festival",
            "movie", "cinema", "concert", "theater", "theatre", "ticket", "tickets", "museum",
            "game", "baseball", "basketball", "football", "soccer", "match", "stadium",
            "event", "party", "bar", "pub", "club",
        ]),
        // 10. SAĞLIK & ECZANE — HEALTH
        CategoryRule(category: .health, keywords: [
            "eczane", "ilaç", "vitamin", "doktor", "hastane", "muayene", "tahlil", "diş!", "dişçi",
            "diş hekimi", "dişhekimi", "gözlük", "optik", "lens", "fizyoterapi", "diyetisyen",
            "psikolog", "masaj", "spor salonu", "gym!", "macfit", "pilates", "veteriner",
            // English
            "pharmacy", "cvs", "walgreens", "boots", "medicine", "doctor", "dentist", "hospital",
            "clinic", "fitness", "vet", "therapy",
        ]),
        // 11. EĞİTİM — EDUCATION
        CategoryRule(category: .education, keywords: [
            "kurs", "kitap", "okul", "udemy", "eğitim", "kırtasiye", "ders",
            "course", "tuition", "books", "school",
        ]),
        // 12. TEKNOLOJİ & ELEKTRONİK — TECH
        CategoryRule(category: .technology, keywords: [
            "tablet", "ipad", "iphone", "telefon", "macbook", "laptop", "bilgisayar", "monitör",
            "ekran", "klavye", "mouse", "fare!", "kulaklık", "airpods", "şarj", "kablo", "adaptör",
            "powerbank", "batarya", "pil!", "akıllı saat", "apple watch", "yazıcı", "printer",
            "kartuş", "toner", "kamera", "tv!", "televizyon", "playstation", "konsol", "samsung",
            "xiaomi", "teknosa", "mediamarkt", "media markt", "vatan bilgisayar", "itopya", "gürgençler",
            // English
            "phone", "monitor", "headphones", "charger", "cable", "console", "steam", "apple", "best buy",
            "amazon", "keyboard", "camera", "computer", "pc", "desktop", "imac", "mac", "webcam",
            "microphone", "speaker", "router", "ssd", "hard drive", "software", "app",
        ]),
        // 13. ALIŞVERİŞ: GİYİM, KİŞİSEL BAKIM, EV, EVCİL HAYVAN — SHOPPING
        CategoryRule(category: .shopping, keywords: [
            "n11", "çiçeksepeti", "ikea", "koçtaş", "bauhaus", "decathlon",
            "zara", "bershka", "pull and bear", "pull&bear", "massimo dutti", "stradivarius", "mango",
            "h&m", "hm!", "mavi!", "koton", "lcw", "lc waikiki", "defacto", "boyner", "beymen", "vakko",
            "nike", "adidas", "puma", "skechers", "new balance", "camper",
            "ayakkabı", "bot!", "gömlek", "pantolon", "tişört", "ceket", "mont", "kazak", "elbise",
            "etek", "çanta", "kıyafet", "giyim", "terzi", "kuru temizleme",
            "gratis", "watsons", "rossmann", "sephora", "kozmetik", "makyaj", "fondöten", "ruj",
            "maskara", "parfüm", "krem", "şampuan",
            "berber", "kuaför", "tıraş", "cilt bakımı",
            "mama", "kedi maması", "köpek maması", "kedi kumu", "petshop",
            // English
            "clothing", "clothes", "shoes", "barber", "haircut", "pet!", "pet food", "petco", "uniqlo",
        ]),
    ]
}

// MARK: - Akıllı kategori eşleştirici

/// Token (kelime) tabanlı eşleştirici; `.contains()` alt-dize tuzaklarını önler.
///
/// • Metin ve anahtar kelime aynı biçimde normalize edilir, harf/rakam dışı karakterlerden bölünür.
/// • Tek kelime: tam eşleşme ya da (≥4 harfli köklerde) çekim eki için önek eşleşmesi.
///   "taksi" → "taksi", "taksiye" ✓ — "taksit" ✗ · "rent" ≠ "different" · "fon" ≠ "fondöten"
/// • Çok kelime ("ev kirası", "whole foods"): ardışık kelimeler; yalnızca son kelimeye ek izni.
/// • Sonu "!" ile biten anahtar kelime yalnızca tam kelime olarak eşleşir.
/// • "=" ile başlayan anahtar kelime aksan korunarak (normalize edilmeden) eşleşir: "=maç" "Mac"e uymaz.
enum SmartCategoryMatcher {

    /// Önek eşleşmesinin bilinçli olarak kapalı olduğu kökler: kök → yasaklı önekler.
    static let blockedPrefixes: [String: [String]] = [
        "taksi": ["taksit"],            // taksit ödemesi ≠ taksi
        "kira": ["kiral"],              // kiralama, kiralık ≠ ev kirası
        "tren": ["trend"],              // Trendyol ≠ tren
        "metro": ["metrop"],            // Metropol AVM ≠ metro
        "euro": ["europ"],              // Europcar ≠ döviz
        "mont": ["montaj"],             // montaj ≠ giyim
        "pazar": ["pazarl", "pazart"],  // pazarlama, pazartesi ≠ pazar alışverişi
        "vale": ["valen"],              // Valentino ≠ vale
        "frank": ["frankf"],            // Frankfurt ≠ İsviçre frangı
        "rent": ["rental"],             // car rental ayrı kuralda
        "train": ["trainer"],           // personal trainer ≠ tren
        "apple": ["applebee"],          // Applebee's ≠ Apple
        "water": ["waterm"],            // watermelon ≠ su faturası
        "stock": ["stocking"],          // stockings ≠ hisse
        "gold": ["golden"],             // Golden Krust ≠ altın
        "match": ["matcha"],            // matcha latte ≠ maç
    ]

    static func tokens(_ normalized: String) -> [String] {
        normalized.split { !($0.isLetter || $0.isNumber) }.map(String.init)
    }

    /// Ham metin için kolaylık sürümü.
    static func matches(_ text: String, keywords: [String]) -> Bool {
        matches(tokens: tokens(text.kurusNormalized), keywords: keywords)
    }

    static func matches(tokens words: [String], keywords: [String], accentTokens: [String] = []) -> Bool {
        keywords.contains { keyword in
            keyword.hasPrefix("=")
                ? matches(tokens: accentTokens, keyword: String(keyword.dropFirst()), normalize: false)
                : matches(tokens: words, keyword: keyword)
        }
    }

    static func matches(tokens words: [String], keyword: String, normalize: Bool = true) -> Bool {
        let exact = keyword.hasSuffix("!")
        let body = exact ? String(keyword.dropLast()) : keyword
        let parts = tokens(normalize ? body.kurusNormalized : body.lowercased())
        guard !parts.isEmpty, words.count >= parts.count else { return false }

        for start in 0...(words.count - parts.count) {
            var matched = true
            for (offset, part) in parts.enumerated() {
                let word = words[start + offset]
                let isLast = offset == parts.count - 1
                let ok = (isLast && !exact) ? wordMatches(word, stem: part) : word == part
                if !ok {
                    matched = false
                    break
                }
            }
            if matched { return true }
        }
        return false
    }

    /// Tam kelime ya da ≥4 harfli kök için önek (çekim eki) eşleşmesi.
    static func wordMatches(_ word: String, stem: String) -> Bool {
        if word == stem { return true }
        guard stem.count >= 4, word.hasPrefix(stem) else { return false }
        return !(blockedPrefixes[stem] ?? []).contains { word.hasPrefix($0) }
    }
}

// MARK: - Metin yardımcıları

extension String {
    /// Dil duyarlı normalize: küçük harf, aksansız ("Türk Telekom" → "turk telekom", "MIGROS" → "migros").
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
        // \b kelime sınırı: anahtar kelime ancak bir kelimenin BAŞINDA eşleşir.
        // prefixOnly=false ise kelimenin tamamı eşleşmelidir.
        let pattern = "\\b" + escaped + (prefixOnly ? "" : "\\b")
        return range(of: pattern, options: .regularExpression) != nil
    }

    /// İlk harfi cihaz diline göre büyütür (tr: "istanbul" → "İstanbul", en: "ikea" → "Ikea").
    /// İlk kelimede zaten büyük harf varsa ("iPad", "iPhone", "eBay") dokunmaz.
    var capitalizedFirstTR: String {
        guard let first, first.isLowercase else { return self }
        let firstWord = prefix { !$0.isWhitespace }
        if firstWord.contains(where: \.isUppercase) { return self }
        return String(first).uppercased(with: .current) + dropFirst()
    }
}
