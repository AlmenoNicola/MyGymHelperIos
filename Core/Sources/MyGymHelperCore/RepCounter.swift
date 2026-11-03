import Foundation

/// Contatore di ripetizioni "ad arco completo" (sostituisce il RepDetector a picchi, troppo sensibile).
/// Port 1:1 di `android/core/.../RepCounter.kt`: le due versioni devono restare uguali (stessi test).
///
/// Una ripetizione vale solo quando l'arto fa **due movimenti**: si allontana dalla posizione di partenza di
/// almeno una certa ampiezza e poi torna indietro. Movimenti piccoli, scosse e vibrazioni non contano.
///
/// Il segnale e' una "posizione" dell'arto, scelta in calibrazione (primi secondi di movimento):
/// - INCLINAZIONE (preferita): direzione della gravita' vista dal telefono, proiettata sull'asse in cui varia di piu'.
///   Funziona quando l'arto ruota (curl, alzate, squat con il telefono sulla coscia, leg extension...).
/// - SPOSTAMENTO: se l'arto quasi non ruota (es. panca), si integra due volte l'accelerazione lineare lungo
///   l'asse principale con integratori "a perdita" che eliminano la deriva.
public struct RepCounterConfig: Sendable, Equatable {
    public var calibrationSeconds = 2.0    // movimento minimo osservato prima di scegliere segnale e asse
    public var lowPassHz = 2.5             // filtro sul segnale di posizione
    public var minTiltSwing = 0.30         // ampiezza minima in INCLINAZIONE (variazione del versore gravita', ~17-20 gradi)
    public var minTranslationSwing = 0.12  // ampiezza minima in SPOSTAMENTO (metri stimati)
    public var adaptiveFraction = 0.55     // dopo 2 ripetizioni: soglia = 55% dell'ampiezza tipica
    public var retreatFraction = 0.20      // ritorno dal punto lontano che conferma l'inversione
    public var returnFraction = 0.35       // la ripetizione conta quando si torna entro il 35% dell'arco dalla partenza
    public var minRepSeconds = 0.8         // tempo minimo tra due ripetizioni
    public var minMovementSeconds = 0.5    // un'andata e ritorno piu' rapida e' un urto, non una ripetizione
    public var forcedSignal: RepSignal?    // segnale imposto dalla calibrazione della posizione (nil = scelta automatica)

    public init(calibrationSeconds: Double = 2.0, lowPassHz: Double = 2.5, minTiltSwing: Double = 0.30,
                minTranslationSwing: Double = 0.12, adaptiveFraction: Double = 0.55, retreatFraction: Double = 0.20,
                returnFraction: Double = 0.35, minRepSeconds: Double = 0.8, minMovementSeconds: Double = 0.5,
                forcedSignal: RepSignal? = nil) {
        self.calibrationSeconds = calibrationSeconds; self.lowPassHz = lowPassHz; self.minTiltSwing = minTiltSwing
        self.minTranslationSwing = minTranslationSwing; self.adaptiveFraction = adaptiveFraction
        self.retreatFraction = retreatFraction; self.returnFraction = returnFraction
        self.minRepSeconds = minRepSeconds; self.minMovementSeconds = minMovementSeconds; self.forcedSignal = forcedSignal
    }
}

public enum RepSignal: String, Sendable, Equatable, CaseIterable, Codable { case tilt = "TILT", translation = "TRANSLATION" }

/// Una ripetizione completata: ampiezza dell'arco e velocita' massima (indice di fatica: cala se si rallenta).
public struct RepCount: Sendable, Equatable {
    public let index: Int
    public let timestamp: Double
    public let amplitude: Double
    public let peakSpeed: Double
}

public struct RepCounter {
    private let config: RepCounterConfig
    public private(set) var count = 0
    public private(set) var events: [RepCount] = []
    public private(set) var signal: RepSignal?
    public var isCalibrated: Bool { signal != nil }

    // Calibrazione
    private struct Sample { let t: Double; let gravity: Vector3; let linear: Vector3 }
    private var window: [Sample] = []
    private var axis: Vector3?

