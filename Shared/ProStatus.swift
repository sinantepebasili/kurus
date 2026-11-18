//
//  ProStatus.swift
//  Kuruş / Cent — Pro durumunun App Group üzerinden paylaşımı
//
//  Hedefler: App + Widget Extension
//
//  StoreManager (yalnızca uygulamada) StoreKit 2 ile doğrulanmış hakları kontrol eder ve sonucu
//  buraya yazar. Widget ve AddExpenseIntent StoreKit'e gitmeden bu bayrağı okur.
//  Bayrak yalnızca bir önbellektir: uygulama her açılışta Transaction.currentEntitlements ile
//  yeniden doğrular, değer gerçek duruma göre düzeltilir.
//

import Foundation

enum ProStatus {
    static let key = "isProUser"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: SharedExpenseStore.appGroupID)
    }

    /// App Group'taki son doğrulanmış Pro durumu
    static var isPro: Bool {
        defaults?.bool(forKey: key) ?? false
    }

    static let planKey = "proPlanProductID"

    /// Son doğrulanmış planın ürün kimliği (açılışta Ayarlar'ın doğru planı hemen göstermesi için)
    static var cachedPlanID: String? {
        defaults?.string(forKey: planKey)
    }

    static func set(_ value: Bool, planID: String? = nil) {
        defaults?.set(value, forKey: key)
        if let planID, value {
            defaults?.set(planID, forKey: planKey)
        } else {
            defaults?.removeObject(forKey: planKey)
        }
    }

    static let selfExpenseKey = "proSelfExpenseHandledTransaction"

    /// "Pro ödemesini giderlerime ekle" teklifi hangi satın alma (originalID) için yanıtlandı?
    /// (Eklendi ya da "Şimdi değil" denildi → aynı satın alma için bir daha sorulmaz.)
    static var selfExpenseHandledID: String? {
        get { defaults?.string(forKey: selfExpenseKey) }
        set { defaults?.set(newValue, forKey: selfExpenseKey) }
    }

    /// Ücretsiz planda izin verilen kart sayısı (nakit sayılmaz)
    static let freeCardLimit = 1
}

/// Pro kilidini tetikleyen özellik — paywall'da ilgili satır vurgulanır.
enum ProFeature: String, Identifiable, Sendable {
    case general
    case smsAutomation
    case installments
    case multipleCards
    case monthHistory
    case export
    case widgets

    var id: String { rawValue }

    /// Paywall'daki 4 süper güç satırından hangisi vurgulanacak (0…3)
    var highlightIndex: Int? {
        switch self {
        case .general: nil
        case .smsAutomation: 0
        case .installments, .multipleCards: 1
        case .monthHistory: 2
        case .export, .widgets: 3
        }
    }
}
