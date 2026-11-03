import AVFoundation
import CoreHaptics
import UIKit
import MyGymHelperCore

struct CueOptions {
    var sound = true
    var voice = true
    var haptics = true
    var countReps = false

    @MainActor
    static func fromDefaults() -> CueOptions {
        let d = UserDefaults.standard
        func flag(_ key: String) -> Bool { d.object(forKey: key) as? Bool ?? true }
        return CueOptions(sound: flag("cue.sound"), voice: flag("cue.voice"), haptics: flag("cue.haptics"),
                          countReps: AppSettings.shared.voiceCountReps)
    }
}

/// Testo localizzato da una chiave calcolata a runtime (es. "voice.rest.2 %lld").
func localized(_ key: String, _ args: CVarArg...) -> String {
    let format = NSLocalizedString(key, comment: "")
    return args.isEmpty ? format : String(format: format, arguments: args)
}

/// Trasforma gli avvisi della sessione in vibrazione, suono e voce (come CueService.kt su Android).
/// Le frasi cambiano ogni volta (piu' varianti per avviso); la voce e' quella scelta nelle impostazioni.
@MainActor
final class CueService {
    var options: CueOptions
    private let voice = VoiceEngine.shared
    private let beeper = Beeper()
    private let haptics = Haptics()
    private var lastVariant: [String: Int] = [:]

    init(options: CueOptions = CueOptions()) {
        self.options = options
        voice.applyVoice()
    }

    /// `currentSet` = serie in corso dopo l'avviso; `totalSets` serve per le frasi "ultima serie".
    func play(_ cue: SessionCue, currentSet: Int, totalSets: Int) {
        if options.haptics { haptics.play(for: cue) }
        if options.sound { beeper.beep(duration: 0.25) }
        // Gli avvisi di partenza della serie interrompono quello che la voce sta ancora dicendo (es. l'annuncio
        // lungo prima dell'ultima serie): devono arrivare in tempo.
        if options.voice, let text = phrase(for: cue, currentSet: currentSet, totalSets: totalSets) {
            voice.speak(text, flush: interrupts(cue))
        }
    }

    /// Avvisi con la priorita': conto alla rovescia di fine pausa e inizio della serie.
    private func interrupts(_ cue: SessionCue) -> Bool {
        switch cue {
        case .restCountdown, .restEnded, .setStarted: return true
        default: return false
        }
    }

    /// Prova degli avvisi dalle impostazioni: suono, vibrazione e voce come a fine serie.
    func preview() { play(.targetReached, currentSet: 1, totalSets: 3) }

    /// Ripetizione contata: numero a voce (se attivo) e "ancora una!" prima dell'ultima.
    func repCounted(_ count: Int, target: Int) {
        guard options.voice, count > 0, count < target else { return }
        let text: String
        if target >= 4 && count == target - 1 {
            text = options.countReps ? "\(count). " + pick("voice.oneMore") : pick("voice.oneMore")
        } else if options.countReps {
            text = "\(count)"
        } else { return }
        voice.speak(text, flush: true)
    }

    /// Serie diverse: annuncio di ripetizioni e peso della prossima serie (a inizio pausa, dopo l'avviso della pausa).
    /// Solo voce: suono e vibrazione sono gia' quelli della pausa.
    func announceSet(_ target: SetTarget) {
        guard options.voice else { return }
        let separator = Character(Locale.current.decimalSeparator ?? ",")
        let text = target.weightKg > 0
            ? localized("voice.nextSet %lld %@", target.reps, WeightInput.format(target.weightKg, separator: separator))
            : localized("voice.nextSetBodyweight %lld", target.reps)
        voice.speak(text)
    }

    /// Pausa prima dell'ultima serie: avvisa che la prossima e' l'ultima e presenta il prossimo esercizio dell'elenco
    /// (nome, muscoli, attrezzo, dove mettere il telefono); se era l'ultimo esercizio, chiude la giornata.
    /// Solo voce: suono e vibrazione sono gia' quelli della pausa.
    func announceLastSet(_ notice: LastSetNotice) {
        guard options.voice else { return }
        let text: String
        switch notice {
        case .endOfDay:
            text = localized("voice.lastOfDay")
        case .lastSetOnly:
            text = pick("voice.lastSetNotice")
        case .nextExercise(let ex, let position):
            var parts = [pick("voice.lastSetNotice"), localized("voice.nextExercise %@", ex.name)]
            if !ex.primary.isEmpty {
                parts.append(localized("voice.nextMuscles %@", ex.primary.map(\.title).joined(separator: ", ")))
            }
            if ex.equipment.lowercased() == "bodyweight" {
                parts.append(localized("voice.nextBodyweight"))
            } else if !ex.equipment.trimmingCharacters(in: .whitespaces).isEmpty {
                let name = Bundle.main.localizedString(forKey: "equipment.\(ex.equipment)", value: ex.equipment, table: nil)
                parts.append(localized("voice.nextEquipment %@", name))
            }
            parts.append(localized("voice.nextPosition %@", localized("voice.position.\(position.rawValue)")))
            text = parts.joined(separator: " ")
        }
        voice.speak(text)
    }

    /// Conto alla rovescia prima della prima serie (dopo la spiegazione).
    func countdown(_ n: Int) {
        if options.haptics { haptics.tick() }
        if options.voice { voice.speak("\(n)", flush: true) } else if options.sound { beeper.beep(duration: 0.12) }
    }

