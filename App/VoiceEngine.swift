import AVFoundation
import Observation

/// Una voce installata sull'iPhone nella lingua del telefono.
struct VoiceOption: Identifiable, Hashable {
    let id: String            // identificatore di AVSpeechSynthesisVoice
    let name: String
    let gender: AVSpeechSynthesisVoiceGender
    let quality: AVSpeechSynthesisVoiceQuality
}

/// Sessione audio comune a voce e bip: suona anche con l'interruttore silenzioso e abbassa la musica delle altre app.
enum AudioSessionHelper {
    static func activate() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        try? session.setActive(true)
    }
    static func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// Sintesi vocale condivisa da tutta l'app (come VoiceEngine.kt su Android).
/// - Sceglie la voce di qualita' piu' alta nella lingua del telefono, maschile o femminile come da impostazioni
///   (su iPhone il genere della voce e' noto); l'utente puo' anche scegliere una voce precisa con anteprima.
/// - Mentre parla abbassa la musica delle altre app e la riporta al volume normale dopo.
/// - Le frasi vanno in coda; si puo' chiedere una funzione a fine lettura e un id per evidenziare il testo letto.
@Observable
@MainActor
final class VoiceEngine: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = VoiceEngine()

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private var tags: [ObjectIdentifier: String] = [:]
    @ObservationIgnored private var callbacks: [ObjectIdentifier: () -> Void] = [:]
    @ObservationIgnored private var voice: AVSpeechSynthesisVoice?
    @ObservationIgnored private var pitch: Float = 1

    private(set) var voices: [VoiceOption] = []
    /// Id della frase in lettura (per evidenziare il passaggio della spiegazione).
    private(set) var speakingID: String?
    /// Vero se per il genere scelto non c'e' una voce: si usa la migliore disponibile con il tono modificato.
    private(set) var genderApproximated = false

    private override init() {
        super.init()
        synthesizer.delegate = self
        loadVoices()
        applyVoice()
    }

    /// Ricarica l'elenco (dopo una correzione del genere) e riapplica la voce.
    func reloadVoices() {
        loadVoices()
        applyVoice()
    }

    private func loadVoices() {
        let language = Locale.current.language.languageCode?.identifier ?? "en"
        let fixes = AppSettings.shared.voiceGenderFixes
        voices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(language) }
            .filter { !$0.voiceTraits.contains(.isNoveltyVoice) && !$0.voiceTraits.contains(.isPersonalVoice) }
            .map { v in
                // Il genere corretto a mano dall'utente vince su quello indicato da iOS.
                let gender: AVSpeechSynthesisVoiceGender = switch fixes[v.identifier] {
                case "male": .male
                case "female": .female
                default: v.gender
                }
                return VoiceOption(id: v.identifier, name: v.name, gender: gender, quality: v.quality)
            }
            .sorted { ($0.quality.rawValue, $1.name) > ($1.quality.rawValue, $0.name) }   // prima le voci migliori
    }

    /// Applica voce e tono secondo le impostazioni. Da richiamare quando cambiano.
    func applyVoice() {
        let settings = AppSettings.shared
        let wanted: AVSpeechSynthesisVoiceGender = settings.voiceGender == "male" ? .male : .female
        let chosen: AVSpeechSynthesisVoice? = {
            if !settings.voiceIdentifier.isEmpty, let v = AVSpeechSynthesisVoice(identifier: settings.voiceIdentifier) { return v }
            if let best = voices.first(where: { $0.gender == wanted }) { return AVSpeechSynthesisVoice(identifier: best.id) }
            return AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
        }()
        voice = chosen
        let chosenGender = chosen.flatMap { c in voices.first { $0.id == c.identifier }?.gender } ?? chosen?.gender
        genderApproximated = settings.voiceIdentifier.isEmpty && chosenGender != wanted
        pitch = !genderApproximated ? 1 : (wanted == .male ? 0.8 : 1.15)
    }

    /// Legge una frase. `flush` interrompe quelle in coda (conto delle ripetizioni, che non deve accumularsi).
    func speak(_ text: String, id: String = "u", flush: Bool = false, onDone: (() -> Void)? = nil) {
        if flush, synthesizer.isSpeaking { stop() }
        AudioSessionHelper.activate()
        let u = AVSpeechUtterance(string: text)
        u.voice = voice
        u.pitchMultiplier = pitch
        u.rate = min(AVSpeechUtteranceMaximumSpeechRate,
                     max(AVSpeechUtteranceMinimumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * Float(AppSettings.shared.voiceRate)))
        let key = ObjectIdentifier(u)
        tags[key] = id
        if let onDone { callbacks[key] = onDone }
        synthesizer.speak(u)
    }

    /// Interrompe la lettura (le funzioni di fine lettura non vengono chiamate).
    func stop() {
        callbacks.removeAll(); tags.removeAll()
        synthesizer.stopSpeaking(at: .immediate)
        speakingID = nil
    }

    /// Anteprima nelle impostazioni.
    func preview(_ text: String) { applyVoice(); stop(); speak(text) }

    // MARK: - AVSpeechSynthesizerDelegate (puo' arrivare su un altro thread: si torna sul principale)

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let key = ObjectIdentifier(utterance)
        Task { @MainActor in self.speakingID = self.tags[key] }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let key = ObjectIdentifier(utterance)
        Task { @MainActor in self.finished(key, run: true) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let key = ObjectIdentifier(utterance)
        Task { @MainActor in self.finished(key, run: false) }
    }

    private func finished(_ key: ObjectIdentifier, run: Bool) {
        if speakingID == tags[key] { speakingID = nil }
        tags[key] = nil
        let callback = callbacks.removeValue(forKey: key)
        if run { callback?() }
        if !synthesizer.isSpeaking { AudioSessionHelper.deactivate() }
    }
}
