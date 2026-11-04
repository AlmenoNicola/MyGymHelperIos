import Foundation
import Observation
import CryptoKit
import Supabase
import MyGymHelperCore

/// Account facoltativo su Supabase (e-mail con codice, Apple, Google, Facebook).
/// Serve a collegare gli abbonamenti alla persona (`appAccountToken`) e ad autenticare le chiamate al backend.
/// I dati sanitari NON vengono mai caricati sul server.
/// Configurazione in Info.plist: `MyGymHelperSupabaseURL` e `MyGymHelperSupabaseAnonKey`
/// (la chiave "anon" e' pubblica per progetto; la sicurezza e' data dalle regole RLS dello schema).
@Observable
@MainActor
final class AccountService {
    /// Indirizzo a cui Supabase rimanda dopo l'accesso con Google o Facebook (va aggiunto in Supabase > Auth > URL Configuration).
    static let redirectURL = URL(string: "mygymhelper://login-callback")!

    let client: SupabaseClient?
    private(set) var userID: UUID?
    private(set) var email: String?
    /// Vero se l'utente e' entrato (anche) con Apple: per eliminare l'account serve la conferma con Apple,
    /// cosi' il server puo' revocare i token Apple come richiesto da Apple.
    private(set) var usesApple = false
    private(set) var isWorking = false
    var lastError: String?
    /// Vero dopo il primo evento di sessione: prima non si sa ancora se l'utente ha fatto l'accesso.
    @ObservationIgnored private var sessionKnown = false

    var isConfigured: Bool { client != nil }
    var isSignedIn: Bool { userID != nil }
    /// Facebook va attivato anche in Supabase (Authentication > Providers): in Info.plist `MyGymHelperFacebookLogin` = YES.
    var facebookEnabled: Bool { Bundle.main.object(forInfoDictionaryKey: "MyGymHelperFacebookLogin") as? Bool ?? false }
    /// Accesso con e-mail e codice: per ora spento (in Info.plist `MyGymHelperEmailLogin` = YES per riattivarlo,
    /// dopo aver collegato un servizio e-mail proprio in Supabase).
    var emailEnabled: Bool { Bundle.main.object(forInfoDictionaryKey: "MyGymHelperEmailLogin") as? Bool ?? false }

