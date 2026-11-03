import XCTest
@testable import MyGymHelperCore

/// Logica di accesso e lettura della Web API Spotify. Stessi casi su Android (SpotifyWebTests.kt).
final class SpotifyWebTests: XCTestCase {
    private func data(_ s: String) -> Data { Data(s.utf8) }

    func testPKCEChallengeMatchesRFC7636() {
        XCTAssertEqual(SpotifyWeb.challenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"), "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        XCTAssertEqual(SpotifyWeb.newVerifier().count, 64)
    }

    func testAuthorizeURLAndBodies() {
        let url = SpotifyWeb.authorizeURL(clientID: "abc", redirectURI: "mygymhelper://spotify-auth", challenge: "CH", state: "ST")
        XCTAssertTrue(url.hasPrefix("https://accounts.spotify.com/authorize?client_id=abc&response_type=code"))
        XCTAssertTrue(url.contains("redirect_uri=mygymhelper%3A%2F%2Fspotify-auth"))
        XCTAssertTrue(url.contains("scope=user-read-private%20playlist-read-private"))
        XCTAssertEqual(SpotifyWeb.refreshRequestBody(clientID: "abc", refreshToken: "R"), "grant_type=refresh_token&refresh_token=R&client_id=abc")
    }

    func testCallback() {
        XCTAssertEqual(SpotifyWeb.parseCallback("mygymhelper://spotify-auth?code=AQB&state=S1", expectedState: "S1"), .code("AQB"))
        XCTAssertEqual(SpotifyWeb.parseCallback("mygymhelper://spotify-auth?error=access_denied&state=S1", expectedState: "S1"), .error("access_denied"))
        XCTAssertNil(SpotifyWeb.parseCallback("mygymhelper://spotify-auth?code=AQB&state=ALTRO", expectedState: "S1"))
    }

    func testTokenParsingKeepsRefresh() {
        let now = Date(timeIntervalSince1970: 0)
        let t = SpotifyWeb.parseToken(data(#"{"access_token":"A","expires_in":3600,"refresh_token":"R"}"#), now: now)
        XCTAssertEqual(t?.refreshToken, "R")
        XCTAssertEqual(t?.expiresAt, Date(timeIntervalSince1970: 3600))
        let renewed = SpotifyWeb.parseToken(data(#"{"access_token":"B","expires_in":3600}"#), now: now, previousRefresh: "R")
        XCTAssertEqual(renewed?.refreshToken, "R")
        XCTAssertNil(SpotifyWeb.parseToken(data(#"{"error":"invalid_grant"}"#)))
    }

    func testUserPlaylistsAndSearch() {
        let u = SpotifyWeb.parseUser(data(#"{"id":"nic","display_name":"Nicola","product":"premium","images":[{"url":"http://a/640","width":640},{"url":"http://a/300","width":300},{"url":"http://a/64","width":64}]}"#))
        XCTAssertEqual(u?.name, "Nicola"); XCTAssertEqual(u?.premium, true); XCTAssertEqual(u?.imageURL, "http://a/300")
        let p = SpotifyWeb.parsePlaylists(data(#"{"items":[{"uri":"spotify:playlist:P1","name":"Palestra","owner":{"display_name":"Nicola"},"tracks":{"total":42},"images":[]},null],"next":"x"}"#))
        XCTAssertEqual(p.items, [SpotifyItem(uri: "spotify:playlist:P1", name: "Palestra", kind: .playlist, detail: "Nicola", count: 42)])
        XCTAssertTrue(p.hasMore)
        XCTAssertNil(SpotifyWeb.searchURL("a"))
        XCTAssertEqual(SpotifyWeb.searchURL(" rock gym "), "https://api.spotify.com/v1/search?q=rock%20gym&type=playlist%2Calbum%2Ctrack&limit=10")
        let r = SpotifyWeb.parseSearch(data(#"{"albums":{"items":[{"uri":"spotify:album:A","name":"Album","artists":[{"name":"X"},{"name":"Y"}],"total_tracks":12}]},"tracks":{"items":[null]}}"#))
        XCTAssertEqual(r.albums.first?.detail, "X, Y"); XCTAssertEqual(r.albums.first?.count, 12); XCTAssertTrue(r.tracks.isEmpty)
    }

    func testLinks() {
        XCTAssertEqual(SpotifyLinks.toURI("https://open.spotify.com/playlist/37i9dQZF1DX76Wlfdnj7AP?si=abc123"), "spotify:playlist:37i9dQZF1DX76Wlfdnj7AP")
        XCTAssertEqual(SpotifyLinks.toURI("https://open.spotify.com/intl-it/album/4aawyAB9vmqN3uQ7FjRGTy"), "spotify:album:4aawyAB9vmqN3uQ7FjRGTy")
        XCTAssertNil(SpotifyLinks.toURI("https://example.com/playlist/37i9dQZF1DX76Wlfdnj7AP"))
    }
}
