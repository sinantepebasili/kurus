//
//  ExportManager.swift
//  Kuruş / Cent — PDF ekstre (ImageRenderer) ve Excel/CSV dışa aktarımı (ShareLink)
//
//  Hedef: App
//

import SwiftUI
import UniformTypeIdentifiers
import CoreTransferable

// MARK: - Paylaşılabilir öğeler (dosya ancak paylaşım anında üretilir)

struct CSVExport: Transferable, Sendable {
    let expenses: [Expense]
    let cards: [PaymentCard]
    let fileName: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { export in
            SentTransferredFile(try ExportManager.writeCSV(export))
        }
    }
}

struct PDFExport: Transferable, Sendable {
    let month: Date
    let expenses: [Expense]
    let cards: [PaymentCard]
    let budget: Decimal
    let fileName: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .pdf) { export in
            SentTransferredFile(try await ExportManager.renderPDF(export))
        }
    }
}

enum ExportError: LocalizedError {
    case renderFailed
    var errorDescription: String? { L("Ekstre oluşturulamadı.", "Couldn’t create the statement.") }
}

// MARK: - Üretici

enum ExportManager {

    static func fileStem(for date: Date = .now) -> String {
        let month = KurusDate.monthYear(date)
            .kurusNormalized
            .replacingOccurrences(of: " ", with: "-")
        return "\(AppLanguage.brandSlug)-\(month)"
    }

    // MARK: CSV — Yerel Excel uyumlu (UTF-8 BOM)
    // Ondalık ayırıcı "," olan yerel ayarlarda (tr, de…) alan ayırıcı ";", aksi halde ",".

