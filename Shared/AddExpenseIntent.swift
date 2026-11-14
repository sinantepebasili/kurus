//
//  AddExpenseIntent.swift
//  Kuruş — Siri, Kestirmeler, SMS otomasyonu ve interaktif widget butonları
//
//  Hedefler: App + Widget Extension
//  (Widget içindeki Button(intent:) bu intent'i uygulamayı açmadan arka planda çalıştırır.)
//

import AppIntents
import SwiftUI

struct AddExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "Harcama Ekle"
    static let description = IntentDescription(
        "Kısa bir metni (“Kahve 145”, “Telefon 36000 3t”) ya da bir banka SMS’inin tamamını Kuruş’a harcama olarak kaydeder.",
        categoryName: "Harcamalar"
    )
    static let openAppWhenRun: Bool = false

    @Parameter(
        title: "Harcama Metni",
        description: "Örn. “Kahve 145” ya da banka SMS’inin tamamı",
        requestValueDialog: IntentDialog("Ne harcadın? Örneğin “Kahve 145”.")
    )
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$text) harcamasını Kuruş’a ekle")
    }

    init() {}

    init(text: String) {
        self.text = text
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        guard let parsed = ExpenseParser.parse(text), parsed.isValid else {
            throw KurusIntentError.amountNotFound
        }

        let store = SharedExpenseStore.shared
        let created = store.add(parsed)
        guard let first = created.first else { throw KurusIntentError.amountNotFound }

        let monthSpend = Ledger.spending(Ledger.inMonth(store.expenses))
        let card = first.cardID.flatMap { store.card(id: $0) }

        var message = "\(first.title) · \(CurrencyFormat.string(first.amount)) kaydedildi."
        if let installment = first.installment {
            message = "\(first.title) · \(installment.count) taksit × \(CurrencyFormat.string(first.amount)) kaydedildi."
        }
        if first.category.isIncome {
            message = "\(first.title) · +\(CurrencyFormat.string(first.amount)) gelir olarak kaydedildi."
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

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .amountNotFound:
            "Metinde bir tutar bulamadım. “Kahve 145” gibi yazmayı dene."
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
        parts.append(card?.pillTitle ?? "Nakit")
        if let installment = expense.installment { parts.append("Taksit \(installment.label)") }
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
                prefix: expense.category.isIncome ? "+" : ""
            )

            VStack(alignment: .leading, spacing: 6) {
                CapsuleMeter(progress: progress, tint: progress > 1 ? Theme.coral : Theme.emerald)
                HStack {
                    Text("Bu ay")
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
