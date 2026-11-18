# Kuruş / Cent

Sunucusuz, hesapsız, saf SwiftUI harcama takip uygulaması. iOS 17.0+ · iPhone · Swift 5 dil modu · 3. parti bağımlılık yok.

## Dil, marka ve para birimi

- **Marka:** Cihaz dili Türkçe ise uygulamanın adı **Kuruş**, diğer tüm dillerde **Cent**. Bu ad sol üst başlıkta, otomasyon rehberinde, PDF/CSV'de ve widget'larda kullanılıyor (`AppLanguage.brandName`). Ana ekrandaki ad `InfoPlist.xcstrings` ile yerelleştirildi: `en` → Cent, `tr` → Kuruş.
- **Arayüz metinleri:** `Shared/Localization.swift` içindeki `L("Türkçe", "English")` ile seçiliyor; Türkçe cihazda ilk, diğer dillerde ikinci metin gösteriliyor.
- **Siri ve widget metinleri:** Siri/Kestirmeler ve widget galerisi gibi sistemin okuduğu sabit metinler `Shared/Localizable.xcstrings` ve `App/AppShortcuts.xcstrings` kataloglarında (kaynak dil `en`, çeviri `tr`). Projenin geliştirme dili `en`; Türkçe ve İngilizce dışındaki dillerde arayüz İngilizce açılır.
- **Para birimi:** Cihaz bölgesinden okunuyor (`Locale.current.currency`): TR → ₺, US → $, Euro bölgesi → €, GB → £. Binlik ve ondalık ayırıcılar ile sembolün önde mi sonda mı olduğu da yerel ayardan geliyor (`₺1.250,50`, `$1,250.50`, `1.250,50 €`).
- **Yabancı para birimi:** Metinde açıkça başka bir para birimi geçen kayıt (`$14.50` ama cihaz TR) kendi sembolüyle saklanır ve listelenir. Kur çevrimi yapılmadığı için toplamlara, bütçeye ve kategori analizine dahil edilmez.
- **Ayrıştırıcı iki dili de okur:** `642,50` / `642.50` / `1.250,00` / `1,250.00` · `3t` / `3x` / `üç taksit` / `in four installments` · `dün` / `yesterday` · `+Maaş` / `+Salary` / `Refund +120` · Türk banka SMS'leri ve `Card ending in 4532 at Whole Foods for $84.50` gibi İngilizce bildirimler.

## Free ve Pro (StoreKit 2)

Satın alma Apple'ın yerel **StoreKit 2** çerçevesiyle yapılır; 3. parti kütüphane yoktur.

| Ücretsiz | Pro |
|---|---|
| Sınırsız yazı ve sesli dikte girişi | Banka SMS / Apple Pay otomasyonu, Kestirmeler ve Siri (`AddExpenseIntent`) |
| iCloud yedekleme, gizlilik bulanıklığı, marka rozetleri | Taksit bölme (`3t`, `6 taksit`, `3x`) ve sınırsız kart (ücretsizde 1 kart + nakit) |
| İçinde bulunulan ayın özeti ve halka grafik analizi | Geçmiş aylar arşivi ve gelecek ay yükü (`‹ ›` okları) |
| Kilit Ekranı widget'ları ve 7 günlük widget | PDF / Excel (CSV) dışa aktarma ve interaktif Hızlı Ekle widget'ı |

**Ürün kimlikleri:**

| Plan | Product ID | Tür | Yedek fiyat (TR / EN) |
|---|---|---|---|
| Aylık | `com.kurus.app.pro.monthly` | Otomatik yenilenen abonelik (P1M) | ₺79,99 / $2.99 |
| Yıllık | `com.kurus.app.pro.yearly` | Otomatik yenilenen abonelik (P1Y) | ₺349,99 / $14.99 |
| Ömür Boyu | `com.kurus.app.pro.lifetime` | Tüketilmeyen (non-consumable) | ₺499,99 / $19.99 |

