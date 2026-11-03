import Foundation

/// Dove si fissa il telefono. Il movimento e' molto diverso a seconda del segmento del corpo: un curl muove
/// l'avambraccio ma non il braccio, una leg extension muove lo stinco ma non la coscia. Per ogni posizione si puo'
/// fare una calibrazione (salvata) e regolare a mano la sensibilita'. Port di `android/core/.../Calibration.kt`.
public enum SensorPosition: String, CaseIterable, Sendable, Codable {
    case armUpper      // braccio, sopra il gomito (bicipite/tricipite)
    case armForearm    // avambraccio
    case legThigh      // coscia
    case legShin       // stinco/caviglia
    case abs           // addome

    public var isLowerBody: Bool { self == .legThigh || self == .legShin }

    public static func from(_ raw: String?) -> SensorPosition? { raw.flatMap(SensorPosition.init(rawValue:)) }
    /// Sessioni salvate prima delle posizioni: "arm" -> braccio, "leg" -> coscia.
    public static func fromLegacy(_ raw: String?) -> SensorPosition { from(raw) ?? (raw == "leg" ? .legThigh : .armUpper) }
}

/// Esito di una calibrazione: segnale che funziona meglio e ampiezza tipica di una ripetizione.
public struct CalibrationResult: Sendable, Equatable {
    public let signal: RepSignal
    public let typicalSwing: Double      // mediana delle ampiezze delle ripetizioni fatte in prova
    public let reps: Int
    public let repSeconds: Double        // durata media di una ripetizione
    public let consistency: Double       // 0..1: quanto sono regolari le ripetizioni

    public static let minConsistency = 0.4
    public var isReliable: Bool { consistency >= Self.minConsistency }
    public func toTuning(sensitivity: Double = 1, now: Double = 0) -> PositionTuning {
        PositionTuning(sensitivity: sensitivity, typicalSwing: typicalSwing, signal: signal, calibratedAt: now)
    }
}

/// Impostazioni di conteggio di una posizione: calibrazione (facoltativa) e sensibilita' manuale.
/// Senza calibrazione e con sensibilita' 1 si usano le soglie predefinite del RepCounter.
public struct PositionTuning: Sendable, Equatable, Codable {
    public var sensitivity: Double        // 0,5 (meno sensibile) .. 2,0 (piu' sensibile)
    public var typicalSwing: Double?      // ampiezza tipica misurata in calibrazione
    public var signal: RepSignal?         // segnale scelto in calibrazione
    public var calibratedAt: Double       // secondi dal 1970; 0 = mai calibrata

    public static let minSensitivity = 0.5
    public static let maxSensitivity = 2.0
    // Limiti di sicurezza: sotto questi valori il tremolio e il rumore dei sensori verrebbero contati.
    public static let minTilt = 0.10
    public static let maxTilt = 1.2
    public static let minTranslation = 0.04
    public static let maxTranslation = 0.8

    public init(sensitivity: Double = 1, typicalSwing: Double? = nil, signal: RepSignal? = nil, calibratedAt: Double = 0) {
        self.sensitivity = sensitivity; self.typicalSwing = typicalSwing; self.signal = signal; self.calibratedAt = calibratedAt
    }

    public var isCalibrated: Bool { typicalSwing != nil && signal != nil }
    public var isDefault: Bool { !isCalibrated && sensitivity == 1 }

    /// Soglie del contatore per questa posizione: ampiezza minima = 55% dell'ampiezza calibrata, divisa per la sensibilita'.
    public func config(base: RepCounterConfig = RepCounterConfig()) -> RepCounterConfig {
        let s = Self.clamp(sensitivity, Self.minSensitivity, Self.maxSensitivity)
        var tilt = base.minTiltSwing
        var translation = base.minTranslationSwing
        if let swing = typicalSwing, let signal {
            let threshold = base.adaptiveFraction * swing
            if signal == .tilt { tilt = threshold } else { translation = threshold }
        }
        var c = base
        c.minTiltSwing = Self.clamp(tilt / s, Self.minTilt, Self.maxTilt)
        c.minTranslationSwing = Self.clamp(translation / s, Self.minTranslation, Self.maxTranslation)
        c.forcedSignal = signal
        return c
    }

    static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(max(v, lo), hi) }
}

/// Calibrazione: l'utente fa alcune ripetizioni complete nella posizione scelta. Si usano soglie molto basse per
/// vedere anche i movimenti piccoli, poi dall'ampiezza mediana si ricavano le soglie da usare in allenamento.
public struct RepCalibrator {
    public let targetReps: Int
    private let minReps: Int
    private var counter = RepCounter(config: RepCounterConfig(minTiltSwing: 0.12, minTranslationSwing: 0.05))

    public init(targetReps: Int = 5, minReps: Int = 3) { self.targetReps = targetReps; self.minReps = minReps }

    public var repsDetected: Int { counter.count }
    public var signal: RepSignal? { counter.signal }
    /// Vero quando le ripetizioni richieste sono state fatte.
    public var isComplete: Bool { counter.count >= targetReps }

    /// Un campione dei sensori (come RepCounter.process). Restituisce true quando si completa una ripetizione.
    @discardableResult
    public mutating func process(t: Double, gravity: Vector3, linear: Vector3) -> Bool {
        counter.process(t: t, gravity: gravity, linear: linear) != nil
    }

    /// L'esito, se ci sono abbastanza ripetizioni; altrimenti nil.
    public func result() -> CalibrationResult? {
        let events = counter.events
        guard let signal = counter.signal, events.count >= minReps else { return nil }
        let amplitudes = events.map(\.amplitude).sorted()
        let n = amplitudes.count
        let median = n % 2 == 1 ? amplitudes[n / 2] : (amplitudes[n / 2 - 1] + amplitudes[n / 2]) / 2
        let gaps = zip(events, events.dropFirst()).map { $1.timestamp - $0.timestamp }
        let period = gaps.isEmpty ? 0 : gaps.reduce(0, +) / Double(gaps.count)
        return CalibrationResult(signal: signal, typicalSwing: max(median, 1e-3), reps: n, repSeconds: period,
                                 consistency: min(1, max(0, counter.signalConfidence)))
    }
}