    /// Legge la spiegazione: nome, passaggi (id "step-i" per evidenziarli a schermo) e chiusura.
    /// `onDone` arriva a fine lettura (subito se la voce e' spenta o non ci sono passaggi).
    func explain(_ exercise: CatalogExercise, onDone: @escaping () -> Void) {
        guard options.voice, !exercise.steps.isEmpty else { onDone(); return }
        voice.stop()
        voice.speak(localized("voice.explainIntro %@", exercise.name), id: "intro")
        for (i, step) in exercise.steps.enumerated() { voice.speak(step, id: "step-\(i)") }
        voice.speak(pick("voice.ready"), id: "ready", onDone: onDone)
    }

    func stopSpeaking() { voice.stop() }

    func shutdown() { voice.stop(); AudioSessionHelper.deactivate() }

    /// Una delle varianti "chiave.1", "chiave.2"... diversa dalla precedente. `suffix` = parametri della chiave (" %lld").
    private func pick(_ base: String, suffix: String = "", _ args: CVarArg...) -> String {
        let variants = (1...5).map { "\(base).\($0)\(suffix)" }.filter { NSLocalizedString($0, comment: "") != $0 }
        guard !variants.isEmpty else { return String(format: NSLocalizedString(base + suffix, comment: ""), arguments: args) }
        var i = Int.random(in: 0..<variants.count)
        if variants.count > 1, lastVariant[base] == i { i = (i + 1) % variants.count }
        lastVariant[base] = i
        return String(format: NSLocalizedString(variants[i], comment: ""), arguments: args)
    }

    private func setPhrase(_ set: Int, _ totalSets: Int) -> String {
        if totalSets > 1 && set == totalSets { return pick("voice.lastSet") }
        if set == 1 { return pick("voice.firstSet") }
        return localized("voice.setNumber %lld %lld", set, totalSets) + " " + pick("voice.go")
    }

    private func phrase(for cue: SessionCue, currentSet: Int, totalSets: Int) -> String? {
        switch cue {
        case .setStarted(let set): return setPhrase(set, totalSets)
        case .targetReached: return pick("voice.target")
        case .restStarted(let seconds): return pick("voice.rest", suffix: " %lld", seconds)
        case .restCountdown(let n): return "\(n)"
        case .restEnded: return setPhrase(currentSet, totalSets)   // fine pausa: inizia la serie successiva
        case .sessionFinished: return pick("voice.finished")
        }
    }
}

/// Bip generato in memoria e riprodotto con la sessione audio "playback": si sente anche con l'interruttore
/// silenzioso attivo (i suoni di sistema, usati prima, in silenzioso non suonano). Segue il volume multimediale.
@MainActor
final class Beeper {
    private var player: AVAudioPlayer?
    private var cached: [Double: Data] = [:]

    func beep(duration: Double) {
        let data = cached[duration] ?? Self.tone(frequency: 880, duration: duration)
        cached[duration] = data
        AudioSessionHelper.activate()
        player = try? AVAudioPlayer(data: data)
        player?.volume = 1
        player?.play()
    }

    /// File WAV (PCM 16 bit, mono, 44,1 kHz) con una sinusoide e attacco/rilascio morbidi.
    static func tone(frequency: Double, duration: Double, sampleRate: Double = 44_100) -> Data {
        let n = Int(duration * sampleRate)
        var pcm = Data(capacity: n * 2)
        for i in 0..<n {
            let t = Double(i) / sampleRate
            let envelope = min(1, min(t / 0.01, (duration - t) / 0.03))
            let v = Int16(max(-1, min(1, sin(2 * .pi * frequency * t) * 0.8 * envelope)) * Double(Int16.max))
            withUnsafeBytes(of: v.littleEndian) { pcm.append(contentsOf: $0) }
        }
        var wav = Data()
        func add(_ s: String) { wav.append(contentsOf: Array(s.utf8)) }
        func add32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { wav.append(contentsOf: $0) } }
        func add16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { wav.append(contentsOf: $0) } }
        add("RIFF"); add32(UInt32(36 + pcm.count)); add("WAVE")
        add("fmt "); add32(16); add16(1); add16(1); add32(UInt32(sampleRate)); add32(UInt32(sampleRate) * 2); add16(2); add16(16)
        add("data"); add32(UInt32(pcm.count)); wav.append(pcm)
        return wav
    }
}

/// Vibrazioni lunghe con Core Haptics (piu' percepibili con il telefono fissato al braccio o alla gamba);
/// se il telefono non le supporta si usano le vibrazioni di sistema.
@MainActor
final class Haptics {
    private var engine: CHHapticEngine?
    private let supported = CHHapticEngine.capabilitiesForHardware().supportsHaptics

    func play(for cue: SessionCue) {
        switch cue {
        case .setStarted: pulses([0.3])
        case .targetReached, .restEnded, .sessionFinished: pulses([0.25, 0.25])
        case .restStarted: pulses([0.4, 0.4])
        case .restCountdown: pulses([0.08])
        }
    }

    func tick() { pulses([0.08]) }

    /// Impulsi continui della durata indicata, separati da 0,15 s.
    private func pulses(_ durations: [Double]) {
        guard supported else {
            UINotificationFeedbackGenerator().notificationOccurred(durations.count > 1 ? .warning : .success)
            return
        }
        do {
            if engine == nil {
                let e = try CHHapticEngine()
                e.resetHandler = { [weak e] in try? e?.start() }
                engine = e
            }
            try engine?.start()
            var time = 0.0
            let events = durations.map { d -> CHHapticEvent in
                defer { time += d + 0.15 }
                return CHHapticEvent(eventType: .hapticContinuous, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
                ], relativeTime: time, duration: d)
            }
            let player = try engine?.makePlayer(with: CHHapticPattern(events: events, parameters: []))
            try player?.start(atTime: CHHapticTimeImmediate)
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}