    // Segnale
    private var lastT: Double?
    private var filtered: Double?
    private var accMean = 0.0
    private var velocity = 0.0
    private var position = 0.0

    // Macchina a stati
    private enum Phase { case away, back }
    private var phase = Phase.away
    private var rest: Double?
    private var direction = 0                 // +1 / -1: verso dell'allontanamento (fissato alla prima ripetizione)
    private var extreme: Double?
    private var lastRepTime: Double?
    private var speedMax = 0.0
    private var startT: Double?
    private var leftRestT: Double?

    public init(config: RepCounterConfig = RepCounterConfig()) { self.config = config }

    private var minSwing: Double {
        let base = signal == .translation ? config.minTranslationSwing : config.minTiltSwing
        if events.count < 2 { return base }
        let last = events.suffix(5).map(\.amplitude).sorted()
        let typical = last[last.count / 2]
        return max(base, config.adaptiveFraction * typical)
    }

    /// Un campione dei sensori: `gravity` = direzione della gravita' vista dal telefono (in g, anche non unitaria),
    /// `linear` = accelerazione senza gravita' (in g), `t` in secondi. Restituisce la ripetizione appena completata.
    @discardableResult
    public mutating func process(t: Double, gravity: Vector3, linear: Vector3) -> RepCount? {
        if signal == nil {
            window.append(Sample(t: t, gravity: gravity, linear: linear))
            while window.count > 1, t - window[0].t > config.calibrationSeconds * 2.5 { window.removeFirst() }
            if t - window[0].t < config.calibrationSeconds { return nil }
            if !calibrate() { return nil }
            // Si riesamina la finestra: la prima ripetizione, se gia' iniziata, viene contata.
            var last: RepCount?
            let replay = window; window.removeAll()
            for s in replay { if let r = step(t: s.t, gravity: s.gravity, linear: s.linear) { last = r } }
            return last
        }
        return step(t: t, gravity: gravity, linear: linear)
    }

    /// Sceglie il segnale: inclinazione se l'arto ruota abbastanza, altrimenti spostamento.
    private mutating func calibrate() -> Bool {
        let g = window.map { Self.unit($0.gravity) }
        let tiltAxis = PrincipalAxis.estimate(from: g)
        var tiltRange = 0.0
        if let a = tiltAxis {
            let proj = g.map { $0.dot(a) }
            tiltRange = (proj.max() ?? 0) - (proj.min() ?? 0)
        }
        let linMax = window.map(\.linear.length).max() ?? 0
        if tiltRange < config.minTiltSwing * 0.5 && linMax < 0.12 { return false }   // ancora fermo: si aspetta
        // Con una calibrazione salvata per la posizione si usa il segnale gia' scelto; altrimenti si decide ora.
        let useTilt: Bool
        switch config.forcedSignal {
        case .tilt?: useTilt = tiltAxis != nil
        case .translation?: useTilt = false
        case nil: useTilt = tiltAxis != nil && tiltRange >= config.minTiltSwing * 0.8
        }
        if useTilt, let a = tiltAxis {
            signal = .tilt; axis = a
        } else {
            signal = .translation
            let ax = PrincipalAxis.estimate(from: window.map(\.linear)) ?? Vector3(0, 0, 1)
            axis = ax
            accMean = window.reduce(0) { $0 + $1.linear.dot(ax) * 9.80665 } / Double(window.count)   // niente transitorio iniziale
        }
        return true
    }

    private static func unit(_ v: Vector3) -> Vector3 { let l = max(v.length, 1e-9); return Vector3(v.x / l, v.y / l, v.z / l) }