    init() {
        let info = Bundle.main.infoDictionary ?? [:]
        let urlText = (info["MyGymHelperSupabaseURL"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        let key = (info["MyGymHelperSupabaseAnonKey"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        if let url = URL(string: urlText), url.scheme == "https", !key.isEmpty {
            // emitLocalSessionAsInitialSession: all'avvio arriva subito la sessione salvata, anche se scaduta
            // (nuovo comportamento di supabase-swift, toglie l'avviso in console). Il token scaduto si rinnova
            // da solo alla prima chiamata al backend (vedi bearerToken()).
            client = SupabaseClient(
                supabaseURL: url,
                supabaseKey: key,
                options: SupabaseClientOptions(auth: .init(emitLocalSessionAsInitialSession: true))
            )
        } else {
            client = nil
        }
    }

    /// Indirizzo delle Edge Functions del progetto (usato per il catalogo esercizi).
    var functionsURL: URL? {
        guard let text = Bundle.main.object(forInfoDictionaryKey: "MyGymHelperSupabaseURL") as? String,
              let base = URL(string: text.trimmingCharacters(in: .whitespaces)), base.scheme == "https" else { return nil }
        return base.appending(path: "functions/v1")
    }

    var anonKey: String? {
        let key = (Bundle.main.object(forInfoDictionaryKey: "MyGymHelperSupabaseAnonKey") as? String ?? "")
            .trimmingCharacters(in: .whitespaces)
        return key.isEmpty ? nil : key
    }

    /// Ascolta i cambi di sessione (accesso, uscita, rinnovo del token). Da chiamare una volta all'avvio.
    func start() async {
        guard let client else { return }
        for await change in client.auth.authStateChanges {
            // La sessione iniziale puo' essere scaduta (change.session?.isExpired): l'utente resta comunque
            // quello salvato, cosi' l'app funziona anche offline; il token viene rinnovato quando serve
            // e, se il rinnovo fallisce, Supabase manda l'evento di uscita (session nil).
            sessionKnown = true
            userID = change.session?.user.id
            email = change.session?.user.email
            usesApple = change.session?.user.identities?.contains { $0.provider == "apple" } ?? false
        }
    }

    /// Token da usare verso il backend: quello dell'utente se ha fatto l'accesso, altrimenti la chiave anon.
    func bearerToken() async -> String? {
        guard let client else { return anonKey }
        do {
            let session = try await client.auth.session
            return session.accessToken
        } catch {
            return anonKey   // nessuna sessione: si usa la chiave pubblica del progetto
        }
    }

    // MARK: - Piano dal server

    /// Legge il piano dal server (funzione SQL `get_my_entitlement`): il migliore tra abbonamento collegato
    /// all'account e licenza gratuita assegnata a mano (vedi supabase/migrations/20261103000000_manual_licenses.sql).
    func fetchEntitlement() async -> ServerCheck {
        guard let client else { return .signedOut }
        guard sessionKnown else { return .unavailable }     // sessione ancora in caricamento: si riprova dopo
        guard userID != nil else { return .signedOut }
        do {
            let rows: [EntitlementRow] = try await client.rpc("get_my_entitlement").execute().value
            let row = rows.first
            // "mid": vecchie licenze, ora Pro
            let tier: SubscriptionTier = row?.tier == "full" || row?.tier == "mid" ? .full : .free
            return .found(tier: tier, until: row?.currentPeriodEnd.flatMap(Self.parseDate), source: row?.source)
        } catch {
            return .unavailable
        }
    }

    private struct EntitlementRow: Decodable, Sendable {
        let tier: String
        let currentPeriodEnd: String?
        let source: String?
        enum CodingKeys: String, CodingKey {
            case tier, source
            case currentPeriodEnd = "current_period_end"
        }
    }

    /// Date di PostgreSQL (timestamptz in JSON), con o senza frazioni di secondo.
    private static func parseDate(_ text: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: text) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: text)
    }

    // MARK: - Accesso

    @discardableResult
    func sendEmailCode(to address: String) async -> Bool {
        await run { client in try await client.auth.signInWithOTP(email: address, shouldCreateUser: true) }
    }

    @discardableResult
    func verifyEmailCode(_ code: String, email address: String) async -> Bool {
        await run { client in try await client.auth.verifyOTP(email: address, token: code, type: .email) }
    }

    @discardableResult
    func signInWithApple(idToken: String, rawNonce: String) async -> Bool {
        await run { client in
            try await client.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: rawNonce))
        }
    }

    @discardableResult
    func signInWithGoogle() async -> Bool {
        await run { client in
            try await client.auth.signInWithOAuth(provider: .google, redirectTo: AccountService.redirectURL)
        }
    }

    /// Accesso con Facebook: Supabase apre la pagina di Facebook in una finestra di sistema (ASWebAuthenticationSession)
    /// e riceve il ritorno su `redirectURL`. Non serve l'SDK di Facebook.
    @discardableResult
    func signInWithFacebook() async -> Bool {
        guard facebookEnabled else { return false }
        return await run { client in
            try await client.auth.signInWithOAuth(provider: .facebook, redirectTo: AccountService.redirectURL)
        }
    }

    func signOut() async {
        _ = await run { client in try await client.auth.signOut() }
    }

    private struct DeleteRequest: Encodable, Sendable {
        let apple_authorization_code: String?
    }

    /// Elimina l'account e i dati collegati sul server (funzione `delete-account`), poi esce.
    /// `appleAuthorizationCode`: codice appena ottenuto confermando con Apple (obbligatorio se `usesApple`);
    /// il server lo usa una sola volta per revocare i token Apple e non lo conserva.
    /// Gli abbonamenti attivi restano su Apple: l'utente li annulla dalle impostazioni dell'Apple ID.
    @discardableResult
    func deleteAccount(appleAuthorizationCode: String? = nil) async -> Bool {
        let request = DeleteRequest(apple_authorization_code: appleAuthorizationCode)
        let ok = await run { client in
            try await client.functions.invoke("delete-account", options: FunctionInvokeOptions(body: request))
        }
        if ok { await signOut() }
        return ok
    }

    @discardableResult
    private func run(_ action: (SupabaseClient) async throws -> Void) async -> Bool {
        guard let client else { return false }
        isWorking = true
        defer { isWorking = false }
        do {
            try await action(client)
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    // MARK: - Nonce per Accedi con Apple

    /// Stringa casuale: il suo hash SHA-256 va nella richiesta Apple, il valore originale a Supabase.
    static func makeNonce(length: Int = 32) -> String {
        let chars = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        return String((0..<length).map { _ in chars[Int.random(in: 0..<chars.count)] })
    }

    static func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
