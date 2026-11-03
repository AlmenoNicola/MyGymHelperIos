import Foundation

public struct Vector3: Sendable {
    public var x, y, z: Double
    public init(_ x: Double, _ y: Double, _ z: Double) { self.x = x; self.y = y; self.z = z }
    public func dot(_ o: Vector3) -> Double { x * o.x + y * o.y + z * o.z }
    public var length: Double { (x * x + y * y + z * z).squareRoot() }
}

/// Trova l'asse dominante del movimento da campioni di accelerazione 3D (gravita' gia' rimossa,
/// per esempio CMDeviceMotion.userAcceleration), cosi' il segnale con segno oscilla una volta per ripetizione.
public enum PrincipalAxis {
    public static func estimate(from samples: [Vector3]) -> Vector3? {
        guard samples.count >= 10 else { return nil }
        let n = Double(samples.count)
        let mean = Vector3(samples.reduce(0) { $0 + $1.x } / n,
                           samples.reduce(0) { $0 + $1.y } / n,
                           samples.reduce(0) { $0 + $1.z } / n)
        var c = [[Double]](repeating: [0, 0, 0], count: 3)
        for s in samples {
            let d = [s.x - mean.x, s.y - mean.y, s.z - mean.z]
            for i in 0..<3 { for j in 0..<3 { c[i][j] += d[i] * d[j] / n } }
        }
        var v = [1.0, 1.0, 1.0]
        for _ in 0..<50 {
            var w = [0.0, 0.0, 0.0]
            for i in 0..<3 { for j in 0..<3 { w[i] += c[i][j] * v[j] } }
            let len = (w[0] * w[0] + w[1] * w[1] + w[2] * w[2]).squareRoot()
            if len < 1e-12 { return nil }
            v = w.map { $0 / len }
        }
        return Vector3(v[0], v[1], v[2])
    }
}

public struct RepEvent: Sendable, Equatable {
    public let index: Int            // 1, 2, 3...
    public let timestamp: TimeInterval
    public let peakAmplitude: Double // proxy della velocita' del movimento
}

public struct RepDetectorConfig: Sendable {
    public var cutoffHz = 3.0            // filtro passa-basso
    public var minPeak = 0.12            // ampiezza minima (g) per contare una ripetizione
    public var minInterval = 0.7         // secondi minimi tra due ripetizioni
    public var thresholdFraction = 0.5   // soglia adattiva rispetto al picco medio
    public var rearmFraction = 0.3       // isteresi: il segnale deve scendere sotto questa frazione della soglia
    public init() {}
}

/// Rilevatore di ripetizioni in tempo reale su un segnale 1D (proiezione sull'asse dominante).
/// Va tarato con registrazioni reali su iPhone e Apple Watch: i valori di default sono un punto di partenza.
public struct RepDetector {
    private let config: RepDetectorConfig
    private var smoothed: Double?
    private var lastTime: TimeInterval?
    private var prev2: (t: TimeInterval, v: Double)?
    private var prev1: (t: TimeInterval, v: Double)?
    private var averagePeak: Double?
    private var lastRepTime: TimeInterval?
    private var armed = true
    public private(set) var count = 0
    public private(set) var events: [RepEvent] = []

    public init(config: RepDetectorConfig = RepDetectorConfig()) { self.config = config }

    private var threshold: Double {
        guard let avg = averagePeak else { return config.minPeak }
        return max(config.minPeak, config.thresholdFraction * avg)
    }

    /// Processa un campione; restituisce un evento quando viene riconosciuta una ripetizione
    /// (con un campione di ritardo, necessario per riconoscere il picco).
    @discardableResult
    public mutating func process(_ value: Double, at time: TimeInterval) -> RepEvent? {
        if let s = smoothed, let lt = lastTime {
            let dt = max(time - lt, 1e-6)
            let rc = 1 / (2 * Double.pi * config.cutoffHz)
            smoothed = s + (dt / (rc + dt)) * (value - s)
        } else {
            smoothed = value
        }
        lastTime = time
        let current = (t: time, v: smoothed ?? value)
        var event: RepEvent?
        let th = threshold
        if let p1 = prev1, let p2 = prev2 {
            if !armed && current.v < config.rearmFraction * th { armed = true }
            let isPeak = p1.v > p2.v && p1.v >= current.v
            let farEnough = lastRepTime.map { p1.t - $0 >= config.minInterval } ?? true
            if armed && isPeak && p1.v > th && farEnough {
                count += 1
                lastRepTime = p1.t
                armed = false
                averagePeak = averagePeak.map { 0.7 * $0 + 0.3 * p1.v } ?? p1.v
                let e = RepEvent(index: count, timestamp: p1.t, peakAmplitude: p1.v)
                events.append(e)
                event = e
            }
        }
        prev2 = prev1
        prev1 = current
        return event
    }

    /// 0...1: bassa se ampiezze e intervalli sono molto irregolari (per esempio telefono in tasca).
    public var signalConfidence: Double {
        guard events.count >= 3 else { return 1 }
        func cv(_ xs: [Double]) -> Double {
            let m = xs.reduce(0, +) / Double(xs.count)
            guard m > 0 else { return 1 }
            let v = xs.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(xs.count)
            return v.squareRoot() / m
        }
        let amps = events.map(\.peakAmplitude)
        let gaps = zip(events.dropFirst(), events).map { $0.timestamp - $1.timestamp }
        let worst = max(cv(amps), cv(gaps))
        return max(0, min(1, 1 - worst))
    }
}
