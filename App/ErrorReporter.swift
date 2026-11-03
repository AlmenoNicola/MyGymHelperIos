import SwiftUI
import UIKit
import MessageUI
import Observation
import MyGymHelperCore

/// Errori da segnalare: quando qualcosa non funziona l'app mostra "Invia" / "Annulla"; con Invia si apre Mail con il
/// rapporto tecnico indirizzato a ErrorReport.email. Niente viene inviato senza l'utente. Come ErrorReporter.kt.
/// Le eccezioni Objective-C non gestite si salvano su file e si propongono al riavvio (gli arresti di Swift non si
/// possono intercettare: restano nei rapporti di Xcode / App Store Connect).
@Observable
@MainActor
final class ErrorReporter {
    static let shared = ErrorReporter()

    struct Pending: Identifiable {
        let id = UUID()
        let area: String
        let message: String
        let details: String
        let time: Date
        var crash = false
    }

    /// Errore da proporre (nil = nessuno). La finestra e' in ContentView (.errorReportAlert()).
    var pending: Pending?
    /// Mail pronta da mostrare (dopo "Invia", se Mail e' configurata).
    var mail: Pending?

    nonisolated static let crashFile = URL.applicationSupportDirectory.appending(path: "last-crash.txt")

    /// Errore Swift: nel rapporto vanno la descrizione completa e il punto in cui e' stato segnalato.
    func report(_ area: String, error: Error, message: String? = nil) {
        let details = String(reflecting: error) + "\n\n" + Thread.callStackSymbols.joined(separator: "\n")
        show(Pending(area: area, message: message ?? error.localizedDescription, details: details, time: Date()))
    }

    /// Errore senza eccezione (es. risposta del server): `details` = codice, indirizzo, risposta...
    func report(_ area: String, message: String, details: String) {
        show(Pending(area: area, message: message,
                     details: details + "\n\n" + Thread.callStackSymbols.joined(separator: "\n"), time: Date()))
    }

    @ObservationIgnored private var lastKey: String?
    @ObservationIgnored private var lastAt = Date.distantPast

    /// Lo stesso errore (es. ogni ricerca Spotify) si propone una volta ogni 10 minuti.
    private func show(_ p: Pending) {
        let key = p.area + "|" + p.message
        if key == lastKey, Date().timeIntervalSince(lastAt) < 600 { return }
        lastKey = key; lastAt = Date()
        pending = p
    }

    /// Da chiamare all'avvio: salva le eccezioni non gestite e propone quella dell'ultima volta.
    func install() {
        NSSetUncaughtExceptionHandler { exception in
            let text = "\(Date())\n\(exception.name.rawValue): \(exception.reason ?? "")\n" + exception.callStackSymbols.joined(separator: "\n")
            try? FileManager.default.createDirectory(at: ErrorReporter.crashFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? text.write(to: ErrorReporter.crashFile, atomically: true, encoding: .utf8)
        }
        if let text = try? String(contentsOf: Self.crashFile, encoding: .utf8) {
            let lines = text.components(separatedBy: "\n")
            pending = Pending(area: "Chiusura improvvisa", message: lines.dropFirst().first ?? "crash",
                              details: lines.dropFirst().joined(separator: "\n"), time: Date(), crash: true)
            try? FileManager.default.removeItem(at: Self.crashFile)
        }
    }

    static func info(time: Date) -> ErrorReport.Info {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        var sys = utsname(); uname(&sys)
        let model = withUnsafePointer(to: &sys.machine) { $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) } }
        #if DEBUG
        let debug = " debug"
        #else
        let debug = ""
        #endif
        return ErrorReport.Info(appVersion: "\(v) (\(b))\(debug)",
                                platform: "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
                                device: model, language: Locale.current.identifier,
                                timeISO: ISO8601DateFormatter().string(from: time))
    }

    /// "Invia": con Mail configurata si apre la mail completa; altrimenti un link mailto (testo piu' corto).
    func send(_ p: Pending, openURL: OpenURLAction) {
        pending = nil
        if MFMailComposeViewController.canSendMail() { mail = p; return }
        let info = Self.info(time: p.time)
        let body = ErrorReport.body(area: p.area, message: p.message, details: p.details, info: info, maxDetails: ErrorReport.maxDetailsLink)
        var c = URLComponents(); c.scheme = "mailto"; c.path = ErrorReport.email
        c.queryItems = [URLQueryItem(name: "subject", value: ErrorReport.subject(area: p.area, info: info)), URLQueryItem(name: "body", value: body)]
        if let url = c.url { openURL(url) }
    }
}

/// Mail di sistema con il rapporto gia' compilato.
struct ErrorMailView: UIViewControllerRepresentable {
    let pending: ErrorReporter.Pending
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let info = ErrorReporter.info(time: pending.time)
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setToRecipients([ErrorReport.email])
        vc.setSubject(ErrorReport.subject(area: pending.area, info: info))
        vc.setMessageBody(ErrorReport.body(area: pending.area, message: pending.message, details: pending.details, info: info), isHTML: false)
        return vc
    }
    func updateUIViewController(_ vc: MFMailComposeViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(dismiss: dismiss) }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let dismiss: DismissAction
        init(dismiss: DismissAction) { self.dismiss = dismiss }
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            dismiss()
        }
    }
}

/// Mail di sistema gia' compilata (destinatario, oggetto, testo): usata da "Suggerisci una funzione".
struct MailComposeView: UIViewControllerRepresentable {
    let to: String
    let subject: String
    let body: String
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setToRecipients([to])
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: false)
        return vc
    }
    func updateUIViewController(_ vc: MFMailComposeViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(dismiss: dismiss) }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let dismiss: DismissAction
        init(dismiss: DismissAction) { self.dismiss = dismiss }
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            dismiss()
        }
    }
}

extension View {
    /// Finestra "Invia" / "Annulla" per il rapporto di un errore, e la mail da compilare. Da mettere su ContentView.
    func errorReportAlert() -> some View { modifier(ErrorReportModifier()) }
}

private struct ErrorReportModifier: ViewModifier {
    @Bindable private var reporter = ErrorReporter.shared
    @Environment(\.openURL) private var openURL

    func body(content: Content) -> some View {
        content
            .alert(LocalizedStringKey(reporter.pending?.crash == true ? "report.crashTitle" : "report.title"),
                   isPresented: Binding(get: { reporter.pending != nil }, set: { if !$0 { reporter.pending = nil } }),
                   presenting: reporter.pending) { p in
                Button("report.send") { reporter.send(p, openURL: openURL) }
                Button("report.cancel", role: .cancel) { reporter.pending = nil }
            } message: { p in
                // Testo tradotto (stessa chiave "report.body %@") + dettagli dell'errore così come sono:
                // un'unica stringa, perché il "+" tra Text è deprecato da iOS 26
                Text(verbatim: String(localized: "report.body \(ErrorReport.email)") + "\n\n\(p.area)\n\(String(p.message.prefix(300)))")
            }
            .sheet(item: $reporter.mail) { p in ErrorMailView(pending: p).ignoresSafeArea() }
    }
}
