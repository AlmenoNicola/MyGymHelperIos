import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

/// Tipo di contenuto Spotify che si puo' scegliere come musica dell'allenamento.
public enum SpotifyKind: String, Codable, Sendable { case playlist, album, track, artist }

/// Un contenuto Spotify (playlist, album, brano). `detail` = proprietario della playlist o artisti;
/// `count` = numero di brani (solo playlist e album).
public struct SpotifyItem: Equatable, Codable, Sendable, Identifiable {
    public let uri: String
    public let name: String
    public let kind: SpotifyKind
    public var imageURL: String?
    public var detail: String?
    public var count: Int?
    public var id: String { uri }

    public init(uri: String, name: String, kind: SpotifyKind, imageURL: String? = nil, detail: String? = nil, count: Int? = nil) {
        self.uri = uri; self.name = name; self.kind = kind; self.imageURL = imageURL; self.detail = detail; self.count = count
    }
}

/// Account Spotify collegato. `premium` = abbonamento Premium (serve per far partire una playlist precisa).
public struct SpotifyUser: Equatable, Codable, Sendable {
    public let id: String
    public let name: String
    public let imageURL: String?
    public let premium: Bool
}

/// Token di accesso alla Web API. `expiresAt` = scadenza.
public struct SpotifyToken: Equatable, Codable, Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresAt: Date
    /// Vero se scade entro un minuto: conviene rinnovarlo prima di usarlo.
    public func isExpiring(now: Date = Date()) -> Bool { now >= expiresAt.addingTimeInterval(-60) }
}

public struct SpotifySearchResult: Equatable, Sendable {
    public let playlists: [SpotifyItem]
    public let albums: [SpotifyItem]
    public let tracks: [SpotifyItem]
    public var isEmpty: Bool { playlists.isEmpty && albums.isEmpty && tracks.isEmpty }
}

/// Esito del ritorno dal login (redirect con ?code=... oppure ?error=...).
public enum SpotifyCallback: Equatable, Sendable {
    case code(String)
    case error(String)
}

/// Accesso a Spotify con "Authorization Code + PKCE" e lettura di profilo, playlist e ricerca dalla Web API.
/// Qui solo la logica (URL, corpi delle richieste, lettura delle risposte). Stessa logica su Android (SpotifyWeb.kt).
/// Su iOS il login lo fa l'SDK Spotify (SPTSessionManager, anch'esso con PKCE): qui si usano le chiamate alla Web API.
public enum SpotifyWeb {
    public static let authorizeEndpoint = "https://accounts.spotify.com/authorize"
    public static let tokenURL = "https://accounts.spotify.com/api/token"
    public static let apiURL = "https://api.spotify.com/v1"

    /// Permessi chiesti: profilo (nome, Premium), playlist dell'utente, comando della riproduzione.
    public static let scopes = ["user-read-private", "playlist-read-private", "playlist-read-collaborative", "app-remote-control"]

    private static let verifierChars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    /// Codice segreto PKCE (64 caratteri ammessi dallo standard).
    public static func newVerifier() -> String { String((0..<64).map { _ in verifierChars.randomElement()! }) }

    /// code_challenge = BASE64URL(SHA256(verifier)) senza "=" finali (RFC 7636).
    public static func challenge(_ verifier: String) -> String {
        #if canImport(CryptoKit)
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        #else
        return ""
        #endif
    }

    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._*")
    private static func enc(_ v: String) -> String { v.addingPercentEncoding(withAllowedCharacters: unreserved) ?? v }
    private static func form(_ pairs: [(String, String)]) -> String { pairs.map { "\($0.0)=\(enc($0.1))" }.joined(separator: "&") }

    /// Pagina di login di Spotify da aprire nel browser.
    public static func authorizeURL(clientID: String, redirectURI: String, challenge: String, state: String) -> String {
        authorizeEndpoint + "?" + form([("client_id", clientID), ("response_type", "code"), ("redirect_uri", redirectURI),
                                   ("code_challenge_method", "S256"), ("code_challenge", challenge), ("state", state),
                                   ("scope", scopes.joined(separator: " "))])
    }

    public static func tokenRequestBody(clientID: String, code: String, redirectURI: String, verifier: String) -> String {
        form([("grant_type", "authorization_code"), ("code", code), ("redirect_uri", redirectURI),
              ("client_id", clientID), ("code_verifier", verifier)])
    }

    public static func refreshRequestBody(clientID: String, refreshToken: String) -> String {
        form([("grant_type", "refresh_token"), ("refresh_token", refreshToken), ("client_id", clientID)])
    }

    /// Legge il ritorno dal login. nil se non e' il nostro (stato diverso) o non contiene ne' codice ne' errore.
    public static func parseCallback(_ url: String, expectedState: String) -> SpotifyCallback? {
        guard let items = URLComponents(string: url)?.queryItems else { return nil }
        var params: [String: String] = [:]
        for item in items { params[item.name] = item.value ?? "" }
        guard params["state"] == expectedState else { return nil }
        if let error = params["error"] { return .error(error) }
        if let code = params["code"], !code.isEmpty { return .code(code) }
        return nil
    }

