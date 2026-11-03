import Foundation
import AuthenticationServices
import Observation
import Security
import UIKit
import SpotifyiOS
import MyGymHelperCore

/// Account Spotify dell'utente e Web API (profilo, playlist, ricerca). Come SpotifyAccount.kt su Android.
/// Login: "Authorization Code + PKCE" in una finestra di sistema (ASWebAuthenticationSession), ritorno su
/// mygymhelper://spotify-auth; nessun client secret nell'app. Token salvati solo sul telefono, nel Portachiavi.
/// La riproduzione la comanda l'SDK Spotify (App Remote, vedi `SpotifyRemote`).
@Observable
@MainActor
final class SpotifyService: NSObject {
    static let shared = SpotifyService()
    static let loginRedirect = "mygymhelper://spotify-auth"

    /// Client ID dell'app Spotify (Support/Info.plist, MyGymHelperSpotifyClientID). Vuoto = Spotify non configurato.
    var clientID: String {
        (Bundle.main.object(forInfoDictionaryKey: "MyGymHelperSpotifyClientID") as? String ?? "").trimmingCharacters(in: .whitespaces)
    }
    var configured: Bool { !clientID.isEmpty }

    private(set) var user: SpotifyUser?
    private(set) var loggedIn = false
    private(set) var busy = false
    /// Chiave del messaggio d'errore da mostrare (nil = nessuno).
    var errorKey: String?

    @ObservationIgnored private var token: SpotifyToken?
    @ObservationIgnored private var authSession: ASWebAuthenticationSession?
    @ObservationIgnored private var renewing: Task<String?, Never>?
    @ObservationIgnored private let defaults = UserDefaults.standard

    private override init() {
        super.init()
        token = TokenKeychain.load()
        loggedIn = token != nil
        if let data = defaults.data(forKey: "spotify.user") { user = try? JSONDecoder().decode(SpotifyUser.self, from: data) }
        if loggedIn { Task { await refreshUser() } }
    }

    // MARK: Login

