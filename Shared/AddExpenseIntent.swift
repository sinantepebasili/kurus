//
//  AddExpenseIntent.swift
//  Kuruş / Cent — Siri, Kestirmeler, SMS otomasyonu ve interaktif widget butonları
//
//  Hedefler: App + Widget Extension
//  (Widget içindeki Button(intent:) bu intent'i uygulamayı açmadan arka planda çalıştırır.)
//

import AppIntents
import SwiftUI

struct AddExpenseIntent: AppIntent {
    // Sabit metinler Localizable.xcstrings'ten gelir (kaynak dil: en, çeviri: tr).
    static let title: LocalizedStringResource = "Add Expense"
    static let description = IntentDescription(
        "Logs a short note (“Coffee 5”, “Laptop 1200 3x”) or a full bank SMS / wallet notification as an expense.",
        categoryName: "Expenses"
    )
    static let openAppWhenRun: Bool = false

    @Parameter(
        title: "Expense Text",
        description: "E.g. “Coffee 5” or a full bank SMS",
        requestValueDialog: IntentDialog("What did you spend? For example “Coffee 5”.")
    )
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$text)")
    }

    init() {}

    init(text: String) {
        self.text = text
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        // Kestirmeler, Siri, SMS / cüzdan bildirimi otomasyonu ve interaktif widget Pro özelliğidir.
        // Pro durumu App Group'tan okunur (StoreManager uygulamada doğrular ve yazar).
        guard ProStatus.isPro else {
            throw KurusIntentError.proRequired
        }
        let store = SharedExpenseStore.shared
        guard let parsed = ExpenseParser.parse(text, userCards: store.userCardNames), parsed.isValid else {
            throw KurusIntentError.amountNotFound
        }

        let created = store.add(parsed)
        guard let first = created.first else { throw KurusIntentError.amountNotFound }

        let monthSpend = Ledger.spending(Ledger.inMonth(store.expenses))
        let card = first.cardID.flatMap { store.card(id: $0) }

        let amount = CurrencyFormat.string(first.amount, currency: first.currencyCode)
        var message = L("\(first.title) · \(amount) kaydedildi.", "\(first.title) · \(amount) logged.")
        if let installment = first.installment {
            message = L(
                "\(first.title) · \(installment.count) taksit × \(amount) kaydedildi.",
                "\(first.title) · \(installment.count) installments × \(amount) logged."
            )
        }
        if first.category.isIncome {
            message = L(
                "\(first.title) · +\(amount) gelir olarak kaydedildi.",
                "\(first.title) · +\(amount) logged as income."
            )
        }

        return .result(
            dialog: IntentDialog(stringLiteral: message),
            view: ExpenseSnippetView(
                expense: first,
                card: card,
                monthSpend: monthSpend,
                budget: Ledger.effectiveBudget(Ledger.inMonth(store.expenses), manual: store.monthlyBudget)
            )
        )
    }
}

enum KurusIntentError: Error, CustomLocalizedStringResourceConvertible {
    case amountNotFound
    case proRequired

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .amountNotFound:
            LocalizedStringResource(stringLiteral: L(
                "Metinde bir tutar bulamadım. “Kahve 145” gibi yazmayı dene.",
                "I couldn’t find an amount. Try something like “Coffee 5”."
            ))
        case .proRequired:
            LocalizedStringResource(stringLiteral: L(
                "Kestirmeler ve SMS otomasyonu \(AppLanguage.brandName) Pro ile çalışır. Uygulamayı açıp menüden Pro’ya geçebilirsin.",
                "Shortcuts and SMS automation are part of \(AppLanguage.brandName) Pro. Open the app and upgrade from the menu."
            ))
        }
    }
}

// MARK: - Onay kartı (Snippet View)

struct ExpenseSnippetView: View {
    let expense: Expense
    let card: PaymentCard?
    let monthSpend: Decimal
    let budget: Decimal

    private var subtitle: String {
        var parts = [expense.category.title]
        parts.append(card?.pillTitle ?? PaymentCard.cashTitle)
        if let installment = expense.installment { parts.append("\(L("Taksit", "Installment")) \(installment.label)") }
        return parts.joined(separator: " · ")
    }

    private var progress: Double {
        budget > 0 ? (monthSpend / budget).doubleValue : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ExpenseBadge(brand: expense.brand, category: expense.category, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(expense.title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                Spacer(minLength: 8)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.emerald)
            }

            AmountText(
                amount: expense.amount,
                size: 34,
                weight: .bold,
                color: expense.category.isIncome ? Theme.emerald : Theme.textPrimary,
                prefix: expense.category.isIncome ? "+" : "",
                currency: expense.currencyCode
            )

            VStack(alignment: .leading, spacing: 6) {
                CapsuleMeter(progress: progress, tint: progress > 1 ? Theme.coral : Theme.emerald)
                HStack {
                    Text(L("Bu ay", "This month"))
                    Spacer()
                    Text("\(CurrencyFormat.string(monthSpend, fraction: false)) / \(CurrencyFormat.string(budget, fraction: false))")
                        .monospacedDigit()
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
        .environment(\.colorScheme, .dark)
    }
}
