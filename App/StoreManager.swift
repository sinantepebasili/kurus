//
//  StoreManager.swift
//  Kuruş / Cent — StoreKit 2 ile Free / Pro (Aylık, Yıllık, Ömür Boyu)
//
//  Hedef: App
//
//  • Açılışta Transaction.currentEntitlements ile Pro hakkı doğrulanır.
//  • Transaction.updates arka planda dinlenir (yenileme, iade, Aile Paylaşımı, başka cihazdan alım).
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

        var productID: String {
            switch self {
            case .monthly: "com.kurus.app.pro.monthly"
            case .yearly: "com.kurus.app.pro.yearly"
            case .lifetime: "com.kurus.app.pro.lifetime"
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

    // MARK: - Durum

    private(set) var isPro: Bool
    private(set) var products: [String: Product] = [:]
    private(set) var isPurchasing = false
    private(set) var isRestoring = false
    var lastError: String?

    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    private init() {
        // Doğrulama bitene kadar son bilinen durumla başla (açılışta kilit titremesin)
        isPro = ProStatus.isPro
        updatesTask = listenForTransactions()
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
            lastError = nil
        }
    }

    // MARK: - Haklar

    /// Aktif abonelik ya da ömür boyu alım var mı? Yalnızca doğrulanmış (JWS) işlemler sayılır.
    func refreshEntitlements() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  Plan.productIDs.contains(transaction.productID),
                  transaction.revocationDate == nil else { continue }
            if let expiration = transaction.expirationDate, expiration < .now { continue }
            active = true
        }
        setPro(active)
    }

    private func setPro(_ value: Bool) {
        let changed = isPro != value || ProStatus.isPro != value
        isPro = value
        ProStatus.set(value)
        if changed { WidgetCenter.shared.reloadAllTimelines() }
    }

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

    /// "Satın Alımları Geri Yükle" — App Store Review zorunluluğu
    func restorePurchases() async {
        lastError = nil
        isRestoring = true
        defer { isRestoring = false }
        do {
            try await AppStore.sync()
        } catch {
            lastError = error.localizedDescription
        }
        await refreshEntitlements()
        if !isPro, lastError == nil {
            lastError = L("Geri yüklenecek bir satın alma bulunamadı.", "No purchases to restore were found.")
        }
    }
}