    func login() async {
        guard configured, !busy else { return }
        let verifier = SpotifyWeb.newVerifier()
        let state = String(SpotifyWeb.newVerifier().prefix(16))
        guard let url = URL(string: SpotifyWeb.authorizeURL(clientID: clientID, redirectURI: Self.loginRedirect,
                                                            challenge: SpotifyWeb.challenge(verifier), state: state)) else { return }
        busy = true
        defer { busy = false }
        do {
            let callback: URL = try await withCheckedThrowingContinuation { continuation in
                let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "mygymhelper") { url, error in
                    if let url { continuation.resume(returning: url) } else { continuation.resume(throwing: error ?? URLError(.cancelled)) }
                }
                session.presentationContextProvider = self
                self.authSession = session
                if !session.start() { continuation.resume(throwing: URLError(.cannotLoadFromNetwork)) }
            }
            authSession = nil
            switch SpotifyWeb.parseCallback(callback.absoluteString, expectedState: state) {
            case .code(let code)?: await exchange(code: code, verifier: verifier)
            case .error(let reason)?: errorKey = reason == "access_denied" ? "spotify.error.denied" : "spotify.error.login"
            case nil: errorKey = "spotify.error.login"
            }
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            authSession = nil      // annullato dall'utente: nessun messaggio
        } catch {
            authSession = nil
            errorKey = "spotify.error.login"
            ErrorReporter.shared.report("Spotify: accesso", error: error)
        }
    }

    private func exchange(code: String, verifier: String) async {
        let body = SpotifyWeb.tokenRequestBody(clientID: clientID, code: code, redirectURI: Self.loginRedirect, verifier: verifier)
        guard let response = await post(SpotifyWeb.tokenURL, form: body) else {
            errorKey = "spotify.error.network"; reportNetwork("Spotify: accesso", SpotifyWeb.tokenURL); return
        }
        guard (200..<300).contains(response.status), let t = SpotifyWeb.parseToken(response.data) else {
            errorKey = "spotify.error.login"
            reportStatus("Spotify: accesso", "POST", SpotifyWeb.tokenURL, response)
            return
        }
        save(t)
        await refreshUser()
    }

    /// Scollega l'account: si cancellano token e dati dell'utente dal telefono.
    func logout() {
        token = nil; user = nil; loggedIn = false
        TokenKeychain.delete()
        defaults.removeObject(forKey: "spotify.user")
        SpotifyRemote.shared.disconnect()
    }

    // MARK: Web API

    func refreshUser() async {
        guard let data = await get(SpotifyWeb.meURL), let u = SpotifyWeb.parseUser(data) else { return }
        user = u
        defaults.set(try? JSONEncoder().encode(u), forKey: "spotify.user")
    }

    /// Playlist dell'utente (fino a 200). nil = errore (messaggio in errorKey).
    func playlists() async -> [SpotifyItem]? {
        var out: [SpotifyItem] = []
        var offset = 0
        while offset < 200 {
            guard let data = await get(SpotifyWeb.playlistsURL(offset: offset)) else { return out.isEmpty ? nil : out }
            let page = SpotifyWeb.parsePlaylists(data)
            out += page.items
            if !page.hasMore || page.items.isEmpty { break }
            offset += 50
        }
        return out
    }

    /// Ricerca di playlist, album e brani. nil = errore o testo troppo corto.
    func search(_ query: String) async -> SpotifySearchResult? {
        guard let url = SpotifyWeb.searchURL(query), let data = await get(url) else { return nil }
        return SpotifyWeb.parseSearch(data)
    }

    /// Token valido, rinnovato se sta per scadere (usato anche dall'App Remote). nil = non collegato.
    func validToken(force: Bool = false) async -> String? {
        guard let t = token else { return nil }
        if !force && !t.isExpiring() { return t.accessToken }
        if let renewing { return await renewing.value }        // un solo rinnovo alla volta
        let task = Task<String?, Never> { await self.renew() }
        renewing = task
        let result = await task.value
        renewing = nil
        return result
    }

    private func renew() async -> String? {
        guard let refresh = token?.refreshToken else { expired(); return nil }
        guard let response = await post(SpotifyWeb.tokenURL, form: SpotifyWeb.refreshRequestBody(clientID: clientID, refreshToken: refresh)) else {
            errorKey = "spotify.error.network"; reportNetwork("Spotify: rinnovo accesso", SpotifyWeb.tokenURL); return nil
        }
        if response.status == 400 || response.status == 401 { expired(); return nil }   // rinnovo revocato: serve un nuovo login
        guard (200..<300).contains(response.status), let t = SpotifyWeb.parseToken(response.data, previousRefresh: refresh) else {
            errorKey = Self.errorKey(for: response.status)
            reportStatus("Spotify: rinnovo accesso", "POST", SpotifyWeb.tokenURL, response)
            return nil
        }
        save(t)
        return t.accessToken
    }

    private func expired() {
        logout()
        errorKey = "spotify.error.expired"
    }

    /// GET autenticata; su 401 rinnova il token una volta e riprova.
    private func get(_ url: String) async -> Data? {
        guard let first = await validToken(), let u = URL(string: url) else { return nil }
        var result = await send(URLRequest(url: u), bearer: first)
        if result?.status == 401, let again = await validToken(force: true) { result = await send(URLRequest(url: u), bearer: again) }
        guard let response = result else {
            errorKey = "spotify.error.network"; reportNetwork("Spotify", url); return nil
        }
        guard (200..<300).contains(response.status) else {
            // 403: di solito l'account non e' tra gli utenti dell'app (User Management) nella dashboard Spotify
            errorKey = Self.errorKey(for: response.status)
            reportStatus("Spotify", "GET", url, response)
            return nil
        }
        return response.data
    }

    /// Messaggio per una risposta di errore di Spotify.
    private static func errorKey(for status: Int) -> String {
        switch status {
        case 403: return "spotify.error.forbidden"
        case 429, 500...599: return "spotify.error.server"
        default: return "spotify.error.network"
        }
    }

    /// Rapporto d'errore (Invia / Annulla) con codice e risposta di Spotify.
    private func reportStatus(_ area: String, _ method: String, _ url: String, _ response: (status: Int, data: Data)) {
        let body = String(decoding: response.data.prefix(2000), as: UTF8.self)
        ErrorReporter.shared.report(area, message: "Risposta HTTP \(response.status)",
                                    details: "\(method) \(url) -> \(response.status)\n\(body)")
    }

    private func reportNetwork(_ area: String, _ url: String) {
        if let lastNetworkError {
            ErrorReporter.shared.report(area, error: lastNetworkError, message: "Rete non disponibile: \(url)")
        } else {
            ErrorReporter.shared.report(area, message: "Nessuna risposta", details: url)
        }
    }

    private func post(_ url: String, form: String) async -> (status: Int, data: Data)? {
        guard let u = URL(string: url) else { return nil }
        var request = URLRequest(url: u)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(form.utf8)
        return await send(request, bearer: nil)
    }

    private func send(_ request: URLRequest, bearer: String?) async -> (status: Int, data: Data)? {
        var r = request
        r.timeoutInterval = 20
        if let bearer { r.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        do {
            let (data, response) = try await URLSession.shared.data(for: r)
            guard let http = response as? HTTPURLResponse else { return nil }
            return (http.statusCode, data)
        } catch {
            lastNetworkError = error          // per il rapporto d'errore
            return nil
        }
    }

    /// Ultimo errore di rete (per il rapporto d'errore).
    @ObservationIgnored private var lastNetworkError: Error?

    private func save(_ t: SpotifyToken) {
        token = t; loggedIn = true
        TokenKeychain.save(t)
    }
}

