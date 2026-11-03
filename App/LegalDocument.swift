import SwiftUI

/// Blocco di un documento legale (titolo, intestazione, paragrafo, elenco puntato).
struct LegalBlock: Identifiable {
    enum Kind { case title, heading, paragraph, bullet }
    let id: Int
    let kind: Kind
    let text: String
}

/// Carica i testi legali da App/Legal/<nome>.<lingua>.md (aggiungili al target come risorse).
/// Se manca la lingua del telefono si usa l'inglese (poi l'italiano). Il testo "[nome dell'app]" diventa il nome dell'app.
enum LegalDocument {
    /// Versione dei testi, salvata insieme all'accettazione (prova di cosa e' stato accettato).
    static let version = "2026-10-20-bozza"

    private static var appName: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? "App"
    }

    private static var languageCode: String { Locale.current.language.languageCode?.identifier ?? "it" }

    private static func url(_ name: String, language: String) -> URL? {
        Bundle.main.url(forResource: "\(name).\(language)", withExtension: "md")
    }

    /// Vero se il documento non esiste nella lingua del telefono e si mostra quello inglese (o italiano).
    static func isFallback(_ name: String) -> Bool {
        url(name, language: languageCode) == nil
    }

    static func load(_ name: String) -> [LegalBlock] {
        for lang in [languageCode, "en", "it"] {
            if let u = url(name, language: lang), let text = try? String(contentsOf: u, encoding: .utf8) {
                return parse(text.replacingOccurrences(of: "[nome dell'app]", with: appName))
            }
        }
        return []
    }

    static func parse(_ text: String) -> [LegalBlock] {
        var blocks: [LegalBlock] = []
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            let kind: LegalBlock.Kind
            let content: String
            if line.hasPrefix("## ") { kind = .heading; content = String(line.dropFirst(3)) }
            else if line.hasPrefix("# ") { kind = .title; content = String(line.dropFirst(2)) }
            else if line.hasPrefix("- ") { kind = .bullet; content = String(line.dropFirst(2)) }
            else { kind = .paragraph; content = line }
            blocks.append(LegalBlock(id: blocks.count, kind: kind, text: content))
        }
        return blocks
    }
}

/// Mostra un documento legale formattato.
struct LegalDocumentView: View {
    let name: String
    var showsTitle = true
    /// Letti una volta sola (non a ogni aggiornamento della vista).
    private let blocks: [LegalBlock]
    private let fallback: Bool

    init(name: String, showsTitle: Bool = true) {
        self.name = name
        self.showsTitle = showsTitle
        self.blocks = LegalDocument.load(name)
        self.fallback = LegalDocument.isFallback(name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if fallback {
                Label("legal.itOnly", systemImage: "globe")
                    .font(.footnote).foregroundStyle(Theme.accentSoft)
            }
            ForEach(blocks) { block in
                switch block.kind {
                case .title:
                    if showsTitle { Text(verbatim: block.text).font(.title3.bold()) }
                case .heading:
                    Text(verbatim: block.text).font(.headline).padding(.top, 8)
                case .paragraph:
                    Text(verbatim: block.text).font(.callout).foregroundStyle(.primary.opacity(0.9))
                case .bullet:
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(verbatim: "•").foregroundStyle(Theme.accent)
                        Text(verbatim: block.text).font(.callout).foregroundStyle(.primary.opacity(0.9))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Schermata a pieno schermo con un documento (da Info).
struct LegalScreen: View {
    let name: String
    let title: LocalizedStringKey

    var body: some View {
        ScrollView {
            LegalDocumentView(name: name, showsTitle: true).glassCard().padding(20)
        }
        .appScreen()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
