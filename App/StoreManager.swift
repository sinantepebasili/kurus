//
//  StoreManager.swift
//  Kuruş / Cent — StoreKit 2 ile Free / Pro (Aylık, Yıllık, Ömür Boyu)
//
//  Hedef: App
//
//  • Açılışta ve her değişiklikte Transaction.currentEntitlements analiz edilir:
//    aktif plan, bitiş / yenilenme tarihi ve otomatik yenileme (willAutoRenew) dışarı açılır.
//  • Transaction.updates (yeni alım, yenileme, iade, yükseltme, Aile Paylaşımı) ve
//    Product.SubscriptionInfo.Status.updates (otomatik yenilemeyi kapatma gibi işlem üretmeyen
//    değişiklikler) uygulama boyunca dinlenir; StoreManager tekil olduğu için dinleyiciler hep canlıdır.
//  • Sonuç App Group'a (ProStatus) yazılır; widget ve Kestirmeler anında bilir.
//  • 3. parti kütüphane yok; yalnızca StoreKit.
//

import Foundation
import Observation
import StoreKit
import WidgetKit

@MainActor
@Observable
final class StoreManager {

    static let shared = StoreManager()

    // MARK: - Planlar

    enum Plan: String, CaseIterable, Identifiable, Sendable {
        case lifetime, yearly, monthly

        var id: String { rawValue }

        init?(productID: String) {
            guard let plan = Plan.allCases.first(where: { $0.productID == productID }) else { return nil }
            self = plan
        }

        var productID: String {
            switch self {
            case .monthly: "com.kurus.app.pro.monthly"
            case .yearly: "com.kurus.app.pro.yearly"
            case .lifetime: "com.kurus.app.pro.lifetime"
            }
        }

        /// Ayarlar ekranındaki plan adı
        var membershipTitle: String {
            switch self {
            case .monthly: L("Aylık Pro", "Monthly Pro")
            case .yearly: L("Yıllık Pro", "Yearly Pro")
            case .lifetime: L("Ömür Boyu Pro", "Lifetime Pro")
            }
        }

        /// Birden fazla hak varsa (ör. yıllık + ömür boyu) en kapsamlısı gösterilir
        var rank: Int {
            switch self {
            case .lifetime: 3
            case .yearly: 2
            case .monthly: 1
            }
        }

        /// App Store'a ulaşılamazsa (ürünler henüz yüklenmediyse) gösterilen yedek fiyat
        var fallbackPrice: String {
            switch self {
            case .monthly: L("₺79,99", "$2.99")
            case .yearly: L("₺349,99", "$14.99")
            case .lifetime: L("₺499,99", "$19.99")
            }
        }

        /// Tasarruf yüzdesi hesabı için yedek sayısal fiyat
        var fallbackAmount: Decimal {
            switch self {
            case .monthly: AppLanguage.isTurkish ? Decimal(string: "79.99")! : Decimal(string: "2.99")!
            case .yearly: AppLanguage.isTurkish ? Decimal(string: "349.99")! : Decimal(string: "14.99")!
            case .lifetime: AppLanguage.isTurkish ? Decimal(string: "499.99")! : Decimal(string: "19.99")!
            }
        }

        var isSubscription: Bool { self != .lifetime }

        static var productIDs: Set<String> { Set(allCases.map(\.productID)) }
    }

    /// "Satın Alımları Geri Yükle" işleminin durumu (Paywall ve Ayarlar gösterir)
    enum RestoreState: Equatable {
        case idle
        case restoring
        case restored
        case nothingToRestore
        case failed(String)

        var message: String? {
            switch self {
            case .idle, .restoring: nil
            case .restored: L("Satın alımların geri yüklendi.", "Your purchases were restored.")
            case .nothingToRestore: L("Geri yüklenecek bir satın alma bulunamadı.", "No purchases to restore were found.")
            case .failed(let reason): reason
            }
        }

        var isError: Bool {
            switch self {
            case .nothingToRestore, .failed: true
            default: false
            }
        }
    }

    // MARK: - Dışa açık durum

    /// Aktif plan; `nil` → Ücretsiz
    private(set) var activePlan: Plan?
    /// Aylık / Yıllık: mevcut dönemin bitişi (yenilenme ya da sona erme tarihi). Ömür boyu: `nil`
    private(set) var expirationDate: Date?
    /// Otomatik yenileme açık mı? `false` → kullanıcı iptal etti, `expirationDate`'te sona erer.
    /// `nil` → bilinmiyor ya da ömür boyu.
    private(set) var willAutoRenew: Bool?

