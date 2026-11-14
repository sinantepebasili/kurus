//
//  KurusApp.swift
//  Kuruş — Uygulama giriş noktası ve Siri/Kestirmeler kısayolları
//
//  Hedef: App
//

import SwiftUI
import AppIntents

@main
struct KurusApp: App {
    @State private var store = SharedExpenseStore.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .tint(Theme.emerald)
                .preferredColorScheme(.dark)
        }
    }
}

/// "Hey Siri, Kuruş ile harcama ekle" — ve Kestirmeler galerisinde hazır eylem.
struct KurusShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddExpenseIntent(),
            phrases: [
                "\(.applicationName) ile harcama ekle",
                "\(.applicationName)’a harcama yaz",
                "\(.applicationName) harcama",
            ],
            shortTitle: "Harcama Ekle",
            systemImageName: "plus.circle.fill"
        )
    }
}
