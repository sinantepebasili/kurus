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
    /// Sıra önemlidir: daha özgül marka önce ("YouTube Music" → "YouTube", "Uber Eats" → "Uber",
    /// "Amazon Prime" → "Amazon"). Yaygın kelimeye denk gelen adlar (Max, Lime, Bird, Total, Mobil,
    /// Calm, Boots) yalnızca belirgin ifadelerle eşleşir ("hbo max", "lime scooter"…).
    /// Kimlikler (id) kalıcıdır: kayıtlı harcamalar markayı kimliğiyle tutar.
    static let all: [Brand] = [
        // Dijital abonelikler · Müzik, ses ve podcast
        b("spotify", "Spotify", ["spotify"], "1DB954", .symbol("waveform"), .subscription, sub: true, dark: true),
        b("deezer", "Deezer", ["deezer"], "A238FF", .monogram("D"), .subscription, sub: true),
        b("applemusic", "Apple Music", ["apple music"], "FA243C", .symbol("music.note"), .subscription, sub: true),
        b("youtubemusic", "YouTube Music", ["youtube music", "yt music"], "FF0033", .symbol("music.note"), .subscription, sub: true),
        b("tidal", "Tidal", ["tidal"], "2B2B2E", .monogram("T"), .subscription, sub: true),
        b("soundcloud", "SoundCloud", ["soundcloud"], "FF5500", .symbol("cloud.fill"), .subscription, sub: true),
        b("audible", "Audible", ["audible"], "F8991C", .symbol("headphones"), .subscription, sub: true, dark: true),
        b("storytel", "Storytel", ["storytel"], "FF501A", .monogram("S"), .subscription, sub: true),
        b("podimo", "Podimo", ["podimo"], "6B4EFF", .monogram("P"), .subscription, sub: true),
        // Video, yayın ve oyun
        b("netflix", "Netflix", ["netflix"], "E50914", .monogram("N"), .subscription, sub: true),
        b("youtube", "YouTube Premium", ["youtube", "yt premium"], "FF0033", .symbol("play.fill"), .subscription, sub: true),
        b("prime", "Prime Video", ["prime video", "amazon prime"], "00A8E1", .monogram("P"), .subscription, sub: true),
        b("disney", "Disney+", ["disney"], "113CCF", .monogram("D+"), .subscription, sub: true),
        b("hulu", "Hulu", ["hulu"], "1CE783", .monogram("h"), .subscription, sub: true, dark: true),
        b("max", "Max", ["hbo max", "hbo"], "002BE7", .monogram("max"), .subscription, sub: true),
        b("paramount", "Paramount+", ["paramount"], "0064FF", .monogram("P+"), .subscription, sub: true),
        b("peacock", "Peacock", ["peacock"], "2B2B2E", .monogram("P"), .subscription, sub: true),
        b("appletv", "Apple TV+", ["apple tv"], "2C2C30", .symbol("tv.fill"), .subscription, sub: true),
        b("crunchyroll", "Crunchyroll", ["crunchyroll"], "F47521", .monogram("C"), .subscription, sub: true),
        b("twitch", "Twitch", ["twitch"], "9146FF", .monogram("T"), .subscription, sub: true),
        b("mubi", "MUBI", ["mubi"], "0A1E5C", .monogram("M"), .subscription, sub: true),
        b("exxen", "Exxen", ["exxen"], "FFCC00", .monogram("E"), .subscription, sub: true, dark: true),
        b("blutv", "BluTV", ["blutv", "blu tv"], "1F7CFF", .monogram("B"), .subscription, sub: true),
        b("tod", "TOD", ["tod"], "5B2C83", .monogram("TOD"), .subscription, sub: true),
        b("gain", "Gain", ["gain"], "0FB89B", .monogram("G"), .subscription, sub: true),
        b("gamepass", "Xbox Game Pass", ["xbox game pass", "game pass"], "107C10", .monogram("X"), .subscription, sub: true),
        b("psplus", "PlayStation Plus", ["playstation plus", "ps plus"], "003791", .monogram("PS"), .subscription, sub: true),
        b("nintendo", "Nintendo Switch Online", ["nintendo switch online", "switch online", "nintendo online"], "E60012", .monogram("N"), .subscription, sub: true),
        b("steam", "Steam", ["steam"], "1B2838", .symbol("gamecontroller.fill"), .entertainment),
        // Üretkenlik, bulut ve yapay zekâ
        b("appleone", "Apple One", ["apple one"], "2C2C30", .monogram("1"), .subscription, sub: true),
        b("icloud", "iCloud+", ["icloud"], "3D8BFF", .symbol("icloud.fill"), .subscription, sub: true),
        b("googleone", "Google One", ["google one"], "4285F4", .monogram("G1"), .subscription, sub: true),
        b("dropbox", "Dropbox", ["dropbox"], "0061FF", .symbol("shippingbox.fill"), .subscription, sub: true),
        b("chatgpt", "ChatGPT Plus", ["chatgpt", "openai"], "10A37F", .symbol("sparkle"), .subscription, sub: true),
        b("claude", "Claude", ["claude"], "D97757", .monogram("C"), .subscription, sub: true),
        b("cursor", "Cursor", ["cursor"], "2B2B2E", .monogram("C"), .subscription, sub: true),
        b("perplexity", "Perplexity", ["perplexity"], "20808D", .monogram("P"), .subscription, sub: true),
        b("midjourney", "Midjourney", ["midjourney"], "2B2B2E", .monogram("M"), .subscription, sub: true),
        b("github", "GitHub", ["github"], "24292F", .monogram("GH"), .subscription, sub: true),
        b("adobe", "Adobe", ["adobe", "creative cloud"], "FA0F00", .monogram("A"), .subscription, sub: true),
        b("canva", "Canva", ["canva"], "00C4CC", .monogram("C"), .subscription, sub: true, dark: true),
        b("microsoft365", "Microsoft 365", ["microsoft 365", "office 365", "m365"], "0078D4", .monogram("365"), .subscription, sub: true),
        b("notion", "Notion", ["notion"], "2B2B2E", .monogram("N"), .subscription, sub: true),
        b("obsidian", "Obsidian", ["obsidian"], "7C3AED", .monogram("O"), .subscription, sub: true),
        b("todoist", "Todoist", ["todoist"], "E44332", .symbol("checkmark.circle.fill"), .subscription, sub: true),
        b("onepassword", "1Password", ["1password"], "0572EC", .monogram("1P"), .subscription, sub: true),
        b("nordvpn", "NordVPN", ["nordvpn", "nord vpn"], "4687FF", .monogram("N"), .subscription, sub: true),
        b("expressvpn", "ExpressVPN", ["expressvpn", "express vpn"], "DA3940", .monogram("E"), .subscription, sub: true),
        // Spor, sağlık ve yaşam
        b("strava", "Strava", ["strava"], "FC4C02", .monogram("S"), .health, sub: true),
        b("whoop", "Whoop", ["whoop"], "2B2B2E", .monogram("W"), .health, sub: true),
        b("oura", "Oura", ["oura"], "2B2B2E", .monogram("O"), .health, sub: true),
        b("myfitnesspal", "MyFitnessPal", ["myfitnesspal", "my fitness pal"], "0066EE", .monogram("M"), .health, sub: true),
        b("yazio", "Yazio", ["yazio"], "0D9488", .monogram("Y"), .health, sub: true),
        b("headspace", "Headspace", ["headspace"], "FF7A00", .monogram("H"), .health, sub: true),
        b("calm", "Calm", ["calm app", "calm premium"], "4A90E2", .monogram("C"), .health, sub: true),
        b("duolingo", "Duolingo", ["duolingo"], "58CC02", .monogram("D"), .education, sub: true, dark: true),
        b("babbel", "Babbel", ["babbel"], "FF6A00", .monogram("B"), .education, sub: true),
        b("kindle", "Kindle Unlimited", ["kindle unlimited"], "FF9900", .symbol("book.fill"), .education, sub: true, dark: true),
        b("patreon", "Patreon", ["patreon"], "FF424D", .monogram("P"), .subscription, sub: true),
        b("substack", "Substack", ["substack"], "FF6719", .monogram("S"), .subscription, sub: true),
        b("tinder", "Tinder", ["tinder"], "FE3C72", .symbol("flame.fill"), .subscription, sub: true),
        b("bumble", "Bumble", ["bumble"], "FFC629", .monogram("B"), .subscription, sub: true, dark: true),
        b("planetfitness", "Planet Fitness", ["planet fitness"], "5C2D91", .monogram("PF"), .health, sub: true),
        b("puregym", "PureGym", ["puregym", "pure gym"], "00A7E1", .monogram("PG"), .health, sub: true),
        b("basicfit", "Basic-Fit", ["basic-fit", "basic fit", "basicfit"], "F27A1A", .monogram("BF"), .health, sub: true),
        b("equinox", "Equinox", ["equinox"], "2B2B2E", .monogram("E"), .health, sub: true),
        b("lafitness", "LA Fitness", ["la fitness"], "00539B", .monogram("LA"), .health, sub: true),
        b("macfit", "MACFit", ["macfit"], "E30613", .monogram("MF"), .health, sub: true),
        // Operatörler (Türkiye)
        b("turkcell", "Turkcell", ["turkcell"], "FFC20E", .monogram("T"), .bills, sub: true, dark: true),
        b("vodafone", "Vodafone", ["vodafone"], "E60000", .symbol("quote.closing"), .bills, sub: true),
        b("turktelekom", "Türk Telekom", ["turk telekom", "turktelekom", "ttnet"], "1D4F91", .monogram("tt"), .bills, sub: true),
        // Kahve ve yeme-içme
        b("starbucks", "Starbucks", ["starbucks"], "00704A", .symbol("cup.and.saucer.fill"), .coffee),
        b("costa", "Costa Coffee", ["costa coffee", "costa"], "6D1F2A", .monogram("C"), .coffee),
        b("dunkin", "Dunkin'", ["dunkin", "dunkin'", "dunkin donuts"], "FF671F", .monogram("D"), .coffee),
        b("pret", "Pret A Manger", ["pret a manger", "pret"], "862633", .monogram("P"), .coffee),
        b("timhortons", "Tim Hortons", ["tim hortons"], "C8102E", .monogram("TH"), .coffee),
        b("nero", "Caffè Nero", ["caffe nero", "nero"], "1B3C6B", .monogram("N"), .coffee),
        b("kahvedunyasi", "Kahve Dünyası", ["kahve dunyasi"], "5B2C1E", .monogram("KD"), .coffee),
        b("espressolab", "EspressoLab", ["espressolab", "espresso lab"], "2B2B2E", .monogram("EL"), .coffee),
        b("mcdonalds", "McDonald's", ["mcdonald's", "mcdonalds", "mc donalds", "mcdonald"], "FFC72C", .monogram("M"), .food, dark: true),
        b("burgerking", "Burger King", ["burger king"], "D62300", .monogram("BK"), .food),
        b("kfc", "KFC", ["kfc"], "E4002B", .monogram("KFC"), .food),
        b("subway", "Subway", ["subway"], "008C15", .monogram("S"), .food),
        b("chipotle", "Chipotle", ["chipotle"], "441500", .monogram("C"), .food),
        b("tacobell", "Taco Bell", ["taco bell"], "702082", .monogram("TB"), .food),
        b("chickfila", "Chick-fil-A", ["chick-fil-a", "chick fil a", "chickfila"], "E51636", .monogram("C"), .food),
        b("wendys", "Wendy's", ["wendy's", "wendys"], "E2203D", .monogram("W"), .food),
        b("shakeshack", "Shake Shack", ["shake shack"], "2B2B2E", .monogram("SS"), .food),
        b("dominos", "Domino's", ["domino's", "dominos"], "006491", .monogram("D"), .food),
        b("pizzahut", "Pizza Hut", ["pizza hut"], "EE3124", .monogram("PH"), .food),
        b("yemeksepeti", "Yemeksepeti", ["yemeksepeti", "yemek sepeti"], "FA0050", .symbol("fork.knife"), .food),
        b("ubereats", "Uber Eats", ["uber eats", "ubereats"], "06C167", .monogram("UE"), .food),
        b("doordash", "DoorDash", ["doordash", "door dash"], "FF3008", .monogram("DD"), .food),
        b("grubhub", "Grubhub", ["grubhub"], "F63440", .monogram("G"), .food),
        b("deliveroo", "Deliveroo", ["deliveroo"], "00CCBC", .monogram("D"), .food, dark: true),
        b("justeat", "Just Eat", ["just eat", "justeat"], "FF8000", .monogram("JE"), .food),
        b("wolt", "Wolt", ["wolt"], "009DE0", .monogram("W"), .food),
        b("glovo", "Glovo", ["glovo"], "FFC244", .monogram("G"), .food, dark: true),
        b("instacart", "Instacart", ["instacart"], "43B02A", .monogram("I"), .market),
        b("getir", "Getir", ["getir"], "5D3EBC", .monogram("g"), .market),
        // Market, perakende ve e-ticaret
        b("migros", "Migros", ["migros"], "F28C00", .monogram("M"), .market),
        b("bim", "BİM", ["bim"], "E30613", .monogram("B"), .market),
        b("a101", "A101", ["a101"], "00A0E3", .monogram("A"), .market),
        b("sok", "Şok", ["sok market", "sok"], "FFD100", .monogram("Ş"), .market, dark: true),
        b("trendyol", "Trendyol", ["trendyol"], "F27A1A", .monogram("t"), .shopping),
        b("hepsiburada", "Hepsiburada", ["hepsiburada"], "FF6000", .monogram("h"), .shopping),
        b("amazon", "Amazon", ["amazon"], "FF9900", .monogram("a"), .shopping, dark: true),
        b("walmart", "Walmart", ["walmart"], "0071CE", .monogram("W"), .market),
        b("target", "Target", ["target"], "CC0000", .symbol("target"), .market),
        b("costco", "Costco", ["costco"], "E31837", .monogram("C"), .market),
        b("samsclub", "Sam's Club", ["sam's club", "sams club"], "0067A0", .monogram("S"), .market),
        b("wholefoods", "Whole Foods", ["whole foods"], "00674B", .monogram("WF"), .market),
        b("traderjoes", "Trader Joe's", ["trader joe's", "trader joes", "trader joe"], "C8102E", .monogram("TJ"), .market),
        b("kroger", "Kroger", ["kroger"], "0F4C81", .monogram("K"), .market),
        b("publix", "Publix", ["publix"], "3F8F29", .monogram("P"), .market),
        b("heb", "H-E-B", ["h-e-b", "heb"], "E31837", .monogram("H"), .market),
        b("walgreens", "Walgreens", ["walgreens"], "E31837", .monogram("W"), .health),
        b("cvs", "CVS", ["cvs"], "CC0000", .monogram("CVS"), .health),
        b("aldi", "Aldi", ["aldi"], "00005F", .monogram("A"), .market),
        b("lidl", "Lidl", ["lidl"], "0050AA", .monogram("L"), .market),
        b("tesco", "Tesco", ["tesco"], "00539F", .monogram("T"), .market),
        b("sainsburys", "Sainsbury's", ["sainsbury's", "sainsburys", "sainsbury"], "F06C00", .monogram("S"), .market),
        b("asda", "Asda", ["asda"], "78BE20", .monogram("A"), .market, dark: true),
        b("waitrose", "Waitrose", ["waitrose"], "5C8A2B", .monogram("W"), .market),
        b("marksandspencer", "M&S", ["marks & spencer", "marks and spencer", "m&s"], "2B2B2E", .monogram("M&S"), .market),
        b("boots", "Boots", ["boots pharmacy", "boots chemist"], "05054B", .monogram("B"), .health),
        b("carrefour", "Carrefour", ["carrefour", "carrefoursa"], "004E9F", .monogram("C"), .market),
        b("leclerc", "E.Leclerc", ["leclerc"], "0066B3", .monogram("L"), .market),
        b("auchan", "Auchan", ["auchan"], "E2001A", .monogram("A"), .market),
        b("rewe", "REWE", ["rewe"], "CC071E", .monogram("R"), .market),
        b("edeka", "Edeka", ["edeka"], "FFD400", .monogram("E"), .market, dark: true),
        b("kaufland", "Kaufland", ["kaufland"], "E10915", .monogram("K"), .market),
        b("dm", "dm", ["dm", "dm drogerie"], "0A2C6E", .monogram("dm"), .shopping),
        b("rossmann", "Rossmann", ["rossmann"], "C3002F", .monogram("R"), .shopping),
        b("mercadona", "Mercadona", ["mercadona"], "00843D", .monogram("M"), .market),
        b("albertheijn", "Albert Heijn", ["albert heijn"], "00A0E2", .monogram("AH"), .market),
        b("ikea", "IKEA", ["ikea"], "0058A3", .monogram("IK"), .shopping),
        b("homedepot", "The Home Depot", ["home depot"], "F96302", .monogram("HD"), .shopping),
        b("lowes", "Lowe's", ["lowe's", "lowes"], "004990", .monogram("L"), .shopping),
        b("bestbuy", "Best Buy", ["best buy"], "0046BE", .monogram("BB"), .technology),
        b("mediamarkt", "MediaMarkt", ["mediamarkt", "media markt"], "DF0000", .monogram("MM"), .technology),
        b("decathlon", "Decathlon", ["decathlon"], "0082C3", .monogram("D"), .shopping),
        b("zara", "Zara", ["zara"], "2B2B2E", .monogram("Z"), .shopping),
        b("hm", "H&M", ["h&m", "hm"], "E50010", .monogram("H&M"), .shopping),
        b("uniqlo", "Uniqlo", ["uniqlo"], "FF0000", .monogram("U"), .shopping),
        b("nike", "Nike", ["nike"], "2B2B2E", .monogram("N"), .shopping),
        b("adidas", "Adidas", ["adidas"], "2B2B2E", .monogram("A"), .shopping),
        b("lululemon", "Lululemon", ["lululemon"], "D22030", .monogram("L"), .shopping),
        b("sephora", "Sephora", ["sephora"], "2B2B2E", .monogram("S"), .shopping),
        b("ulta", "Ulta Beauty", ["ulta"], "F26B3A", .monogram("U"), .shopping),
        // Ulaşım ve akaryakıt
        b("uber", "Uber", ["uber"], "2B2B2E", .monogram("U"), .transport),
        b("lyft", "Lyft", ["lyft"], "FF00BF", .monogram("L"), .transport),
        b("bolt", "Bolt", ["bolt"], "34D186", .monogram("B"), .transport, dark: true),
        b("freenow", "FreeNow", ["freenow", "free now"], "D90034", .monogram("FN"), .transport),
        b("marti", "Martı", ["marti"], "3BD16F", .monogram("M"), .transport, dark: true),
        b("lime", "Lime", ["lime scooter", "lime ride"], "0BDA51", .monogram("L"), .transport, dark: true),
        b("bird", "Bird", ["bird scooter", "bird ride"], "2B2B2E", .monogram("B"), .transport),
        b("thy", "Türk Hava Yolları", ["thy", "turk hava yollari", "turkish airlines"], "C8102E", .symbol("airplane"), .travel),
        b("shell", "Shell", ["shell"], "FFD500", .monogram("S"), .transport, dark: true),
        b("bp", "BP", ["bp"], "007F00", .monogram("bp"), .transport),
        b("chevron", "Chevron", ["chevron"], "0054A4", .monogram("C"), .transport),
        b("exxon", "Exxon", ["exxon", "exxonmobil"], "ED1B2D", .monogram("E"), .transport),
        b("mobil", "Mobil", ["mobil gas", "mobil station", "mobil benzin"], "0F4DA2", .monogram("M"), .transport),
        b("total", "TotalEnergies", ["totalenergies", "total energies"], "ED0000", .monogram("T"), .transport),
        b("opet", "Opet", ["opet"], "005CA9", .monogram("O"), .transport),
        b("petrolofisi", "Petrol Ofisi", ["petrol ofisi"], "E30613", .monogram("PO"), .transport),
    ]

    private static func b(
        _ id: String, _ name: String, _ keywords: [String], _ hex: String,
        _ glyph: Brand.Glyph, _ category: ExpenseCategory, sub: Bool = false, dark: Bool = false
    ) -> Brand {
        Brand(id: id, name: name, keywords: keywords, hex: hex, glyph: glyph,
              category: category, isSubscription: sub, darkGlyph: dark)
    }

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