    /// Token dalla risposta di /api/token. Nel rinnovo Spotify puo' non rimandare il refresh token: si tiene il precedente.
    public static func parseToken(_ json: Data, now: Date = Date(), previousRefresh: String? = nil) -> SpotifyToken? {
        guard let o = object(json), let access = o["access_token"] as? String, !access.isEmpty else { return nil }
        let seconds = (o["expires_in"] as? NSNumber)?.doubleValue ?? 3600
        return SpotifyToken(accessToken: access, refreshToken: (o["refresh_token"] as? String) ?? previousRefresh,
                            expiresAt: now.addingTimeInterval(seconds))
    }

    public static var meURL: String { apiURL + "/me" }
    public static func playlistsURL(offset: Int = 0) -> String { apiURL + "/me/playlists?limit=50&offset=\(offset)" }

    /// Ricerca di playlist, album e brani (nil se il testo e' troppo corto).
    public static func searchURL(_ query: String, limit: Int = 10) -> String? {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { return nil }
        return apiURL + "/search?" + form([("q", q), ("type", "playlist,album,track"), ("limit", "\(limit)")])
    }

    public static func parseUser(_ json: Data) -> SpotifyUser? {
        guard let o = object(json), let id = o["id"] as? String else { return nil }
        let name = (o["display_name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? id
        return SpotifyUser(id: id, name: name, imageURL: image(o["images"]), premium: (o["product"] as? String) == "premium")
    }

    /// Playlist dell'utente (risposta di /me/playlists) e se ce ne sono altre da caricare.
    public static func parsePlaylists(_ json: Data) -> (items: [SpotifyItem], hasMore: Bool) {
        guard let o = object(json) else { return ([], false) }
        return (items(o["items"], .playlist), o["next"] is String)
    }

    public static func parseSearch(_ json: Data) -> SpotifySearchResult {
        guard let o = object(json) else { return SpotifySearchResult(playlists: [], albums: [], tracks: []) }
        func list(_ key: String) -> Any? { (o[key] as? [String: Any])?["items"] }
        return SpotifySearchResult(playlists: items(list("playlists"), .playlist),
                                   albums: items(list("albums"), .album),
                                   tracks: items(list("tracks"), .track))
    }

    private static func object(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// Elementi di una lista Spotify; quelli nulli o senza uri (capita nelle ricerche) vengono saltati.
    private static func items(_ list: Any?, _ kind: SpotifyKind) -> [SpotifyItem] {
        guard let array = list as? [Any] else { return [] }
        return array.compactMap { raw -> SpotifyItem? in
            guard let o = raw as? [String: Any], let uri = o["uri"] as? String, uri.hasPrefix("spotify:"),
                  let name = o["name"] as? String else { return nil }
            let artists = ((o["artists"] as? [Any]) ?? []).compactMap { ($0 as? [String: Any])?["name"] as? String }
                .joined(separator: ", ")
            let artistsOrNil = artists.isEmpty ? nil : artists
            switch kind {
            case .playlist:
                let total = ((o["tracks"] as? [String: Any]) ?? (o["items"] as? [String: Any]))?["total"] as? Int
                return SpotifyItem(uri: uri, name: name, kind: kind, imageURL: image(o["images"]),
                                   detail: (o["owner"] as? [String: Any])?["display_name"] as? String, count: total)
            case .album:
                return SpotifyItem(uri: uri, name: name, kind: kind, imageURL: image(o["images"]),
                                   detail: artistsOrNil, count: o["total_tracks"] as? Int)
            case .track:
                return SpotifyItem(uri: uri, name: name, kind: kind,
                                   imageURL: image((o["album"] as? [String: Any])?["images"]), detail: artistsOrNil)
            case .artist:
                return SpotifyItem(uri: uri, name: name, kind: kind, imageURL: image(o["images"]))
            }
        }
    }

    /// Immagine piu' adatta a una miniatura: la piu' piccola larga almeno 120 px, altrimenti la piu' grande.
    private static func image(_ list: Any?) -> String? {
        let images: [(String, Int)] = ((list as? [Any]) ?? []).compactMap { raw in
            guard let o = raw as? [String: Any], let url = o["url"] as? String else { return nil }
            return (url, o["width"] as? Int ?? 0)
        }
        guard !images.isEmpty else { return nil }
        return images.filter { $0.1 >= 120 }.min { $0.1 < $1.1 }?.0 ?? images.max { $0.1 < $1.1 }?.0
    }
}

/// Converte un link Spotify incollato dall'utente nell'URI usato dall'SDK (spotify:playlist:ID). Come SpotifyLinks.kt.
public enum SpotifyLinks {
    private static let kinds: Set<String> = ["playlist", "album", "track", "artist"]

    public static func toURI(_ input: String) -> String? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let idOK: (Substring) -> Bool = { id in (10...40).contains(id.count) && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) } }
        let parts = text.split(separator: ":")
        if parts.count == 3, parts[0] == "spotify", kinds.contains(String(parts[1])), idOK(parts[2]) { return text }
        guard let url = URL(string: text), let host = url.host, host == "open.spotify.com" else { return nil }
        var path = url.path.split(separator: "/")
        if let first = path.first, first.hasPrefix("intl-") { path.removeFirst() }
        if path.count >= 2, path[0] == "user" { path.removeFirst(2) }
        guard path.count >= 2, kinds.contains(String(path[0])), idOK(path[1]) else { return nil }
        return "spotify:\(path[0]):\(path[1])"
    }
}