    static func writeCSV(_ export: CSVExport) throws -> URL {
        // Kimlik çakışması olsa bile (eski veri) çökmesin: ilk kart kazanır
        let cardNames = Dictionary(export.cards.map { ($0.id, $0.pillTitle) }, uniquingKeysWith: { first, _ in first })
        let separator = CurrencyFormat.style().decimal == "," ? ";" : ","
        let header = AppLanguage.isTurkish
            ? ["Tarih", "Saat", "Açıklama", "Kategori", "Tutar", "Para Birimi", "Kart", "Taksit", "Tekrarlayan", "Not"]
            : ["Date", "Time", "Description", "Category", "Amount", "Currency", "Card", "Installment", "Recurring", "Note"]
        var lines = [header.joined(separator: separator)]

        for e in export.expenses.sorted(by: { $0.date < $1.date }) {
            let row = [
                KurusDate.numeric(e.date),
                KurusDate.time(e.date),
                e.title,
                e.category.title,
                (e.category.isIncome ? "" : "-") + CurrencyFormat.plain(e.amount),
                e.currencyCode ?? Money.homeCurrency,
                e.cardID.flatMap { cardNames[$0] } ?? PaymentCard.cashTitle,
                e.installment?.label ?? "",
                e.isRecurring ? L("Evet", "Yes") : L("Hayır", "No"),
                e.note ?? "",
            ].map { csvField($0, separator: separator) }
            lines.append(row.joined(separator: separator))
        }

        let csv = "\u{FEFF}" + lines.joined(separator: "\r\n")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(export.fileName)
        try? FileManager.default.removeItem(at: url)
        try csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func csvField(_ value: String, separator: String) -> String {
        let needsQuotes = value.contains(separator) || value.contains("\"") || value.contains("\n")
        guard needsQuotes else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: PDF — tek sayfa A4, minimalist ekstre

    @MainActor
    static func renderPDF(_ export: PDFExport) throws -> URL {
        let pageSize = CGSize(width: 595, height: 842)
        let view = StatementPDFView(
            month: export.month,
            expenses: export.expenses,
            cards: export.cards,
            budget: export.budget
        )
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(pageSize)

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(export.fileName)
        try? FileManager.default.removeItem(at: url)

        var didRender = false
        renderer.render { _, draw in
            var box = CGRect(origin: .zero, size: pageSize)
            guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            context.beginPDFPage(nil)
            draw(context)
            context.endPDFPage()
            context.closePDF()
            didRender = true
        }

        guard didRender else { throw ExportError.renderFailed }
        return url
    }
}

// MARK: - Ekstre sayfası

struct StatementPDFView: View {
    let month: Date
    let expenses: [Expense]
    let cards: [PaymentCard]
    let budget: Decimal

    private let ink = Color(hex: "1C1C1E")
    private let sub = Color(hex: "6E6E73")
    private let rule = Color(hex: "1C1C1E").opacity(0.08)
    private let maxRows = 20

    var body: some View {
        let spend = Ledger.spending(expenses)
        let saved = Ledger.savings(expenses)
        let rows = expenses.sorted { $0.date > $1.date }
        let visible = Array(rows.prefix(maxRows))
        let usage = budget > 0 ? (spend / budget).doubleValue : 0

        VStack(alignment: .leading, spacing: 0) {
            // Başlık
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(AppLanguage.brandName)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(ink)
                    Text(L("Hesap Ekstresi · \(KurusDate.monthYear(month))", "Statement · \(KurusDate.monthYear(month))"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(sub)
                }
                Spacer()
                Text(L("Oluşturma: \(KurusDate.numeric(.now))", "Created: \(KurusDate.numeric(.now))"))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(sub)
                    .monospacedDigit()
            }

            Rectangle().fill(rule).frame(height: 1).padding(.vertical, 18)

            // Özet
            HStack(spacing: 10) {
                stat(L("Gerçek Harcama", "Spending"), spend, tint: ink)
                stat(L("Birikim / Yatırım", "Savings / Investing"), saved, tint: Theme.violet)
                stat(L("Bütçe", "Budget") + " · " + Percent.string(usage), budget, tint: sub)
            }

            // Kategori dağılımı
            categoryBreakdown(spend: spend)
                .padding(.top, 20)

            // Tablo
            VStack(spacing: 0) {
                tableHeader
                ForEach(Array(visible.enumerated()), id: \.element.id) { index, expense in
                    tableRow(expense, shaded: index.isMultiple(of: 2))
                }
            }
            .padding(.top, 22)

            if rows.count > visible.count {
                Text(L("+ \(rows.count - visible.count) harcama daha · tam liste CSV dışa aktarımında", "+ \(rows.count - visible.count) more · full list in the CSV export"))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(sub)
                    .padding(.top, 8)
            }

            Spacer(minLength: 0)

            Rectangle().fill(rule).frame(height: 1).padding(.bottom, 10)
            HStack {
                Text(L("Bu ekstre cihazınızda oluşturuldu. Hiçbir veri bir sunucuya gönderilmedi.", "This statement was created on your device. No data was sent to any server."))
                Spacer()
                Text(AppLanguage.brandSlug.lowercased())
            }
            .font(.system(size: 8.5, weight: .medium))
            .foregroundStyle(sub)
        }
        .padding(40)
        .frame(width: 595, height: 842, alignment: .topLeading)
        .background(Theme.paper)
        .environment(\.colorScheme, .light)
    }

    private func stat(_ title: String, _ value: Decimal, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased(with: KurusDate.locale))
                .font(.system(size: 8, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(sub)
            AmountText(amount: value, size: 20, weight: .bold, color: tint)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ink.opacity(0.03), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(rule, lineWidth: 1))
    }

    private func categoryBreakdown(spend: Decimal) -> some View {
        let groups = Dictionary(grouping: expenses.filter { $0.category.countsAsSpending }, by: \.category)
            .map { (category: $0.key, total: Ledger.sum($0.value)) }
            .sorted { $0.total > $1.total }
            .prefix(4)

        return VStack(alignment: .leading, spacing: 7) {
            Text(L("KATEGORİLER", "CATEGORIES"))
                .font(.system(size: 8, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(sub)
            ForEach(Array(groups), id: \.category) { item in
                let share = spend > 0 ? (item.total / spend).doubleValue : 0
                HStack(spacing: 8) {
                    Circle().fill(item.category.color).frame(width: 6, height: 6)
                    Text(item.category.title)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(ink)
                        .frame(width: 70, alignment: .leading)
                    Capsule()
                        .fill(item.category.color.opacity(0.85))
                        .frame(width: max(4, 260 * share), height: 5)
                    Spacer(minLength: 4)
                    Text(Percent.string(share))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(sub)
                        .monospacedDigit()
                    AmountText(amount: item.total, size: 10, weight: .semibold, color: ink, showsFraction: false)
                        .frame(width: 70, alignment: .trailing)
                }
            }
        }
    }

    private var tableHeader: some View {
        HStack(spacing: 8) {
            Text(L("TARİH", "DATE")).frame(width: 52, alignment: .leading)
            Text(L("AÇIKLAMA", "DESCRIPTION")).frame(maxWidth: .infinity, alignment: .leading)
            Text(L("KATEGORİ", "CATEGORY")).frame(width: 70, alignment: .leading)
            Text(L("KART", "CARD")).frame(width: 84, alignment: .leading)
            Text(L("TUTAR", "AMOUNT")).frame(width: 80, alignment: .trailing)
        }
        .font(.system(size: 8, weight: .semibold))
        .tracking(0.5)
        .foregroundStyle(sub)
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
    }

    private func tableRow(_ e: Expense, shaded: Bool) -> some View {
        let card = e.cardID.flatMap { id in cards.first { $0.id == id } }
        return HStack(spacing: 8) {
            Text(KurusDate.shortDay(e.date))
                .frame(width: 52, alignment: .leading)
                .monospacedDigit()
            HStack(spacing: 4) {
                Text(e.title).lineLimit(1)
                if let installment = e.installment {
                    Text(installment.label)
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundStyle(Theme.amber)
                }
                if e.isRecurring {
                    Image(systemName: "repeat")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(Theme.violet)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(e.category.title).frame(width: 70, alignment: .leading).foregroundStyle(sub)
            Text(card?.pillTitle ?? PaymentCard.cashShortTitle)
                .lineLimit(1)
                .frame(width: 84, alignment: .leading)
                .foregroundStyle(sub)
                .monospacedDigit()
            AmountText(
                amount: e.amount,
                size: 10,
                weight: .semibold,
                color: e.category.isIncome ? Theme.emerald : (e.category.isSavings ? Theme.violet : ink),
                prefix: e.category.isIncome ? "+" : "",
                currency: e.currencyCode
            )
                .frame(width: 80, alignment: .trailing)
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(ink)
        .padding(.horizontal, 8)
        .frame(height: 19)
        .background(shaded ? ink.opacity(0.025) : Color.clear, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}
