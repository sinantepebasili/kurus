//
//  KurusApp.swift
//  Kuruş / Cent — Uygulama giriş noktası ve Siri/Kestirmeler kısayolları
//
//  Hedef: App
//

import SwiftUI
import AppIntents

@main
struct KurusApp: App {
    @State private var store = SharedExpenseStore.shared
    /// StoreKit 2: açılışta hakları doğrular, Transaction.updates'i dinler
    @State private var storeManager = StoreManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(storeManager)
                .tint(Theme.emerald)
                .preferredColorScheme(.dark)
        }
    }
}

/// "Hey Siri, log an expense in Cent" / "Kuruş ile harcama ekle".
/// İfadelerin Türkçesi AppShortcuts.xcstrings'te; `.applicationName` yerel görünen ad (Kuruş / Cent).
struct KurusShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddExpenseIntent(),
            phrases: [
                "Log an expense in \(.applicationName)",
                "Add an expense to \(.applicationName)",
                "\(.applicationName) expense",
            ],
            shortTitle: "Add Expense",
            systemImageName: "plus.circle.fill"
        )
    }
}
