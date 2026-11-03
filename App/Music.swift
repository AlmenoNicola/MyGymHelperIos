import Foundation
import MediaPlayer
import MyGymHelperCore

/// Musica durante l'allenamento: parte (o riprende) a inizio serie e si ferma durante la spiegazione.
/// Su iPhone un'app puo' comandare Apple Music (lettore di sistema) e Spotify (con l'SDK Spotify, App Remote);
/// le altre app musicali (YouTube Music...) non si possono comandare: la musica continua e la voce la abbassa.
@MainActor
protocol MusicPlayer: AnyObject {
    /// Preparazione all'inizio della sessione (per Apple Music: richiesta del permesso).
    func prepare()
    func onSetStart()
    func onExplanation()
    func release()
}

@MainActor
enum Music {
    static func create(settings: AppSettings) -> MusicPlayer? {
        guard settings.musicEnabled else { return nil }
        switch settings.musicMode {
        case "appleMusic": return AppleMusicPlayer()
        case "spotify" where AppFlags.spotifyIntegration && SpotifyService.shared.configured:
            return SpotifyPlayer(uri: SpotifyLinks.toURI(settings.spotifyURI) ?? "")
        default: return nil
        }
    }
}

/// Apple Music con il lettore di sistema (riprende l'ultima musica ascoltata in Musica).
/// Serve NSAppleMusicUsageDescription in Info.plist e il permesso dell'utente.
@MainActor
final class AppleMusicPlayer: MusicPlayer {
    private let player = MPMusicPlayerController.systemMusicPlayer
    private var authorized = MPMediaLibrary.authorizationStatus() == .authorized

    func prepare() {
        guard !authorized else { return }
        MPMediaLibrary.requestAuthorization { status in
            Task { @MainActor [weak self] in self?.authorized = status == .authorized }
        }
    }

    func onSetStart() {
        guard authorized, player.playbackState != .playing else { return }
        player.play()
    }

    func onExplanation() {
        guard authorized, player.playbackState == .playing else { return }
        player.pause()
    }

    func release() {}
}

/// Spotify con l'SDK (App Remote): alla prima serie fa partire la musica scelta, alle successive la riprende, durante
/// la spiegazione la mette in pausa. Serve l'app Spotify; per far partire una playlist precisa serve Premium.
/// Se Spotify non e' attivo, alla prima serie si apre Spotify (che fa partire la musica) e si torna nell'app.
@MainActor
final class SpotifyPlayer: MusicPlayer {
    private let uri: String
    private var started = false
    private var remote: SpotifyRemote { SpotifyRemote.shared }

    init(uri: String) { self.uri = uri }

    func prepare() {
        Task { @MainActor in
            let token = await SpotifyService.shared.validToken()
            remote.connect(token: token)      // riesce solo se Spotify e' gia' attivo
        }
    }

    func onSetStart() {
        if remote.connected { playOrResume(); return }
        if !started {
            started = true
            remote.wakeAndPlay(uri: uri)      // Spotify parte gia' con la musica scelta
        } else {
            remote.connect(token: nil) { [weak self] in self?.playOrResume() }
        }
    }

    private func playOrResume() {
        if !started && !uri.isEmpty { remote.play(uri) } else { remote.resume() }
        started = true
    }

    func onExplanation() {
        if remote.connected { remote.pause() }
    }

    func release() { remote.disconnect() }
}
