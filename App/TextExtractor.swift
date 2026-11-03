import Foundation
import PDFKit
import Vision
import UIKit
import UniformTypeIdentifiers
import MyGymHelperCore

/// Estrae il testo da schede in PDF, Excel (.xlsx), Word (.docx), CSV, foto o file di testo, tutto sul telefono
/// (PDFKit e Vision, Excel e Word letti dal Core: nessun server). Le tabelle escono con le celle separate da TAB,
/// cosi' il parser riconosce le colonne. Il risultato passa poi ai parser del Core e alla revisione: l'utente conferma sempre.
enum TextExtractor {
    /// Motivo dell'errore: decide il messaggio mostrato all'utente (stessi casi dell'app Android).
    enum ExtractError: Error { case unreadable, empty, unsupported, legacyOffice, protected, tooLarge }

    /// Pagine massime da riconoscere con l'OCR in un PDF scansionato (per non bloccare il telefono).
    static let maxOCRPages = 10

    /// Dimensione massima del file scelto.
    static let maxFileBytes = 30 * 1024 * 1024

    /// Tipi proposti dal selettore di file (il contenuto viene comunque verificato).
    static var pickerTypes: [UTType] {
        var types: [UTType] = [.pdf, .image, .plainText, .text, .commaSeparatedText, .spreadsheet]
        // .xlsx e .docx; .xls e .doc solo per spiegare che vanno salvati nel formato nuovo.
        for ext in ["xlsx", "docx", "xls", "doc"] {
            if let type = UTType(filenameExtension: ext) { types.append(type) }
        }
        return types
    }

    static func text(fromFile url: URL) async throws -> String {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > maxFileBytes { throw ExtractError.tooLarge }
        let data: Data
        do { data = try Data(contentsOf: url) } catch { throw ExtractError.unreadable }
        let ext = url.pathExtension.lowercased()
        let type = UTType(filenameExtension: ext)

        // Il tipo si decide dal contenuto, non dall'estensione.
        let result: String
        switch OfficeText.detect(data) {
        case .pdf:
            result = try await fromPDF(data)
        case .image:
            result = try await Self.text(fromImageData: data)
        case .legacyOffice:
            throw ExtractError.legacyOffice
        case .zip:
            guard let entries = try? OfficeText.unzipXML(data) else { throw ExtractError.unreadable }
            guard let office = OfficeText.fromOOXML(entries) else { throw ExtractError.unsupported }   // es. .odt / .ods / .pages
            result = office
        case .other:
            if type?.conforms(to: .image) == true {
                result = try await Self.text(fromImageData: data)
            } else {
                let plain = decode(data)
                if OfficeText.looksBinary(plain) { throw ExtractError.unsupported }
                let isCSV = ext == "csv" || type?.conforms(to: .commaSeparatedText) == true
                result = isCSV ? OfficeText.csvToTabs(plain) : plain
            }
        }
        if result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw ExtractError.empty }
        return result
    }

    private static func decode(_ data: Data) -> String {
        let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252) ?? ""
        return text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
    }

    static func text(fromImageData data: Data) async throws -> String {
        guard let image = UIImage(data: data), let cg = image.cgImage else { throw ExtractError.unreadable }
        return try await recognize(cg, orientation: .from(image.imageOrientation))
    }

    /// PDF: si usa il testo incorporato se il parser ci trova esercizi o pasti; altrimenti (PDF scansionato o tabella
    /// che ha perso le colonne) si legge con l'OCR, che mantiene le righe della tabella.
    private static func fromPDF(_ data: Data) async throws -> String {
        guard let pdf = PDFDocument(data: data) else { throw ExtractError.unreadable }
        if pdf.isLocked && !pdf.unlock(withPassword: "") { throw ExtractError.protected }
        let embedded = (pdf.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if embedded.count > 20 {
            let nutrition = NutritionPlanParser.parse(embedded)
            if !TrainingPlanParser.parse(embedded).allEntries.isEmpty || !nutrition.meals.isEmpty || nutrition.calories != nil {
                return embedded
            }
        }
        do {
            return try await ocr(pdf: pdf)
        } catch {
            if embedded.count > 20 { return embedded }
            throw error
        }
    }

    private static func ocr(pdf: PDFDocument) async throws -> String {
        var pages: [String] = []
        for index in 0..<min(pdf.pageCount, maxOCRPages) {
            guard let page = pdf.page(at: index) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let scale = 2000 / max(bounds.width, bounds.height, 1)
            let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
            let image = page.thumbnail(of: size, for: .mediaBox)
            guard let cg = image.cgImage else { continue }
            pages.append(try await recognize(cg, orientation: .up))
        }
        let text = pages.joined(separator: "\n")
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw ExtractError.empty }
        return text
    }

    /// OCR con Vision (modalita' accurata, lingua rilevata in automatico). Le righe tornano in ordine di lettura;
    /// i pezzi di testo alla stessa altezza (le celle di una tabella: "Panca" | "4" | "8") sono separati da TAB.
    static func recognize(_ image: CGImage, orientation: CGImagePropertyOrientation) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.automaticallyDetectsLanguage = true
                do {
                    // perform e' sincrono: i risultati sono pronti al ritorno (una sola ripresa della continuation).
                    try VNImageRequestHandler(cgImage: image, orientation: orientation).perform([request])
                    // Coordinate Vision: origine in basso, quindi dall'alto verso il basso = midY decrescente.
                    let pieces: [(box: CGRect, text: String)] = (request.results ?? [])
                        .compactMap { obs in obs.topCandidates(1).first.map { (box: obs.boundingBox, text: $0.string) } }
                        .sorted { $0.box.midY > $1.box.midY }
                    var rows: [[(box: CGRect, text: String)]] = []
                    for piece in pieces {
                        if let first = rows.last?.first, abs(first.box.midY - piece.box.midY) <= first.box.height / 2 {
                            rows[rows.count - 1].append(piece)
                        } else {
                            rows.append([piece])
                        }
                    }
                    let lines = rows.map { row in row.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: "\t") }
                    continuation.resume(returning: lines.joined(separator: "\n"))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

extension CGImagePropertyOrientation {
    static func from(_ o: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch o {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}
