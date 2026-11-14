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
        //    ya da dikte: "üç taksit", "on iki taksitle" → sayı + "taksit" başlıktan da temizlenir.
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
        let normTokens = SmartCategoryMatcher.tokens(norm)
        let incomeByWord = SmartCategoryMatcher.matches(tokens: normTokens, keywords: Patterns.incomeWords)
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
            result.isRecurring = SmartCategoryMatcher.matches(tokens: normTokens, keywords: Patterns.recurringIncomeWords)
        } else {
            // Kategori, taksit/kart/tutar ayıklanmış metinden çıkarılır: "3 taksit" içindeki
            // "taksi" önekinin Ulaşım'a düşmesi ("Yazıcı 4500 3 taksit" → Ulaşım) böylece engellenir.
            result.category = brand?.category ?? inferCategory(working.kurusNormalized) ?? .other
            result.isRecurring = (brand?.isSubscription ?? false)
                || SmartCategoryMatcher.matches(tokens: normTokens, keywords: Patterns.recurringWords)
        }

        let finalTitle = title.isEmpty ? result.category.title : title
        result.title = String(finalTitle.prefix(42))
        return result
    }

    // MARK: Kategori çıkarımı

    private static func inferCategory(_ norm: String) -> ExpenseCategory? {
        let tokens = SmartCategoryMatcher.tokens(norm)
        for rule in Patterns.categoryRules where SmartCategoryMatcher.matches(tokens: tokens, keywords: rule.keywords) {
            return rule.category
        }
        return nil
    }

    // MARK: Dikte ile taksit

    private static let spokenUnits: [String: Int] = [
        "bir": 1, "iki": 2, "uc": 3, "dort": 4, "bes": 5, "alti": 6, "yedi": 7, "sekiz": 8, "dokuz": 9,
    ]
    private static let spokenTens: [String: Int] = ["on": 10, "yirmi": 20, "otuz": 30, "kirk": 40]

    /// "Telefon 36000 üç taksit" → (3, "Telefon 36000"). "on iki taksitle" → 12, "oniki taksit" → 12.
    /// Sayı kelimeleri ve "taksit…" kelimesi metinden çıkarılır; böylece başlığa sızmaz.
    private static func extractSpokenInstallment(from text: String) -> (count: Int, cleaned: String)? {
        var tokens = text.split(whereSeparator: \.isWhitespace).map(String.init)
        let norms = tokens.map { $0.kurusNormalized.trimmingCharacters(in: .punctuationCharacters) }
        guard let anchor = norms.firstIndex(where: { $0.hasPrefix("taksit") }), anchor > 0 else { return nil }

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
        } else if let ten = spokenTens[previous] {
            value = ten
            used = 1
        } else if let fused = fusedSpokenNumber(previous) {
            value = fused
            used = 1
        }

        guard used > 0, (2...48).contains(value) else { return nil }
        tokens.removeSubrange((anchor - used)...anchor)
        return (value, tokens.joined(separator: " "))
    }

    /// Bitişik dikte: "onaltı" → 16, "yirmidört" → 24
    private static func fusedSpokenNumber(_ word: String) -> Int? {
        for (tenWord, tenValue) in spokenTens where word.hasPrefix(tenWord) {
            if let unit = spokenUnits[String(word.dropFirst(tenWord.count))] { return tenValue + unit }
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
        /// Doğal Türkçe yazılır; eşleştirmeden önce normalize edilir ("kulaklık" = "kulaklik").
        /// Sonu "!" ile biten kelime yalnızca tam kelime olarak eşleşir (bkz. SmartCategoryMatcher).
        let keywords: [String]
    }

    /// Sıra önemlidir; ilk eşleşen kural kazanır:
    /// "telefon faturası" → Fatura (Teknoloji'den önce) · "yarım ekmek" → Yemek (Birikim'den önce)
    /// "tam pansiyon" → Seyahat · "metro market" → Market (Ulaşım'dan önce) · "şarj istasyonu" → Ulaşım
    static let categoryRules: [CategoryRule] = [
        // 1. KONUT, KİRA, AİDAT, FATURA, VERGİ
        CategoryRule(category: .bills, keywords: [
            "kira", "ev kirası", "aidat", "site aidatı", "apartman aidatı", "depozito", "emlak",
            "kombi", "petek", "tesisat", "tadilat", "çilingir", "nakliye",
            "fatura", "elektrik", "gediz", "enerjisa", "ck boğaziçi",
            "su faturası", "izsu", "iski", "aski", "doğalgaz", "igdaş", "izmirgaz", "başkentgaz",
            "internet", "fiber", "superonline", "turknet", "kablonet", "millenicom",
            "telekom", "hat faturası", "telefon faturası", "kontör",
            "vergi", "mtv", "emlak vergisi", "harç", "noter", "sigorta", "kasko", "dask",
        ]),
        // 2. KAHVE
        CategoryRule(category: .coffee, keywords: [
            "kahve", "espresso", "latte", "americano", "cappuccino", "mocha", "filtre kahve",
            "türk kahvesi", "çay", "espresso lab", "espressolab", "tchibo", "arabica",
            "nero!", "caffe nero", "caribou", "kafe", "cafe",
        ]),
        // 3. YEME & İÇME
        CategoryRule(category: .food, keywords: [
            "yemek", "öğle yemeği", "akşam yemeği", "kahvaltı", "brunch", "restoran", "lokanta",
            "esnaf lokantası", "kebap", "kebab", "döner", "iskender", "lahmacun", "pide", "simit",
            "burger", "hamburger", "pizza", "sushi", "makarna", "salata", "çorba", "köfte",
            "kokoreç", "midye", "mantı", "tatlı", "baklava", "pastane", "kruvasan", "mado", "ekmek",
            "mcdonalds", "popeyes", "kfc", "dominos", "little caesars", "arbys", "happy moons",
            "bigchefs", "midpoint", "tavuk dünyası", "baydöner",
            "getiryemek", "getir yemek", "trendyol yemek", "migros yemek",
        ]),
        // 4. MARKET & EV
        CategoryRule(category: .market, keywords: [
            "market", "süpermarket", "macrocenter", "macro", "carrefour", "a101", "bim", "şok",
            "file!", "tarım kredi", "metro market", "onur market", "bakkal", "büfe", "manav",
            "pazar", "kasap", "şarküteri", "kuruyemiş", "fırın", "damacana", "erikli", "sırma",
            "su!", "getirbüyük", "istegelsin", "banabi", "yemeksepeti market", "trendyol hızlı market",
            "deterjan", "temizlik", "tuvalet kağıdı", "poşet",
        ]),
        // 5. SEYAHAT
        CategoryRule(category: .travel, keywords: [
            "uçak", "otel", "pansiyon", "pegasus", "sunexpress", "ajet", "tatil", "airbnb",
            "booking", "vize", "pasaport", "obilet",
        ]),
        // 6. BİRİKİM & YATIRIM (harcama toplamını şişirmez)
        CategoryRule(category: .savings, keywords: [
            "birikim", "yatırım", "altın", "gümüş", "gram!", "çeyrek", "yarım!", "tam!", "tam altın",
            "ata altın", "cumhuriyet", "ons!", "bilezik", "kuyumcu",
            "döviz", "dolar", "euro", "sterlin", "frank", "usd", "eur",
            "hisse", "bist", "borsa", "temettü", "fon!", "tefas", "mevduat", "kumbara",
            "bes!", "bireysel emeklilik", "kripto", "bitcoin", "btc", "eth", "midas",
        ]),
        // 7. ULAŞIM & ARAÇ
        CategoryRule(category: .transport, keywords: [
            "benzin", "mazot", "motorin", "dizel", "lpg", "otogaz", "yakıt", "akaryakıt",
            "şarj istasyonu", "zes", "trugo", "shell", "opet", "petrol", "petrol ofisi", "bp",
            "aytemiz", "go yakıt", "otopark", "ispark", "vale", "oto yıkama",
            "hgs", "ogs", "otoyol", "köprü", "avrasya", "osmangazi",
            "lastik", "jant", "periyodik bakım", "tüvtürk", "çekici", "araç kiralama", "rent a car",
            "taksi", "bitaksi", "uber", "martı", "binbin",
            "otobüs", "metro", "metrobüs", "tramvay", "izban", "marmaray", "vapur", "feribot",
            "ido", "budo", "istanbulkart", "izmirimkart", "ankarakart", "akbil", "dolmuş", "minibüs",
            "tren", "yht", "kamil koç",
        ]),
        // 8. ABONELİK & DİJİTAL SERVİSLER
        CategoryRule(category: .subscription, keywords: [
            "abonelik", "üyelik", "apple music", "apple one", "app store", "google one",
            "prime!", "blutv", "exxen", "gain!", "mubi", "tod!", "beinsports", "tabii",
            "claude", "copilot", "cursor", "midjourney", "adobe", "canva", "notion",
        ]),
        // 9. EĞLENCE
        CategoryRule(category: .entertainment, keywords: [
            "sinema", "bilet", "konser", "tiyatro", "steam", "oyun", "bowling", "müze",
            "maç bileti", "festival",
        ]),
        // 10. SAĞLIK & ECZANE
        CategoryRule(category: .health, keywords: [
            "eczane", "ilaç", "vitamin", "doktor", "hastane", "muayene", "tahlil", "diş!", "dişçi",
            "diş hekimi", "dişhekimi", "gözlük", "optik", "lens", "fizyoterapi", "diyetisyen",
            "psikolog", "masaj", "spor salonu", "gym!", "macfit", "pilates", "veteriner",
        ]),
        // 11. EĞİTİM
        CategoryRule(category: .education, keywords: [
            "kurs", "kitap", "okul", "udemy", "eğitim", "kırtasiye", "ders",
        ]),
        // 12. TEKNOLOJİ & ELEKTRONİK
        CategoryRule(category: .technology, keywords: [
            "tablet", "ipad", "iphone", "telefon", "macbook", "laptop", "bilgisayar", "monitör",
            "ekran", "klavye", "mouse", "fare!", "kulaklık", "airpods", "şarj", "kablo", "adaptör",
            "powerbank", "batarya", "pil!", "akıllı saat", "apple watch", "yazıcı", "printer",
            "kartuş", "toner", "kamera", "tv!", "televizyon", "playstation", "konsol", "samsung",
            "xiaomi", "teknosa", "mediamarkt", "media markt", "vatan bilgisayar", "itopya", "gürgençler",
        ]),
        // 13. ALIŞVERİŞ: GİYİM, KİŞİSEL BAKIM, EV, EVCİL HAYVAN
        CategoryRule(category: .shopping, keywords: [
            "amazon", "n11", "çiçeksepeti", "ikea", "koçtaş", "bauhaus", "decathlon",
            "zara", "bershka", "pull and bear", "pull&bear", "massimo dutti", "stradivarius", "mango",
            "h&m", "hm!", "mavi!", "koton", "lcw", "lc waikiki", "defacto", "boyner", "beymen", "vakko",
            "nike", "adidas", "puma", "skechers", "new balance", "camper",
            "ayakkabı", "bot!", "gömlek", "pantolon", "tişört", "ceket", "mont", "kazak", "elbise",
            "etek", "çanta", "kıyafet", "giyim", "terzi", "kuru temizleme",
            "gratis", "watsons", "rossmann", "sephora", "kozmetik", "makyaj", "fondöten", "ruj",
            "maskara", "parfüm", "krem", "şampuan",
            "berber", "kuaför", "tıraş", "cilt bakımı",
            "mama", "kedi maması", "köpek maması", "kedi kumu", "petshop",
        ]),
    ]
}