    private(set) var isPro: Bool
    /// Aktif hakkın satın alma zinciri kimliği (Transaction.originalID)
    private(set) var activeOriginalID: UInt64?
    /// "Kendini gider olarak ekle" teklifinin yanıtlandığı satın alma
    private(set) var selfExpenseHandledID: String?
    private(set) var products: [String: Product] = [:]
    private(set) var isPurchasing = false
    private(set) var restoreState: RestoreState = .idle
    var lastError: String?

    var isRestoring: Bool { restoreState == .restoring }

    @ObservationIgnored private var transactionUpdates: Task<Void, Never>?
    @ObservationIgnored private var statusUpdates: Task<Void, Never>?

    private init() {
        // Doğrulama bitene kadar son bilinen durumla başla (açılışta kilit titremesin)
        isPro = ProStatus.isPro
        activePlan = ProStatus.cachedPlanID.flatMap(Plan.init(productID:))
        selfExpenseHandledID = ProStatus.selfExpenseHandledID
        transactionUpdates = listenForTransactions()
        statusUpdates = listenForSubscriptionStatus()
        Task {
            await loadProducts()
            await refreshEntitlements()
        }
    }

    // MARK: - Ürünler

    func product(for plan: Plan) -> Product? {
        products[plan.productID]
    }

    func displayPrice(for plan: Plan) -> String {
        product(for: plan)?.displayPrice ?? plan.fallbackPrice
    }

    /// Yıllığın aylığa göre tasarrufu (ör. 58)
    var yearlySavingsPercent: Int {
        let monthly = product(for: .monthly)?.price ?? Plan.monthly.fallbackAmount
        let yearly = product(for: .yearly)?.price ?? Plan.yearly.fallbackAmount
        let fullYear = monthly * 12
        guard fullYear > 0 else { return 0 }
        let ratio = (1 - yearly / fullYear).doubleValue
        return max(0, Int((ratio * 100).rounded(.down)))
    }

    func loadProducts() async {
        do {
            let loaded = try await Product.products(for: Plan.productIDs)
            products = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
        } catch {
            // Çevrimdışı ya da App Store Connect'te ürün yok: yedek fiyatlar gösterilir.
        }
    }

    // MARK: - Haklar

    /// Aktif hakları analiz eder. Yalnızca doğrulanmış (JWS), iade edilmemiş ve süresi dolmamış
    /// işlemler sayılır. Birden fazla hak varsa en kapsamlı plan seçilir.
    func refreshEntitlements() async {
        var best: (plan: Plan, transaction: Transaction)?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  let plan = Plan(productID: transaction.productID),
                  transaction.revocationDate == nil else { continue }
            if let expiration = transaction.expirationDate, expiration < .now { continue }
            if best == nil || plan.rank > best!.plan.rank {
                best = (plan, transaction)
            }
        }

        guard let best else {
            apply(plan: nil, expiration: nil, autoRenew: nil, originalID: nil)
            return
        }

