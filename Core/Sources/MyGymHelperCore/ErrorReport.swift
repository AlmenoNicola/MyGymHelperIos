import Foundation

// MARK: - E-mail dell'app: contatto, rapporti d'errore e suggerimenti (uguale su Android: ErrorReport.kt)

/// Indirizzo unico dell'app: qui arrivano tutte le e-mail (rapporti d'errore, suggerimenti, contatto).
public enum AppContact {
    public static let email = "mygymhelper@gmail.com"
}

/// E-mail "Suggerisci una funzione" dell'Area personale: l'utente scrive l'idea o cosa manca nell'app.
/// In fondo si aggiungono versione dell'app e del telefono (nessun dato personale), utili per capire il contesto.
/// Segnalazione di un testo generato dall'IA (nota della revisione della scheda), richiesta dalle norme degli store
/// sui contenuti generati dall'IA. L'e-mail contiene l'invito a descrivere il problema, il testo dell'IA e i dati
/// tecnici; l'utente la legge e puo' modificarla prima di inviarla. Uguale a AIContentReport in ErrorReport.kt.
public enum AIContentReport {
    public static let email = AppContact.email

    public static func subject(info: ErrorReport.Info) -> String { "MyGymHelper \(info.appVersion) – segnalazione testo IA" }

    /// `intro` = testo tradotto (chiave "review.report.intro"); `aiText` = testo generato dall'IA da segnalare.
    public static func body(intro: String, aiText: String, info: ErrorReport.Info) -> String {
        [intro, "", "", "", "—",
         "Testo dell'IA: \(aiText)",
         "App: \(info.appVersion)",
         "Sistema: \(info.platform)",
         "Telefono: \(info.device)",
         "Lingua: \(info.language)"].joined(separator: "\n")
    }
}

public enum Suggestion {
    public static let email = AppContact.email

    public static func subject(info: ErrorReport.Info) -> String { "MyGymHelper \(info.appVersion) – suggerimento" }

    /// `intro` = testo tradotto che invita a scrivere (chiave "suggest.intro"); poi righe vuote per il testo dell'utente.
    public static func body(intro: String, info: ErrorReport.Info) -> String {
        [intro, "", "", "", "—",
         "App: \(info.appVersion)",
         "Sistema: \(info.platform)",
         "Telefono: \(info.device)",
         "Lingua: \(info.language)"].joined(separator: "\n")
    }
}

// MARK: - Rapporto d'errore da inviare per e-mail

/// Testo del rapporto tecnico di un errore. Contiene solo dati tecnici (dove e' successo, messaggio, dettagli,
/// versione dell'app e del telefono): mai dati di allenamento, salute o account. L'utente lo legge nell'app di posta
/// prima di inviarlo.
public enum ErrorReport {
    /// Indirizzo a cui arrivano i rapporti.
    public static let email = AppContact.email
    /// Lunghezza massima dei dettagli nel corpo dell'e-mail.
    public static let maxDetails = 12_000
    /// Con i link "mailto:" (senza Mail configurata) il corpo deve restare corto.
    public static let maxDetailsLink = 1_500

    public struct Info: Sendable {
        public let appVersion, platform, device, language, timeISO: String
        public init(appVersion: String, platform: String, device: String, language: String, timeISO: String) {
            self.appVersion = appVersion; self.platform = platform; self.device = device
            self.language = language; self.timeISO = timeISO
        }
    }

    public static func subject(area: String, info: Info) -> String { "MyGymHelper \(info.appVersion) – errore: \(area)" }

    /// Toglie dai dettagli token e codici che non devono uscire dal telefono.
    public static func redact(_ text: String) -> String {
        var s = text.replacingOccurrences(of: #"(?i)(bearer\s+)[A-Za-z0-9._\-]+"#, with: "$1•••", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)("?(?:access_token|refresh_token|code|code_verifier|id_token|client_secret)"?\s*[:=]\s*"?)[^"&\s,}]+"#,
                                   with: "$1•••", options: .regularExpression)
        return s
    }

    public static func body(area: String, message: String, details: String, info: Info, maxDetails: Int = maxDetails) -> String {
        var d = redact(details)
        if d.count > maxDetails { d = String(d.prefix(maxDetails)) + "\n… (troncato)" }
        let m = redact(message).trimmingCharacters(in: .whitespacesAndNewlines)
        return """
        Rapporto di errore di MyGymHelper

        Dove: \(area)
        Messaggio: \(m.isEmpty ? "-" : m)
        Quando: \(info.timeISO)
        App: \(info.appVersion)
        Sistema: \(info.platform)
        Telefono: \(info.device)
        Lingua: \(info.language)

        Dettagli tecnici:
        \(d.isEmpty ? "-" : d)

        (Puoi aggiungere qui cosa stavi facendo.)
        """
    }
}