extension SpotifyService: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
        }
    }
}

/// Token Spotify nel Portachiavi (solo su questo telefono, non sincronizzato con iCloud).
private enum TokenKeychain {
    private static let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                               kSecAttrService as String: "app.mygymhelper.spotify",
                                               kSecAttrAccount as String: "token"]

    static func load() -> SpotifyToken? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(SpotifyToken.self, from: data)
    }

    static func save(_ t: SpotifyToken) {
        guard let data = try? JSONEncoder().encode(t) else { return }
        delete()
        var q = query
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }

    static func delete() { SecItemDelete(query as CFDictionary) }
}

/// Collegamento all'app Spotify con l'SDK (App Remote): fa partire, riprende e mette in pausa la musica.
/// Serve l'app Spotify installata. Se Spotify non e' attivo, `wakeAndPlay` la apre facendo partire la musica scelta
/// e torna in MyGymHelper (mygymhelper://spotify-remote), dove ci si collega.
@MainActor
final class SpotifyRemote: NSObject, SPTAppRemoteDelegate {
    static let shared = SpotifyRemote()
    static let redirect = "mygymhelper://spotify-remote"

    private lazy var appRemote: SPTAppRemote = {
        let configuration = SPTConfiguration(clientID: SpotifyService.shared.clientID, redirectURL: URL(string: Self.redirect)!)
        let remote = SPTAppRemote(configuration: configuration, logLevel: .error)
        remote.delegate = self
        return remote
    }()
    private var pending: [() -> Void] = []

    var connected: Bool { appRemote.isConnected }

    /// Si collega (se Spotify e' attivo) e poi esegue `then`. Se il collegamento non riesce, `then` non viene eseguito.
    func connect(token: String?, then action: (() -> Void)? = nil) {
        if connected { action?(); return }
        if let action { pending.append(action) }
        if let token { appRemote.connectionParameters.accessToken = token }
        guard appRemote.connectionParameters.accessToken != nil else { pending.removeAll(); return }
        appRemote.connect()
    }

    /// Apre Spotify facendo partire `uri` (vuoto = l'ultima musica ascoltata); al ritorno ci si collega.
    func wakeAndPlay(uri: String, then action: (() -> Void)? = nil) {
        if let action { pending.append(action) }
        appRemote.authorizeAndPlayURI(uri) { _ in }
    }

    /// Ritorno da Spotify dopo `wakeAndPlay`: true se l'indirizzo era per noi.
    func handle(url: URL) -> Bool {
        guard url.scheme == "mygymhelper", url.host == "spotify-remote" else { return false }
        if let token = appRemote.authorizationParameters(from: url)?[SPTAppRemoteAccessTokenKey] {
            appRemote.connectionParameters.accessToken = token
            appRemote.connect()
        } else {
            pending.removeAll()
        }
        return true
    }

    func play(_ uri: String) { appRemote.playerAPI?.play(uri, callback: nil) }
    func resume() { appRemote.playerAPI?.resume(nil) }
    func pause() { appRemote.playerAPI?.pause(nil) }

    func disconnect() {
        pending.removeAll()
        if connected { appRemote.disconnect() }
    }

    // Le chiamate del delegato arrivano sul thread principale (documentazione dell'SDK).
    nonisolated func appRemoteDidEstablishConnection(_ appRemote: SPTAppRemote) {
        MainActor.assumeIsolated {
            let actions = pending
            pending.removeAll()
            actions.forEach { $0() }
        }
    }

    nonisolated func appRemote(_ appRemote: SPTAppRemote, didFailConnectionAttemptWithError error: Error?) {
        MainActor.assumeIsolated { pending.removeAll() }
    }

    nonisolated func appRemote(_ appRemote: SPTAppRemote, didDisconnectWithError error: Error?) {}
}