        if best.plan.isSubscription {
            let autoRenew = await autoRenewStatus(for: best.transaction)
            apply(plan: best.plan, expiration: best.transaction.expirationDate, autoRenew: autoRenew,
                  originalID: best.transaction.originalID)
        } else {
            apply(plan: best.plan, expiration: nil, autoRenew: nil, originalID: best.transaction.originalID)
        }
    }

    /// Product.SubscriptionInfo.Status → RenewalInfo.willAutoRenew
    private func autoRenewStatus(for transaction: Transaction) async -> Bool? {
        if products[transaction.productID] == nil { await loadProducts() }
        guard let subscription = products[transaction.productID]?.subscription,
              let statuses = try? await subscription.status else { return nil }

        // Önce bu işlemin zincirine (originalID) ait durum
        for status in statuses {
            guard case .verified(let renewal) = status.renewalInfo,
                  case .verified(let current) = status.transaction,
                  current.originalID == transaction.originalID else { continue }
            return renewal.willAutoRenew
        }
        // Tek abonelik grubu: ilk doğrulanmış durum
        for status in statuses {
            if case .verified(let renewal) = status.renewalInfo { return renewal.willAutoRenew }
        }
        return nil
    }

    private func apply(plan: Plan?, expiration: Date?, autoRenew: Bool?, originalID: UInt64?) {
        let isNowPro = plan != nil
        let changed = isPro != isNowPro || ProStatus.isPro != isNowPro
        activePlan = plan
        activeOriginalID = originalID
        expirationDate = expiration
        willAutoRenew = autoRenew
        isPro = isNowPro
        ProStatus.set(isNowPro, planID: plan?.productID)
        if changed { WidgetCenter.shared.reloadAllTimelines() }
    }

    /// Yeni alım, yenileme, iade, yükseltme / düşürme, Aile Paylaşımı, başka cihazdan alım
    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                }
                await self?.refreshEntitlements()
            }
        }
    }

    /// Otomatik yenilemeyi kapatma / açma, faturalama sorunu, ek süre gibi işlem üretmeyen değişiklikler
    private func listenForSubscriptionStatus() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await _ in Product.SubscriptionInfo.Status.updates {
                await self?.refreshEntitlements()
            }
        }
    }

    // MARK: - Satın alma

    /// `true` → Pro artık aktif
    @discardableResult
    func purchase(_ plan: Plan) async -> Bool {
        lastError = nil
        if products.isEmpty { await loadProducts() }
        guard let product = product(for: plan) else {
            lastError = L(
                "App Store’a şu an ulaşılamıyor. Bağlantını kontrol edip tekrar dene.",
                "The App Store isn’t reachable right now. Check your connection and try again."
            )
            return false
        }

        isPurchasing = true
        defer { isPurchasing = false }

        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    lastError = L("Satın alma doğrulanamadı.", "The purchase couldn’t be verified.")
                    return false
                }
                await transaction.finish()
                await refreshEntitlements()
                return isPro
            case .pending:
                // Ebeveyn onayı (Ask to Buy) ya da SCA bekleniyor; Transaction.updates sonucu getirir.
                lastError = L("Satın alma onay bekliyor.", "Your purchase is pending approval.")
                return false
            case .userCancelled:
                return false
            @unknown default:
                return false
            }
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    // MARK: - Geri yükleme

    /// "Satın Alımları Geri Yükle" — App Store Review Kılavuzu 3.1.1 zorunluluğu.
    /// AppStore.sync() Apple Hesabı şifresi isteyebilir; yalnızca kullanıcı dokununca çağrılmalı.
    func restorePurchases() async {
        guard restoreState != .restoring else { return }
        lastError = nil
        restoreState = .restoring
        do {
            try await AppStore.sync()
        } catch StoreKitError.userCancelled {
            restoreState = .idle
            return
        } catch {
            await refreshEntitlements()
            restoreState = .failed(error.localizedDescription)
            lastError = restoreState.message
            return
        }
        await refreshEntitlements()
        restoreState = isPro ? .restored : .nothingToRestore
        if !isPro { lastError = restoreState.message }
    }

    // MARK: - Pro ödemesini gider olarak ekleme (isteğe bağlı, tek dokunuş)

    /// Aktif satın alma için teklif henüz yanıtlanmadıysa `true`
    var shouldOfferSelfExpense: Bool {
        guard isPro, activePlan != nil, let id = activeOriginalID else { return false }
        return selfExpenseHandledID != String(id)
    }

    /// Teklif metninde gösterilecek tutar ("₺79,99" / "$2.99")
    func selfExpensePrice(for plan: Plan) -> String {
        displayPrice(for: plan)
    }

    /// Aylık → tekrarlayan gider (Yaklaşan Ödemeler'de yenileme olarak görünür).
    /// Yıllık / Ömür Boyu → bugüne tek seferlik harcama. Teklif bir daha sorulmaz.
    @discardableResult
    func logSelfExpense(in store: SharedExpenseStore) -> [Expense] {
        guard let plan = activePlan else { return [] }
        let product = product(for: plan)
        let amount = product?.price ?? plan.fallbackAmount
        let code = product?.priceFormatStyle.currencyCode ?? (AppLanguage.isTurkish ? "TRY" : "USD")

        let title = "\(AppLanguage.brandName) Pro"
        var parsed = ParsedExpense(rawText: title, title: title)
        parsed.amount = amount
        parsed.currencyCode = code == Money.homeCurrency ? nil : code
        parsed.category = plan == .lifetime ? .technology : .subscription
        parsed.isRecurring = plan == .monthly

        let created = store.add(parsed)
        markSelfExpenseHandled()
        return created
    }

    func dismissSelfExpenseOffer() {
        markSelfExpenseHandled()
    }

    private func markSelfExpenseHandled() {
        guard let id = activeOriginalID else { return }
        selfExpenseHandledID = String(id)
        ProStatus.selfExpenseHandledID = String(id)
    }

    /// Sayfa kapanınca eski geri yükleme mesajı kalmasın
    func clearRestoreState() {
        if restoreState != .restoring { restoreState = .idle }
    }
}
