import Foundation
import Observation
import UIKit
import MyGymHelperCore

/// Collega macchina a stati, sensori, avvisi, spiegazione, musica e salvataggio di una sessione
/// (come SessionController.kt su Android).
@Observable
@MainActor
final class SessionController {
    let position: SensorPosition
    /// Parametri della sessione (serie diverse: ripetizioni e peso di ogni serie in `targets`).
    let parameters: WorkoutParameters
    /// Obiettivo di ogni serie, nell'ordine.
    let targets: [SetTarget]
    let isVaried: Bool
    let totalSets: Int
    let restSeconds: Int
    let exercise: CatalogExercise?
    /// Peso della prima serie (serie uguali: di tutte).
    let weightKg: Double
    let startedAt = Date()
    let motion: MotionService

    private(set) var phase: SessionPhase = .notStarted
    private(set) var currentReps = 0
    private(set) var records: [SetRecord] = []

    /// Spiegazione dell'esercizio prima della prima serie: sempre a schermo (con "Salta"), a voce se richiesto.
    let hasExplanation: Bool
    private(set) var explaining: Bool
    /// Secondi alla partenza della prima serie dopo la spiegazione (nil = lettura in corso).
    private(set) var startCountdown: Int?

    @ObservationIgnored private var engine: SessionEngine
    @ObservationIgnored private let cues: CueService
    @ObservationIgnored private let music: MusicPlayer?
    @ObservationIgnored private let voiceOn: Bool
    /// Leggere a voce la spiegazione (impostazioni audio). La schermata di spiegazione compare comunque.
    @ObservationIgnored private let readAloud: Bool
    @ObservationIgnored private var startAt: TimeInterval?
    @ObservationIgnored private var lastCountdown: Int?
    @ObservationIgnored private var explainingInRest = false
    @ObservationIgnored private var metrics: [(peak: Double, low: Bool)] = []
    @ObservationIgnored private var running = false
    /// Cosa dire nella pausa prima dell'ultima serie (prossimo esercizio dell'elenco o fine della giornata).
    /// Si calcola a quel momento, cosi' tiene conto dello stato attuale dell'elenco.
    @ObservationIgnored private let lastSetNotice: @MainActor () -> LastSetNotice

    init(position: SensorPosition, tuning: PositionTuning, parameters: WorkoutParameters,
         exercise: CatalogExercise?, options: CueOptions, readAloud: Bool,
         lastSetNotice: @escaping @MainActor () -> LastSetNotice = { .lastSetOnly }) {
        let targets = parameters.targets.map { SetTarget(reps: max(1, $0.reps), weightKg: $0.weightKg) }
        self.position = position
        self.exercise = exercise
        self.parameters = parameters
        self.targets = targets
        self.isVaried = parameters.isVaried
        self.weightKg = targets[0].weightKg
        self.totalSets = targets.count
        self.restSeconds = parameters.restSeconds
        self.engine = SessionEngine(repsPerSet: targets.map(\.reps), restSeconds: parameters.restSeconds)
        self.motion = MotionService(config: tuning.config())
        self.cues = CueService(options: options)
        self.voiceOn = options.voice
        self.music = Music.create(settings: AppSettings.shared)
        self.hasExplanation = !(exercise?.steps.isEmpty ?? true)
        self.readAloud = readAloud
        self.explaining = hasExplanation
        self.lastSetNotice = lastSetNotice
    }

    /// Orologio monotono: non cambia se l'utente modifica l'ora del telefono.
    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    var currentSetNumber: Int {
        switch phase {
        case .working(let n): return n
        case .resting(let n, _): return n + 1
        case .notStarted: return 1
        default: return records.count
        }
    }

    /// Obiettivo della serie `set` (1 = prima).
    func target(_ set: Int) -> SetTarget { targets[min(max(set, 1), totalSets) - 1] }

    /// Obiettivo della serie in corso (in pausa: della prossima).
    var currentTarget: SetTarget { target(currentSetNumber) }

    /// Ripetizioni obiettivo della serie in corso (in pausa: della prossima).
    var targetReps: Int { currentTarget.reps }

    /// Apertura della schermata: spiegazione (se prevista) e poi prima serie.
    func start() {
        // Solo la prima volta: tornando sulla schermata a sessione finita non si riaccendono i sensori.
        guard !running, phase == .notStarted else { return }
        running = true
        UIApplication.shared.isIdleTimerDisabled = true   // schermo acceso: i sensori si fermano se l'app va in background
        music?.prepare()
        motion.onRepCount = { [weak self] count in
            Task { @MainActor in self?.repsUpdated(count) }
        }
        if !explaining { beginFirstSet() }
        else if readAloud { explain() }
        else { startAt = now + Self.readSeconds }      // senza lettura a voce: tempo per leggere, poi si parte
    }

