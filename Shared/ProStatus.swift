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

    static func set(_ value: Bool) {
        defaults?.set(value, forKey: key)
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
