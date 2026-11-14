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
/// - ROTAZIONE ORIZZONTALE (YAW): rotazione attorno all'asse verticale, dal giroscopio (twist, woodchop...).
///   L'inclinazione non la vede: girando attorno alla verticale la gravita' non cambia.
///
/// Asse del movimento (novembre 2026, `MovementAxis`): ogni esercizio dice se conta il movimento su/giu' o
/// sinistra/destra, sempre rispetto al pavimento (gravita'), qualunque sia l'orientamento del telefono:
/// - SU/GIU': inclinazione oppure spostamento lungo la verticale; le rotazioni attorno alla verticale non contano.
/// - SINISTRA/DESTRA: rotazione attorno alla verticale oppure spostamento nel piano orizzontale.
/// - AVANTI/INDIETRO (9 novembre 2026): solo spostamento nel piano orizzontale, mai la rotazione (swing, slitta...).
/// Senza asse (nil) si sceglie da soli, come prima.
public struct RepCounterConfig: Sendable, Equatable {
    public var calibrationSeconds = 2.0    // movimento minimo osservato prima di scegliere segnale e asse
    public var lowPassHz = 2.5             // filtro sul segnale di posizione
    public var minTiltSwing = 0.30         // ampiezza minima in INCLINAZIONE (variazione del versore gravita', ~17-20 gradi)
    public var minTranslationSwing = 0.12  // ampiezza minima in SPOSTAMENTO (metri stimati)
    public var minYawSwing = 0.35          // ampiezza minima in ROTAZIONE ORIZZONTALE (radianti stimati, ~20 gradi)
    public var adaptiveFraction = 0.55     // dopo 2 ripetizioni: soglia = 55% dell'ampiezza tipica
    public var retreatFraction = 0.20      // ritorno dal punto lontano che conferma l'inversione
    public var returnFraction = 0.35       // la ripetizione conta quando si torna entro il 35% dell'arco dalla partenza
    public var minRepSeconds = 0.8         // tempo minimo tra due ripetizioni
    public var minMovementSeconds = 0.5    // un'andata e ritorno piu' rapida e' un urto, non una ripetizione
    public var forcedSignal: RepSignal?    // segnale imposto dalla calibrazione della posizione (nil = scelta automatica)
    public var axis: MovementAxis?         // asse del movimento dell'esercizio (nil = scelta automatica, come prima)

    public init(calibrationSeconds: Double = 2.0, lowPassHz: Double = 2.5, minTiltSwing: Double = 0.30,
                minTranslationSwing: Double = 0.12, minYawSwing: Double = 0.35, adaptiveFraction: Double = 0.55,
                retreatFraction: Double = 0.20, returnFraction: Double = 0.35, minRepSeconds: Double = 0.8,
                minMovementSeconds: Double = 0.5, forcedSignal: RepSignal? = nil, axis: MovementAxis? = nil) {
        self.calibrationSeconds = calibrationSeconds; self.lowPassHz = lowPassHz; self.minTiltSwing = minTiltSwing
        self.minTranslationSwing = minTranslationSwing; self.minYawSwing = minYawSwing
        self.adaptiveFraction = adaptiveFraction
        self.retreatFraction = retreatFraction; self.returnFraction = returnFraction
        self.minRepSeconds = minRepSeconds; self.minMovementSeconds = minMovementSeconds; self.forcedSignal = forcedSignal
        self.axis = axis
    }
}

public enum RepSignal: String, Sendable, Equatable, CaseIterable, Codable {
    case tilt = "TILT", translation = "TRANSLATION", yaw = "YAW"
}

