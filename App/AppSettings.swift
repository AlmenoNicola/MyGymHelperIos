import Foundation
import Observation
import MyGymHelperCore

/// Impostazioni di voce, musica, calibrazione del conteggio e piano di prova, salvate in UserDefaults
/// (stesse chiavi dell'app Android dove possibile). Le calibrazioni sono solo soglie: non sono dati sulla salute,
/// ma vengono comunque cancellate da "Elimina tutti i dati" (che svuota UserDefaults; poi si chiama `reload()`).
@Observable
@MainActor
final class AppSettings {
    static let shared = AppSettings()

    /// Piano simulato predefinito: Full nelle build di debug (Xcode), nessuno (-1) in quelle pubblicate.
    static var debugTierDefault: Int {
        #if DEBUG
        return SubscriptionTier.full.rawValue
        #else
        return -1
        #endif
    }

    @ObservationIgnored private let d = UserDefaults.standard

    /// "female" / "male".
    private(set) var voiceGender = "female"
    /// Voce scelta a mano dall'elenco (identificatore di AVSpeechSynthesisVoice); vuota = scelta automatica.
    private(set) var voiceIdentifier = ""
    /// Moltiplicatore della velocita' normale (0,75 - 1,25).
    private(set) var voiceRate = 0.95
    /// Genere delle voci corretto a mano (identificatore -> "female"/"male"), se quello indicato da iOS e' sbagliato
    /// o manca. Come voiceGenderFixes su Android.
    private(set) var voiceGenderFixes: [String: String] = [:]
    private(set) var voiceCountReps = false
    /// Lettura a voce della spiegazione dell'esercizio (la schermata di spiegazione compare sempre).
    private(set) var explainExercise = true
    /// Elenco scelto nella scheda Allenamento (nil = nessuno: al primo esercizio si crea "Allenamento odierno").
    private(set) var currentListID: UUID?
    /// Attrezzi che l'utente ha in casa (solo piano Full) e filtro "Solo i miei attrezzi" acceso o spento.
    private(set) var ownedEquipment: Set<String> = []
    private(set) var equipmentFilter = false

    /// Schede principali (per passare all'Allenamento dopo aver aggiunto un esercizio da un'altra scheda). Non salvata.
    /// I Piani non sono una scheda: si aprono dall'Area personale.
    enum MainTab: Hashable { case workout, exercises, nutrition, info }
    var selectedTab: MainTab = .workout
    /// Identita' della pila di navigazione di Allenamento: cambiandola si torna alla schermata iniziale. Non salvata.
    var workoutStackID = UUID()
    /// Mostra Allenamento dalla schermata iniziale (dopo aver usato un allenamento di una scheda pronta).
    func showWorkoutRoot() { selectedTab = .workout; workoutStackID = UUID() }
    private(set) var musicEnabled = false
    /// "appleMusic" (l'app avvia e ferma Apple Music), "spotify" (Spotify con l'SDK: playlist scelta, avvio e pausa)
    /// oppure "other" (un'altra app: solo abbassata durante la voce).
    private(set) var musicMode = "appleMusic"
    /// Spotify: URI da far partire (scelto dall'elenco o incollato come link). Vuoto = l'ultima musica ascoltata.
    private(set) var spotifyURI = ""
    /// Spotify: contenuto scelto dall'elenco o dalla ricerca (nil = link incollato o nessuna scelta).
    private(set) var spotifyChoice: SpotifyItem?
    /// Solo build di debug: piano simulato (-1 = quello reale).
    private(set) var debugTier = -1
    private(set) var tunings: [SensorPosition: PositionTuning] = [:]

    private init() { reload() }