    private mutating func step(t: Double, gravity: Vector3, linear: Vector3) -> RepCount? {
        guard let a = axis else { return nil }
        let dt = lastT.map { max(t - $0, 1e-4) } ?? 0.02
        lastT = t
        let raw: Double
        if signal == .tilt {
            raw = Self.unit(gravity).dot(a)
        } else {
            // Doppia integrazione "a perdita" (passa-alto): niente deriva, conserva i movimenti di 0,5-4 s.
            let acc = linear.dot(a) * 9.80665
            accMean += (acc - accMean) * (1 - exp(-dt / 2.0))
            velocity = velocity * exp(-dt / 1.2) + (acc - accMean) * dt
            position = position * exp(-dt / 1.6) + velocity * dt
            raw = position
        }
        let rc = 1 / (2 * Double.pi * config.lowPassHz)
        let prev = filtered
        let x = prev.map { $0 + (dt / (rc + dt)) * (raw - $0) } ?? raw
        let speed = prev.map { abs(x - $0) / dt } ?? 0
        filtered = x
        // In SPOSTAMENTO gli integratori hanno bisogno di circa 1 s per assestarsi.
        let start: Double
        if let s = startT { start = s } else { startT = t; start = t }
        if signal == .translation && t - start < 1.0 { return nil }
        return advance(t: t, x: x, speed: speed)
    }

    private mutating func advance(t: Double, x: Double, speed: Double) -> RepCount? {
        guard let r = rest else { rest = x; extreme = x; return nil }
        speedMax = max(speedMax, speed)
        let threshold = minSwing
        let dir = Double(direction)
        switch phase {
        case .away:
            if abs(x - r) < 0.15 * threshold || leftRestT == nil { leftRestT = t }
            let e = extreme ?? x
            let dist = x - r
            if direction == 0 {
                if abs(dist) > abs(e - r) { extreme = x }
            } else if dist * dir > (e - r) * dir {
                extreme = x                                   // si allontana ancora
            } else if dist * dir < 0 {
                rest = x; extreme = x                         // va oltre la partenza: la partenza si sposta
                return nil
            }
            let ex = extreme ?? x
            let swing = abs(ex - r)
            let retreat = abs(x - ex)
            if swing >= threshold && retreat >= config.retreatFraction * swing {
                if direction == 0 { direction = ex > r ? 1 : -1 }
                phase = .back
            } else if swing < threshold && abs(x - r) < 0.3 * swing {
                extreme = x                                   // piccolo movimento tornato indietro: si ignora
            }
        case .back:
            let ex = extreme ?? x
            let swing = abs(ex - r)
            if (x - r) * dir > (ex - r) * dir { extreme = x; return nil }   // riprende ad allontanarsi
            if abs(x - r) <= config.returnFraction * swing {
                let farEnough = lastRepTime.map { t - $0 >= config.minRepSeconds } ?? true
                let slowEnough = t - (leftRestT ?? t) >= config.minMovementSeconds
                phase = .away
                extreme = x
                leftRestT = t
                if !farEnough || !slowEnough { speedMax = 0; return nil }
                count += 1
                lastRepTime = t
                let ev = RepCount(index: count, timestamp: t, amplitude: swing, peakSpeed: speedMax)
                events.append(ev)
                speedMax = 0
                rest = r + (x - r) * 0.5                     // la partenza segue lentamente la posizione reale
                return ev
            }
        }
        return nil
    }

    /// 0..1: bassa se ampiezze e ritmo sono molto irregolari (telefono non fissato bene).
    public var signalConfidence: Double {
        if events.count < 3 { return 1 }
        func cv(_ xs: [Double]) -> Double {
            let m = xs.reduce(0, +) / Double(xs.count)
            if m <= 0 { return 1 }
            return (xs.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(xs.count)).squareRoot() / m
        }
        let amps = events.map(\.amplitude)
        let gaps = zip(events, events.dropFirst()).map { $1.timestamp - $0.timestamp }
        return max(0, min(1, 1 - max(cv(amps), cv(gaps))))
    }

    /// Velocita' massima media delle ripetizioni (per i consigli sulla fatica: si confronta solo nella stessa sessione).
    public var averagePeakSpeed: Double { events.isEmpty ? 0 : events.reduce(0) { $0 + $1.peakSpeed } / Double(events.count) }
}