**Nasıl çalışır:**
- **`App/StoreManager.swift`:**
  - Açılışta `Transaction.currentEntitlements` ile hakkı doğrular ve `Transaction.updates`'i arka planda dinler.
  - `restorePurchases()` ile `AppStore.sync()` çağırır.
  - Sonucu App Group'a `isProUser` olarak yazar (`Shared/ProStatus.swift`); widget ve Kestirmeler bu bayrağı okur.
- **Yedek fiyatlar:** Gerçek fiyatlar `Product.displayPrice`'tan gelir. Yedek fiyatlar yalnızca ürünler yüklenemezse gösterilir.
- **`App/PaywallView.swift`:** Varsayılan plan Ömür Boyu. En altta Geri Yükle, [Kullanım Koşulları](https://www.apple.com/legal/internet-services/itunes/dev/stdeula/) (Apple standart EULA) ve [Gizlilik Politikası](PRIVACY.md) bağlantıları var.

**Ayarlar & Abonelik** (`App/SettingsSheetView.swift`, sağ üst menü › *Ayarlar & Abonelik*):
- **Üyelik Durumu:**
  - Aktif plan: Aylık Pro, Yıllık Pro, Ömür Boyu Pro ya da Ücretsiz.
  - Yenilenme ya da sona erme tarihi: `RenewalInfo.willAutoRenew` açıksa "… tarihinde yenilenecek", kapalıysa "… tarihinde sona erecek".
  - Abonelikte **Aboneliği Yönet / İptal Et** (`.manageSubscriptionsSheet`), ücretsiz planda **Pro'ya Geç**, her durumda **Satın Alımları Geri Yükle**.
- **Veri Yönetimi › Tüm Verileri Sıfırla:**
  - Onay sorduktan sonra harcamaları, kartları ve bütçeyi bu cihazdan ve iCloud'dan siler (`SharedExpenseStore.resetAllData()`).
  - Uygulama SwiftData kullanmıyor; veri App Group `UserDefaults` + iCloud anahtar-değer deposunda tek bir `KurusSnapshot` olarak tutuluyor. Boş anlık görüntü en yeni zaman damgasıyla yazıldığı için iCloud'a bağlı diğer cihazlar da boşalır.
  - Pro satın alımı Apple'da olduğu için etkilenmez.
- **Nasıl Kullanılır?:** Beş örnek komut (kart adının tutardan sonra yazıldığı `Kahve 85 bonus` dahil).
- **iCloud & Veri Yönetimi:**
  - iCloud durumu (`ubiquityIdentityToken`).
  - Kayıtlı kartlar: dokununca düzenleme, çöp kutusuyla silme.
  - **Kart Ekle:** listede olmayan banka / kart (ör. Nkolay) için ad + isteğe bağlı son 4 hane. Ad, ayrıştırıcının kart sözlüğüne girer. Ücretsiz planda 1 kart sınırı aşılınca paywall açılır.
- **Hakkında:** Gizlilik Politikası, Apple Standart EULA ve sürüm/build (`v1.0 (1)`).
- **Pro ödemesini gider olarak ekleme:** Satın almadan sonra ya da Ayarlar'da bir kez, isteğe bağlı sunulur.
  - Aylık → tekrarlayan gider; Yaklaşan Ödemeler'de yenileme olarak görünür.
  - Yıllık / Ömür Boyu → bugüne tek seferlik harcama.

**Kart ve banka tanıma:**
- Banka / kart adı yalnızca **tutardan sonra** yazılınca karttır: `Yemek 300 bonus` → Bonus kartı; `Bonus 200`, `Wings 15`, `World Market 30` kart oluşturmaz.
- İstisna: SMS / bildirim (son 4 hane, `işyeri`, `spent`, `card ending in`…) ya da kart bağlamı (`kartla`, `kartım`, `kartınızla`, `card`) varsa banka adı her yerde olabilir.
- Türk bankaları ve kart programları + Finansbank (→ QNB), yabancı bankalar: Chase, Amex / American Express, Citi, Capital One, Discover, Bank of America, Wells Fargo, U.S. Bank, Apple Card, Barclays, HSBC, Lloyds, NatWest, Monzo, Revolut, N26, Wise, Santander, Deutsche Bank, BNP Paribas.
- Kullanıcının kart adları (takma adlar ve sözlükte olmayan bankalar) aynı kuralla eşleşir: `Kahve 85 nkolay` → Nkolay kartı, başlık “Kahve”.
- Bir gider sonradan Abonelik kategorisine alınırsa tekrarlayan olur (Yaklaşan Ödemeler'e girer); Abonelik'ten çıkarılırsa tekrarlayan olmaktan çıkar. Taksitler hariç.

**Kart silme:**
- Kart hapına ya da hesap kesimi kutusuna basılı tut › *Kartı Sil*, ya da Ayarlar'daki kart listesinden.
- Silmeden önce sorulur: harcamalar *Nakit / Banka Kartı*'na aktarılsın mı (SwiftData'daki `.nullify` karşılığı), yoksa kartla birlikte silinsin mi (`.cascade`)?
- Hiçbir harcama silinmiş bir karta bağlı kalmaz.
- Haplarda `.contextMenu` bilinçli olarak kullanılmıyor: List satırı içindeki bağlam menüleri tüm satıra bağlandığı için yanlış kartı düzenliyordu.

**App Store Connect'te elle yapılacaklar:**
1. *Business › Agreements* altında **Paid Applications** sözleşmesini imzalayın; banka ve vergi bilgilerini doldurun. Bu adım tamamlanmadan ürünler yüklenmez.
2. *Uygulamanız › Subscriptions* altında bir abonelik grubu (ör. "Pro") oluşturun. Yıllık ve aylık abonelikleri yukarıdaki kimliklerle ekleyin; yıllığı daha üst seviye yapın.
3. *In-App Purchases* altında Ömür Boyu'nu **Non-Consumable** olarak ekleyin.
4. Her ürüne fiyat, en az bir yerelleştirme (tr ve en) ve inceleme ekran görüntüsü ekleyin. İlk ürünler uygulama sürümüyle birlikte incelemeye gönderilmelidir.
5. *App Privacy* bölümüne Gizlilik Politikası URL'si olarak `PRIVACY.md` bağlantısını girin. Uygulama veri toplamadığı için "Data Not Collected" seçeneği uygundur.
6. Bundle ID değişirse ürün kimliklerini `StoreManager.Plan.productID` ve `Kurus.storekit` içinde de güncelleyin.

**Yerelde deneme (App Store Connect olmadan):**
- **StoreKit yapılandırması:** Scheme › Run › Options › **StoreKit Configuration** alanından proje kökündeki `Kurus.storekit` dosyasını seçin. Bu dosya üç ürünü USD fiyatlarıyla tanımlar; Türk mağazası için *Editor › Default Storefront* kullanılabilir.
- **İşlem yönetimi:** Satın almaları *Debug › StoreKit › Manage Transactions* penceresinden iade edebilir veya silebilirsiniz.
- **Doğrulama durumu:** `Kurus.storekit` elle yazıldı ve yalnızca JSON olarak doğrulandı. Xcode açmazsa *File › New › File › StoreKit Configuration File* ile yeniden oluşturup aynı üç ürünü ekleyin.

## Hızlı başlangıç

1. `Kurus.xcodeproj` dosyasını **Xcode 15 veya üstü** ile açın.
2. Her iki target için **Signing & Capabilities › Team** alanından Apple Developer takımınızı seçin (aşağıdaki bölüme bakın).
3. `Kurus` şemasını seçip bir iPhone simülatöründe ya da cihazda çalıştırın (⌘R).

> Gerekirse bundle ID'leri değiştirin. `com.kurus.app` başka bir geliştiricinin hesabında kayıtlıysa Xcode imzalama hatası verir. Ne değiştirileceği **Kimlikleri değiştirmek** bölümünde.

## Proje yapısı

```
Kurus/
├── Kurus.xcodeproj/                  Proje + paylaşılan şemalar (Kurus, KurusWidgetExtension)
├── App/                              Yalnızca "Kurus" (uygulama) target'ı
│   ├── KurusApp.swift                @main — uygulama girişi + AppShortcutsProvider
│   ├── ContentView.swift
│   ├── SummaryCardView.swift
│   ├── SmartInputBarView.swift
│   ├── AutomationGuideSheet.swift
│   ├── ExportManager.swift
│   ├── BrandLogoView.swift           Marka işareti, sol üst başlık, ikon dışa aktarıcısı
│   ├── CategoryBreakdownSheet.swift  % rozetinden açılan halka grafik analizi
│   ├── Assets.xcassets               AppIcon, AccentColor, LaunchBackground
│   ├── InfoPlist.xcstrings           Görünen ad: en "Cent" / tr "Kuruş"
│   ├── AppShortcuts.xcstrings        Siri ifadelerinin Türkçesi
│   ├── Info.plist                    kurus:// URL şeması, karanlık açılış ekranı
│   ├── Kurus.entitlements            App Group + iCloud KVS
│   └── PrivacyInfo.xcprivacy         UserDefaults gerekçe beyanı
├── Shared/                           HER İKİ target'a da dahil
│   ├── Localization.swift            Dil/marka (Kuruş·Cent), L(tr, en), yerel para biçimi, örnekler
│   ├── Localizable.xcstrings         Intent ve widget galerisi metinleri (en → tr)
│   ├── Theme.swift
│   ├── BrandEngine.swift
│   ├── ExpenseModel.swift
│   ├── ExpenseParser.swift
│   ├── SharedExpenseStore.swift
│   └── AddExpenseIntent.swift
└── Widget/                           Yalnızca "KurusWidgetExtension" target'ı
    ├── KurusWidget.swift             @main — WidgetBundle (4 widget)
    ├── Assets.xcassets               AccentColor, WidgetBackground
    ├── InfoPlist.xcstrings           Görünen ad: en "Cent" / tr "Kuruş"
    ├── Info.plist                    NSExtension = com.apple.widgetkit-extension
    ├── KurusWidget.entitlements      App Group + iCloud KVS
    └── PrivacyInfo.xcprivacy
```

### Target'lar

| Target | Tür | Bundle ID | Kaynaklar |
|---|---|---|---|
| `Kurus` | iOS uygulaması | `com.kurus.app` | `App/*.swift` + `Shared/*.swift` |
| `KurusWidgetExtension` | Widget Extension (`.appex`) | `com.kurus.app.KurusWidget` | `Widget/KurusWidget.swift` + `Shared/*.swift` |

- Uygulama target'ı widget'a bağımlıdır ve onu **Embed Foundation Extensions** aşamasında `PlugIns/` içine gömer.
- **`@main` çakışması yok:** Uygulama target'ında tek `@main` `KurusApp`, widget target'ında tek `@main` `KurusWidgetBundle`. `Shared/` içinde `@main` bulunmaz.
- `AppShortcutsProvider` (`KurusShortcuts`) yalnızca uygulama target'ındadır.
- Widget'taki interaktif butonlar `AddExpenseIntent`'i widget sürecinde çalıştırır. Bu yüzden intent dosyası iki target'ta da derlenir.

### Önemli derleme ayarları

| Ayar | Değer |
|---|---|
| `IPHONEOS_DEPLOYMENT_TARGET` | 17.0 |
| `SWIFT_VERSION` | 5.0 (Swift 6 katı eşzamanlılık modu bilinçli olarak kapalı) |
| `TARGETED_DEVICE_FAMILY` | 1 (iPhone) |
| `GENERATE_INFOPLIST_FILE` | YES (+ `INFOPLIST_FILE` ile birleştirilir) |
| `CODE_SIGN_STYLE` | Automatic |
| `DEVELOPMENT_TEAM` | Boş, kendi takımınızı seçin |

## Capability'ler

Her iki target'ın entitlements dosyasında şunlar zaten tanımlı:

```xml
<key>com.apple.security.application-groups</key>
<array><string>group.com.kurus.app</string></array>
<key>com.apple.developer.ubiquity-kvstore-identifier</key>
<string>$(TeamIdentifierPrefix)com.kurus.app</string>
```

- **App Groups (`group.com.kurus.app`):** Uygulama, widget ve Kestirmeler aynı `UserDefaults(suiteName:)` deposunu okur ve yazar.
- **iCloud Key-Value Storage:** İki target da **aynı** KVS tanımlayıcısını (`TEAMID.com.kurus.app`) kullanır, yani aynı iCloud anahtar-değer deposunu paylaşır. CloudKit kapsayıcısı gerekmez.

Xcode'da açtığınızda **Signing & Capabilities** sekmesinde her iki target için de *App Groups* ve *iCloud (Key-value storage)* görünmelidir. Görünmüyorsa:

1. Target'ı seçin › **+ Capability › App Groups** › `group.com.kurus.app` grubunu işaretleyin.
2. **+ Capability › iCloud** › yalnızca **Key-value storage** kutusunu işaretleyin.
3. Xcode entitlements dosyasındaki KVS değerini `$(TeamIdentifierPrefix)$(CFBundleIdentifier)` olarak değiştirirse, **widget target'ında** bu değeri tekrar `$(TeamIdentifierPrefix)com.kurus.app` yapın. Aksi halde widget ayrı bir iCloud deposu kullanır.

## Apple Developer hesabında elle yapılacaklar

Otomatik imzalama (*Automatically manage signing*) açıkken Xcode aşağıdakilerin çoğunu kendisi yapar. Elle yapmak ya da kontrol etmek için [developer.apple.com › Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list) sayfasını kullanın:

1. **Üyelik:** App Groups ve iCloud, ücretli **Apple Developer Program** üyeliği gerektirir. Ücretsiz "Personal Team" bu capability'leri imzalayamaz.
2. **App Group kaydı:** *Identifiers › + › App Groups* yolundan `group.com.kurus.app` grubunu oluşturun. Bu ad hesabınızda ya da başka bir hesapta alınmışsa farklı bir ad kullanın (bkz. *Kimlikleri değiştirmek*).
3. **Uygulama App ID'si:** *Identifiers › + › App IDs › App* yolundan `com.kurus.app` kimliğini (Explicit) oluşturun. **App Groups** kutusunu işaretleyip *Configure* ile `group.com.kurus.app` grubunu atayın. **iCloud** kutusunu işaretleyin (CloudKit gerekmez; *Compatible with Xcode 5* / key-value yeterli).
4. **Widget App ID'si:** Aynı adımları `com.kurus.app.KurusWidget` için tekrarlayın: App Groups (aynı grup) ve iCloud.
5. **Profiller:** Otomatik imzalamada Xcode geliştirme profillerini kendisi üretir. Elle imzalıyorsanız iki App ID için ayrı *iOS App Development* ve *App Store* profilleri oluşturup indirin. Capability değiştirdikten sonra profilleri yenileyin.
6. **Cihaz:** Gerçek cihazda çalıştırmak için cihazı *Devices* altında kaydedin. Otomatik imzalamada cihaz bağlıyken Xcode bunu kendisi yapar.

### Kimlikleri değiştirmek

`com.kurus.app` sizin hesabınızda kullanılamıyorsa (ör. `com.adiniz.kurus`) **hepsini birlikte** değiştirin:

| Nerede | Değer |
|---|---|
| Kurus target › Build Settings › `PRODUCT_BUNDLE_IDENTIFIER` | `com.adiniz.kurus` |
| KurusWidgetExtension › `PRODUCT_BUNDLE_IDENTIFIER` | `com.adiniz.kurus.KurusWidget` (uygulama ID'siyle başlamak **zorunlu**) |
| `App/Kurus.entitlements` ve `Widget/KurusWidget.entitlements` › application-groups | `group.com.adiniz.kurus` |
| Aynı iki dosya › ubiquity-kvstore-identifier | `$(TeamIdentifierPrefix)com.adiniz.kurus` |
| `Shared/SharedExpenseStore.swift` › `appGroupID` | `"group.com.adiniz.kurus"` |

## Çalıştırma ve deneme

- **Uygulama:** `Kurus` şeması. İlk açılışta canlı demo (“Netflix 229”, “Turkcell 450”) otomatik oynar.
- **Widget:** `KurusWidgetExtension` şeması widget'ı simülatörde açar (varsayılan `systemMedium`). Ya da uygulamayı kurup ana ekrana widget ekleyin.
- **Deep link:** Simülatörde `xcrun simctl openurl booted kurus://quick-add` giriş çubuğunu odaklar.
- **Siri / Kestirmeler:** “Kuruş ile harcama ekle” / “Log an expense in Cent”. Otomasyon kurulumu uygulama içindeki rehberde anlatılıyor: Türkçede banka SMS’i, İngilizcede Apple Pay (*Transaction*) ve banka SMS’i.
- **Dili denemek:** Scheme › Run › Options › *App Language* ve *App Region* (ör. English / United States) ile uygulama Cent, `$` ve `1,250.50` biçimiyle açılır.
- **iCloud eşitlemesi:** Simülatörde iCloud hesabıyla oturum açın. KVS eşitlemesi gecikmeli olabilir; en güvenilir test iki gerçek cihazla yapılır.

## Kullanım notları

- **Gelir:** Giriş çubuğuna başında `+` ile (`+Maaş 65000`, `İade +450`, `+Salary 5000`, `Refund +120`) ya da *maaş, gelir, iade, prim, ikramiye, kira geliri / salary, income, refund, paycheck* kelimeleriyle yazın.
  - Gelir zümrüt yeşili `+₺` olarak listelenir ve harcama toplamına eklenmez.
  - O ay gelir varsa özet kartındaki limit (`/ ₺…`) o ayın toplam geliri olur; yoksa manuel bütçe gösterilir.
  - `Disney+ 349` gibi harfe yapışık `+` gelir sayılmaz.
- **Ay geçişi:** Özet kartındaki `‹ ›` okları önceki aylara (kayıtlı ilk aya kadar) ve 12 ay ileriye gider. Ay başlığına dokunmak bu aya döndürür.
  - Gelecek aylarda kayıtlı taksitler ve tekrarlayan aboneliklerin **tahmini** kopyaları görünür. Tahminler kaydedilmez; silinemez ve düzenlenemez.
- **Kategori analizi:** Özet kartının sağ üstündeki `%` rozeti, seçili ay ve kart filtresi için halka grafiği açar. Birikim ve gelir bu analize dahil değildir.
- **Uygulama ikonu:** `AppIcon-1024.png`, `KurusAppIconExporter` geometrisinin Python ile çizilmiş bir kopyasıdır. Birebir SwiftUI çıktısı için Xcode'da `BrandLogoView.swift` içindeki “Uygulama ikonu” önizlemesini 1024×1024 dışa aktarıp bu dosyayla değiştirin.

## Doğrulama durumu

Bu proje, Xcode ve Swift derleyicisi **bulunmayan** bir Linux ortamında hazırlandı:

- **Yapılmayan:** `xcodebuild`, Swift derlemesi, simülatör çalıştırma ve birim testi yapılmadı. Projede test target'ı yok.
- **Yapılan:** Yalnızca yapısal kontroller.
  - `project.pbxproj` iki ayrı ayrıştırıcıyla (`openstep_parser`, `mod-pbxproj`) okundu.
  - Tanımsız nesne referansı olmadığı ve hedef üyelikleri ile her target'ta tek `@main` bulunduğu kontrol edildi.
  - plist, entitlements ve xcprivacy dosyaları ayrıştırıldı.
  - Asset `Contents.json` dosyaları ve şema XML'leri doğrulandı.
  - Şemalardaki target kimliklerinin projeyle eşleştiği teyit edildi.

İlk derleme Mac'te yapılacak. Hata çıkarsa Xcode'un hata çıktısını paylaşın.