    /// Rilegge tutto da UserDefaults (anche dopo "Elimina tutti i dati").
    func reload() {
        voiceGender = d.string(forKey: "voice.gender") ?? "female"
        voiceIdentifier = d.string(forKey: "voice.name") ?? ""
        voiceRate = d.object(forKey: "voice.rate") as? Double ?? 0.95
        voiceGenderFixes = d.dictionary(forKey: "voice.genderFixes") as? [String: String] ?? [:]
        voiceCountReps = d.bool(forKey: "voice.countReps")
        explainExercise = d.object(forKey: "voice.explain") as? Bool ?? true
        currentListID = d.string(forKey: "workout.currentList").flatMap(UUID.init(uuidString:))
        ownedEquipment = HomeEquipment.decode(d.string(forKey: HomeEquipment.ownedKey))
        equipmentFilter = d.bool(forKey: HomeEquipment.filterKey)
        musicEnabled = d.bool(forKey: "music.enabled")
        musicMode = d.string(forKey: "music.mode.ios") ?? "appleMusic"
        spotifyURI = d.string(forKey: "music.spotifyPlaylist") ?? ""
        spotifyChoice = d.data(forKey: "music.spotifyChoice").flatMap { try? JSONDecoder().decode(SpotifyItem.self, from: $0) }
        debugTier = d.object(forKey: "debug.tier") as? Int ?? Self.debugTierDefault
        var map: [SensorPosition: PositionTuning] = [:]
        for p in SensorPosition.allCases {
            if let data = d.data(forKey: "tuning.\(p.rawValue)"),
               let t = try? JSONDecoder().decode(PositionTuning.self, from: data) {
                var safe = t
                safe.sensitivity = min(max(t.sensitivity, PositionTuning.minSensitivity), PositionTuning.maxSensitivity)
                map[p] = safe
            }
        }
        tunings = map
    }

    func setVoiceGender(_ v: String) { voiceGender = v; voiceIdentifier = ""; d.set(v, forKey: "voice.gender"); d.set("", forKey: "voice.name") }
    func setVoiceIdentifier(_ v: String) { voiceIdentifier = v; d.set(v, forKey: "voice.name") }
    /// Segna il genere vero di una voce; se era la voce scelta e non e' del genere voluto, si torna alla scelta automatica.
    func fixVoiceGender(_ identifier: String, gender: String) {
        voiceGenderFixes[identifier] = gender
        d.set(voiceGenderFixes, forKey: "voice.genderFixes")
        if voiceIdentifier == identifier && gender != voiceGender { setVoiceIdentifier("") }
    }
    func setVoiceRate(_ v: Double) { voiceRate = v; d.set(v, forKey: "voice.rate") }
    func setVoiceCountReps(_ v: Bool) { voiceCountReps = v; d.set(v, forKey: "voice.countReps") }
    func setCurrentList(_ id: UUID?) { currentListID = id; d.set(id?.uuidString ?? "", forKey: "workout.currentList") }
    /// Aggiunge o toglie un attrezzo tra quelli che si hanno in casa.
    func toggleOwnedEquipment(_ name: String) {
        if ownedEquipment.contains(name) { ownedEquipment.remove(name) } else { ownedEquipment.insert(name) }
        d.set(HomeEquipment.encode(ownedEquipment), forKey: HomeEquipment.ownedKey)
    }
    func setEquipmentFilter(_ v: Bool) { equipmentFilter = v; d.set(v, forKey: HomeEquipment.filterKey) }
    func setExplainExercise(_ v: Bool) { explainExercise = v; d.set(v, forKey: "voice.explain") }
    func setMusicEnabled(_ v: Bool) { musicEnabled = v; d.set(v, forKey: "music.enabled") }
    func setMusicMode(_ v: String) { musicMode = v; d.set(v, forKey: "music.mode.ios") }
    /// Link o URI incollato a mano: la scelta dall'elenco viene dimenticata.
    func setSpotifyLink(_ v: String) {
        spotifyURI = v; spotifyChoice = nil
        d.set(v, forKey: "music.spotifyPlaylist"); d.removeObject(forKey: "music.spotifyChoice")
    }
    /// Playlist, album o brano scelto dall'app (nil = nessuno: riprende l'ultima musica di Spotify).
    func setSpotifyChoice(_ item: SpotifyItem?) {
        spotifyChoice = item; spotifyURI = item?.uri ?? ""
        d.set(spotifyURI, forKey: "music.spotifyPlaylist")
        if let item, let data = try? JSONEncoder().encode(item) { d.set(data, forKey: "music.spotifyChoice") }
        else { d.removeObject(forKey: "music.spotifyChoice") }
    }
    func setDebugTier(_ v: Int) { debugTier = v; d.set(v, forKey: "debug.tier") }

    // MARK: - Calibrazione per posizione

    func tuning(for position: SensorPosition) -> PositionTuning { tunings[position] ?? PositionTuning() }

    func setTuning(_ tuning: PositionTuning, for position: SensorPosition) {
        tunings[position] = tuning
        if let data = try? JSONEncoder().encode(tuning) { d.set(data, forKey: "tuning.\(position.rawValue)") }
    }

    func resetTuning(for position: SensorPosition) {
        tunings[position] = nil
        d.removeObject(forKey: "tuning.\(position.rawValue)")
    }
}