/// Direzione del movimento che si conta, rispetto al pavimento. `rawValue` e' il valore salvato (elenchi e catalogo),
/// uguale su Android (MovementAxis in RepCounter.kt).
public enum MovementAxis: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    case upDown, leftRight, forwardBack

    /// Asse successivo (pulsante "cambia" durante il conteggio): su/giù → sinistra/destra → avanti/indietro → su/giù.
    public var other: MovementAxis {
        switch self {
        case .upDown: return .leftRight
        case .leftRight: return .forwardBack
        case .forwardBack: return .upDown
        }
    }
    /// Chiave del testo: "movement.upDown" / "movement.leftRight".
    public var titleKey: String { "movement.\(rawValue)" }
}

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
    /// Asse del movimento usato (nil = scelta automatica).
    public var axisMode: MovementAxis? { config.axis }

    // Calibrazione
    private struct Sample { let t: Double; let gravity: Vector3; let linear: Vector3; let rotation: Vector3? }
    private var window: [Sample] = []
    private var axis: Vector3?

    /// Come si ricava lo spostamento dall'accelerazione lineare.
    private enum Projection { case principal, vertical, horizontal }
    private var projection = Projection.principal

    // Segnale
    private var lastT: Double?
    private var filtered: Double?
    private var accMean = 0.0
    private var velocity = 0.0
    private var position = 0.0
    private var yawMean = 0.0
    private var yawAngle = 0.0

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
        let base: Double
        switch signal {
        case .translation?: base = config.minTranslationSwing
        case .yaw?: base = config.minYawSwing
        default: base = config.minTiltSwing
        }
        if events.count < 2 { return base }
        let last = events.suffix(5).map(\.amplitude).sorted()
        let typical = last[last.count / 2]
        return max(base, config.adaptiveFraction * typical)
    }

    /// Un campione dei sensori: `gravity` = direzione della gravita' vista dal telefono (in g, anche non unitaria),
    /// `linear` = accelerazione senza gravita' (in g), `rotation` = velocita' angolare del giroscopio (rad/s, nil se
    /// manca), `t` in secondi. Restituisce la ripetizione appena completata.
    @discardableResult
    public mutating func process(t: Double, gravity: Vector3, linear: Vector3, rotation: Vector3? = nil) -> RepCount? {
        if signal == nil {
            window.append(Sample(t: t, gravity: gravity, linear: linear, rotation: rotation))
            while window.count > 1, t - window[0].t > config.calibrationSeconds * 2.5 { window.removeFirst() }
            if t - window[0].t < config.calibrationSeconds { return nil }
            if !calibrate() { return nil }
            // Si riesamina la finestra: la prima ripetizione, se gia' iniziata, viene contata.
            var last: RepCount?
            let replay = window; window.removeAll()
            for s in replay {
                if let r = step(t: s.t, gravity: s.gravity, linear: s.linear, rotation: s.rotation) { last = r }
            }
            return last
        }
        return step(t: t, gravity: gravity, linear: linear, rotation: rotation)
    }

    /// Sceglie il segnale in base all'asse del movimento (o da solo, senza asse).
    private mutating func calibrate() -> Bool {
        switch config.axis {
        case nil: return calibrateAuto()
        case .upDown?: return calibrateUpDown()
        case .leftRight?: return calibrateLeftRight()
        case .forwardBack?: return calibrateForwardBack()
        }
    }

    /// Asse in cui varia di piu' la direzione della gravita' e ampiezza della variazione.
    private func tilt() -> (axis: Vector3?, range: Double) {
        let g = window.map { Self.unit($0.gravity) }
        let tiltAxis = PrincipalAxis.estimate(from: g)
        var tiltRange = 0.0
        if let a = tiltAxis {
            let proj = g.map { $0.dot(a) }
            tiltRange = (proj.max() ?? 0) - (proj.min() ?? 0)
        }
        return (tiltAxis, tiltRange)
    }

    private func useTilt(_ tiltAxis: Vector3?, _ tiltRange: Double) -> Bool {
        switch config.forcedSignal {
        case .tilt?: return tiltAxis != nil
        case .translation?: return false
        default: return tiltAxis != nil && tiltRange >= config.minTiltSwing * 0.8
        }
    }

    /// Senza asse: inclinazione se l'arto ruota abbastanza, altrimenti spostamento lungo l'asse principale.
    private mutating func calibrateAuto() -> Bool {
        let (tiltAxis, tiltRange) = tilt()
        let linMax = window.map(\.linear.length).max() ?? 0
        if tiltRange < config.minTiltSwing * 0.5 && linMax < 0.12 { return false }   // ancora fermo: si aspetta
        // Con una calibrazione salvata per la posizione si usa il segnale gia' scelto; altrimenti si decide ora.
        if useTilt(tiltAxis, tiltRange), let a = tiltAxis {
            signal = .tilt; axis = a
        } else {
            useTranslation(.principal, PrincipalAxis.estimate(from: window.map(\.linear)) ?? Vector3(0, 0, 1))
        }
        return true
    }

    /// Su/giu': inclinazione (le rotazioni attorno alla verticale non cambiano la gravita' e quindi non contano)
    /// oppure spostamento lungo la verticale.
    private mutating func calibrateUpDown() -> Bool {
        let (tiltAxis, tiltRange) = tilt()
        let verticalMax = window.map { abs($0.linear.dot(Self.unit($0.gravity))) }.max() ?? 0
        if tiltRange < config.minTiltSwing * 0.5 && verticalMax < 0.12 { return false }
        if useTilt(tiltAxis, tiltRange), let a = tiltAxis { signal = .tilt; axis = a }
        else { useTranslation(.vertical, Vector3(0, 0, 1)) }
        return true
    }

    /// Sinistra/destra: rotazione attorno alla verticale (giroscopio) se c'e' ed e' abbastanza ampia, altrimenti
    /// spostamento nel piano orizzontale, lungo la direzione in cui varia di piu'. La calibrazione della posizione
    /// (fatta su/giu') non si usa per scegliere il segnale.
    private mutating func calibrateLeftRight() -> Bool {
        let hasGyro = window.contains { $0.rotation != nil }
        var angle = 0.0, low = 0.0, high = 0.0
        for i in 1..<max(window.count, 1) {
            let s = window[i]
            let w = s.rotation.map { $0.dot(Self.unit(s.gravity)) } ?? 0
            angle += w * (s.t - window[i - 1].t)
            low = min(low, angle); high = max(high, angle)
        }
        let yawRange = high - low
        let horizontal = window.map { Self.horizontalPart($0.linear, $0.gravity) }
        let horizontalMax = horizontal.map(\.length).max() ?? 0
        if yawRange < config.minYawSwing * 0.5 && horizontalMax < 0.12 { return false }
        // Si decide solo dopo almeno `calibrationSeconds` di movimento: all'inizio di un twist l'accelerazione
        // orizzontale supera la soglia prima che l'angolo sia ampio, e si sceglierebbe lo spostamento.
        if let moving = window.firstIndex(where: { s in
            abs(s.rotation.map { $0.dot(Self.unit(s.gravity)) } ?? 0) > 0.3 || Self.horizontalPart(s.linear, s.gravity).length > 0.05
        }), let lastT = window.last?.t,
           lastT - window[moving].t < config.calibrationSeconds,
           lastT - window[0].t < config.calibrationSeconds * 2.4 { return false }
        if hasGyro && yawRange >= config.minYawSwing * 0.8 {
            signal = .yaw
            let ws = window.compactMap { s in s.rotation.map { $0.dot(Self.unit(s.gravity)) } }
            yawMean = ws.isEmpty ? 0 : ws.reduce(0, +) / Double(ws.count)
        } else {
            useTranslation(.horizontal, PrincipalAxis.estimate(from: horizontal) ?? Vector3(1, 0, 0))
        }
        return true
    }

    /// Avanti/indietro: spostamento nel piano orizzontale, lungo la direzione in cui varia di più. Non usa mai la
    /// rotazione attorno alla verticale (è la differenza rispetto a sinistra/destra).
    private mutating func calibrateForwardBack() -> Bool {
        let horizontal = window.map { Self.horizontalPart($0.linear, $0.gravity) }
        if (horizontal.map(\.length).max() ?? 0) < 0.12 { return false }   // ancora fermo: si aspetta
        useTranslation(.horizontal, PrincipalAxis.estimate(from: horizontal) ?? Vector3(1, 0, 0))
        return true
    }

    private mutating func useTranslation(_ p: Projection, _ ax: Vector3) {
        signal = .translation
        projection = p
        axis = ax
        accMean = window.reduce(0) { $0 + translationAcc($1.linear, $1.gravity, ax) } / Double(window.count)   // niente transitorio iniziale
    }

    /// Accelerazione (m/s^2) lungo la direzione dello spostamento, secondo la proiezione scelta.
    private func translationAcc(_ linear: Vector3, _ gravity: Vector3, _ ax: Vector3) -> Double {
        switch projection {
        case .principal: return 9.80665 * linear.dot(ax)
        case .vertical: return 9.80665 * linear.dot(Self.unit(gravity))
        case .horizontal: return 9.80665 * Self.horizontalPart(linear, gravity).dot(ax)
        }
    }

    /// Parte orizzontale di un vettore (si toglie la componente lungo la gravita').
    private static func horizontalPart(_ v: Vector3, _ gravity: Vector3) -> Vector3 {
        let u = unit(gravity), d = v.dot(u)
        return Vector3(v.x - d * u.x, v.y - d * u.y, v.z - d * u.z)
    }

    private static func unit(_ v: Vector3) -> Vector3 { let l = max(v.length, 1e-9); return Vector3(v.x / l, v.y / l, v.z / l) }

    private mutating func step(t: Double, gravity: Vector3, linear: Vector3, rotation: Vector3?) -> RepCount? {
        let dt = lastT.map { max(t - $0, 1e-4) } ?? 0.02
        lastT = t
        let raw: Double
        switch signal {
        case .tilt?:
            guard let a = axis else { return nil }
            raw = Self.unit(gravity).dot(a)
        case .yaw?:
            // Velocita' angolare attorno alla verticale, senza la media lenta (deriva del giroscopio),
            // integrata "a perdita": resta l'angolo dei movimenti di 0,5-4 s.
            let w = rotation.map { $0.dot(Self.unit(gravity)) } ?? 0
            yawMean += (w - yawMean) * (1 - exp(-dt / 4.0))
            yawAngle = yawAngle * exp(-dt / 3.0) + (w - yawMean) * dt
            raw = yawAngle
        default:
            guard let a = axis else { return nil }
            // Doppia integrazione "a perdita" (passa-alto): niente deriva, conserva i movimenti di 0,5-4 s.
            let acc = translationAcc(linear, gravity, a)
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