// MARK: - Akıllı kategori eşleştirici

/// Token (kelime) tabanlı eşleştirici; `.contains()` alt-dize tuzaklarını önler.
///
/// • Metin ve anahtar kelime aynı biçimde normalize edilir, harf/rakam dışı karakterlerden bölünür.
/// • Tek kelime: tam eşleşme ya da (≥4 harfli köklerde) Türkçe çekim eki için önek eşleşmesi.
///   "taksi" → "taksi", "taksiye" ✓ — "taksit" ✗ · "tablet" ≠ "et" · "fon" ≠ "fondöten"
/// • Çok kelime ("ev kirası"): ardışık kelimeler; yalnızca son kelimeye çekim eki izni.
/// • Sonu "!" ile biten anahtar kelime yalnızca tam kelime olarak eşleşir.
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
    ]

    static func tokens(_ normalized: String) -> [String] {
        normalized.split { !($0.isLetter || $0.isNumber) }.map(String.init)
    }

    /// Ham metin için kolaylık sürümü.
    static func matches(_ text: String, keywords: [String]) -> Bool {
        matches(tokens: tokens(text.kurusNormalized), keywords: keywords)
    }

    static func matches(tokens words: [String], keywords: [String]) -> Bool {
        keywords.contains { matches(tokens: words, keyword: $0) }
    }

    static func matches(tokens words: [String], keyword: String) -> Bool {
        let exact = keyword.hasSuffix("!")
        let parts = tokens((exact ? String(keyword.dropLast()) : keyword).kurusNormalized)
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
