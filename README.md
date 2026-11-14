# Kuruş

Sunucusuz, hesapsız, saf SwiftUI harcama takip uygulaması. iOS 17.0+ · iPhone · Swift 5 dil modu · 3. parti bağımlılık yok.

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
│   ├── Assets.xcassets               AppIcon, AccentColor, LaunchBackground
│   ├── Info.plist                    kurus:// URL şeması, karanlık açılış ekranı
│   ├── Kurus.entitlements            App Group + iCloud KVS
│   └── PrivacyInfo.xcprivacy         UserDefaults gerekçe beyanı
├── Shared/                           HER İKİ target'a da dahil
│   ├── Theme.swift
│   ├── BrandEngine.swift
│   ├── ExpenseModel.swift
│   ├── ExpenseParser.swift
│   ├── SharedExpenseStore.swift
│   └── AddExpenseIntent.swift
└── Widget/                           Yalnızca "KurusWidgetExtension" target'ı
    ├── KurusWidget.swift             @main — WidgetBundle (4 widget)
    ├── Assets.xcassets               AccentColor, WidgetBackground
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
- **Siri / Kestirmeler:** “Kuruş ile harcama ekle”. SMS otomasyonu kurulumu uygulama içindeki *Banka SMS Otomasyonu Rehberi*'nde anlatılıyor.
- **iCloud eşitlemesi:** Simülatörde iCloud hesabıyla oturum açın. KVS eşitlemesi gecikmeli olabilir; en güvenilir test iki gerçek cihazla yapılır.

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