    /// Legge di nuovo la spiegazione (prima della partenza o durante una pausa). La musica si ferma.
    func explain() {
        guard let exercise, hasExplanation else { return }
        music?.onExplanation()
        if case .resting = phase { explainingInRest = true }
        if phase == .notStarted { startAt = nil; startCountdown = nil; lastCountdown = nil }
        cues.explain(exercise) { [weak self] in
            guard let self else { return }
            // Prima serie: dopo la lettura parte il conto alla rovescia (3 s; 15 s per leggere se la voce e' spenta).
            if self.phase == .notStarted && self.explaining { self.startAt = self.now + (self.voiceOn ? 3 : Self.readSeconds) }
        }
    }

    /// Secondi per leggere la spiegazione quando non viene letta a voce.
    static let readSeconds: TimeInterval = 15

    /// "Salta": salta spiegazione e conto alla rovescia, il conteggio parte subito.
    func startNow() {
        guard phase == .notStarted else { return }
        cues.stopSpeaking()
        beginFirstSet()
    }

    private func beginFirstSet() {
        explaining = false; startAt = nil; startCountdown = nil
        motion.start()
        motion.beginSet()
        music?.onSetStart()
        apply(engine.start(at: now))
    }

    /// Da chiamare circa 4 volte al secondo.
    func tick() {
        if phase == .notStarted, let at = startAt {
            let remaining = Int((at - now).rounded(.up))
            startCountdown = max(0, remaining)
            if remaining <= 0 { beginFirstSet(); return }
            if remaining <= 3 && lastCountdown != remaining { lastCountdown = remaining; cues.countdown(remaining) }
            return
        }
        apply(engine.tick(at: now))
    }

    func stop(doneReps: Int) { apply(engine.stop(doneReps: doneReps, at: now)) }
    func skipRest() { apply(engine.skipRest(at: now)) }
    func endEarly() { apply(engine.endNow(at: now)) }

    /// Rilascia sensori, schermo e audio.
    func end() {
        guard running else { return }
        running = false
        motion.onRepCount = nil
        motion.stop()
        UIApplication.shared.isIdleTimerDisabled = false
        cues.shutdown()
        music?.release()
    }

    private func repsUpdated(_ count: Int) {
        guard running else { return }
        apply(engine.repsCounted(count, at: now))
        if case .working = phase { cues.repCounted(engine.currentReps, target: engine.targetReps) }
    }

    private func apply(_ list: [SessionCue]) {
        let setNow: Int = { if case .working(let n) = engine.phase { return n } else { return currentSetNumber } }()
        for cue in list {
            // Una spiegazione riascoltata in pausa non deve sovrapporsi al conto alla rovescia e alla nuova serie.
            if explainingInRest {
                switch cue {
                case .restCountdown, .restEnded, .sessionFinished: explainingInRest = false; cues.stopSpeaking()
                default: break
                }
            }
            if case .restEnded = cue { music?.onSetStart() }   // prima della voce: la musica riparte a inizio serie
            cues.play(cue, currentSet: setNow, totalSets: totalSets)
            // Serie diverse: a inizio pausa si annunciano ripetizioni e peso della prossima serie, se cambiano.
            if case .restStarted = cue, case .resting(let done, _) = engine.phase, target(done + 1) != target(done) {
                cues.announceSet(target(done + 1))
            }
            // Pausa prima dell'ultima serie: avviso e presentazione del prossimo esercizio (o fine della giornata).
            if case .restStarted = cue, case .resting(let done, _) = engine.phase,
               WorkoutListLogic.isRestBeforeLastSet(afterSet: done, totalSets: totalSets) {
                cues.announceLastSet(lastSetNotice())
            }
            switch cue {
            case .restStarted, .sessionFinished: motion.pauseCounting()
            case .restEnded: motion.beginSet()
            default: break
            }
        }
        phase = engine.phase
        currentReps = engine.currentReps
        records = engine.records
        while metrics.count < records.count {
            metrics.append((motion.averagePeak, motion.lowConfidence))
        }
    }

    /// La sessione appena svolta nel formato del motore adattivo (piano Full).
    func sample() -> SessionSample {
        SessionSample(date: startedAt, weightKg: targets.map(\.weightKg).max() ?? weightKg, sets: records.enumerated().map { i, r in
            SessionSetSample(doneReps: r.doneReps, plannedReps: r.plannedReps, stoppedEarly: r.stoppedEarly,
                             averagePeak: i < metrics.count ? metrics[i].peak : 0)
        })
    }

    /// Record da salvare nello storico (solo con il consenso ai dati sulla salute).
    func makeRecord() -> WorkoutSessionRecord {
        let session = WorkoutSessionRecord(startedAt: startedAt, endedAt: Date(), limb: position.rawValue,
                                           plannedSets: totalSets, plannedReps: targets[0].reps, restSeconds: restSeconds,
                                           exerciseID: exercise?.id ?? "", exerciseName: exercise?.name ?? "", weightKg: weightKg)
        for (i, r) in records.enumerated() {
            let m = i < metrics.count ? metrics[i] : (peak: 0.0, low: false)
            session.sets.append(SetLogRecord(number: r.number, plannedReps: r.plannedReps, doneReps: r.doneReps,
                                             stoppedEarly: r.stoppedEarly, durationSeconds: r.durationSeconds,
                                             averagePeak: m.peak, lowConfidence: m.low, weightKg: target(r.number).weightKg))
        }
        return session
    }
}
