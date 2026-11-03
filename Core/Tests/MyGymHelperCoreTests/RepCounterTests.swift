import XCTest
@testable import MyGymHelperCore

/// Generatore pseudo-casuale con seme (SplitMix64): stessi numeri su ogni macchina, come nei test Kotlin di verifica.
struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func nextDouble() -> Double {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z = z ^ (z >> 31)
        return Double(z >> 11) / 9007199254740992.0
    }
    mutating func noise(_ a: Double) -> Double { (nextDouble() * 2 - 1) * a }
}

/// Simulazione di un arto che ruota a 50 Hz con il telefono fissato sopra (raggio 30 cm). Usata da piu' test.
enum MotionSim {
    static let hz = 50.0

    /// `theta(t)` in gradi; `feed` riceve tempo, gravita' e accelerazione lineare (in g).
    static func rotate(seconds: Double, noiseG: Double = 0.02, rng: inout SeededRandom,
                       theta: (Double) -> Double, feed: (Double, Vector3, Vector3) -> Void) {
        let n = Int(seconds * hz), dt = 1 / hz
        func pos(_ t: Double) -> (Double, Double) { let th = theta(t) * .pi / 180; return (0.3 * sin(th), -0.3 * cos(th)) }
        for i in 0..<n {
            let t = Double(i) * dt
            let th = theta(t) * .pi / 180
            let (x0, y0) = pos(t - dt), (x1, y1) = pos(t), (x2, y2) = pos(t + dt)
            let ax = (x2 - 2 * x1 + x0) / (dt * dt) / 9.80665, ay = (y2 - 2 * y1 + y0) / (dt * dt) / 9.80665
            let g = Vector3(sin(th) + rng.noise(noiseG), cos(th) + rng.noise(noiseG), rng.noise(noiseG))
            feed(t, g, Vector3(ax + rng.noise(noiseG), ay + rng.noise(noiseG), rng.noise(noiseG)))
        }
    }

    /// Curl: 0 -> `amp` -> 0 gradi in `period` secondi, dopo `still` secondi da fermo.
    static func curl(_ t: Double, reps: Int, period: Double = 2.5, still: Double = 1.0, amp: Double = 120) -> Double {
        let u = t - still
        if u < 0 || u > Double(reps) * period { return 0 }
        return amp * (1 - cos(2 * .pi * u / period)) / 2
    }
}

/// Stessi casi di `android/core/.../RepCounterTests.kt`.
final class RepCounterTests: XCTestCase {
    private var rng = SeededRandom(seed: 7)

    private func rotation(_ seconds: Double, noiseG: Double = 0.02, config: RepCounterConfig = RepCounterConfig(),
                          _ theta: (Double) -> Double) -> RepCounter {
        var c = RepCounter(config: config)
        MotionSim.rotate(seconds: seconds, noiseG: noiseG, rng: &rng, theta: theta) { t, g, l in c.process(t: t, gravity: g, linear: l) }
        return c
    }

    func testCurlCountsOnePerFullMovement() {
        let c = rotation(1 + 10 * 2.5 + 1.5) { MotionSim.curl($0, reps: 10) }
        XCTAssertEqual(c.signal, .tilt)
        XCTAssertEqual(c.count, 10)
        XCTAssertGreaterThan(c.signalConfidence, 0.7)
    }

    func testSlowAndFastRepsAreCounted() {
        XCTAssertEqual(rotation(1 + 6 * 4 + 1.5) { MotionSim.curl($0, reps: 6, period: 4) }.count, 6)
        XCTAssertEqual(rotation(1 + 8 * 1.2 + 1.5) { MotionSim.curl($0, reps: 8, period: 1.2) }.count, 8)
    }

    func testSmallMovementsAreIgnored() {
        XCTAssertEqual(rotation(12) { 6 * sin(2 * .pi * 3 * $0) }.count, 0)          // tremolio di 6 gradi a 3 Hz
        XCTAssertEqual(rotation(12) { 5 + 5 * sin(2 * .pi * 0.5 * $0) }.count, 0)    // oscillazione lenta di 10 gradi
    }

    func testWigglesBetweenRepsDoNotCount() {
        // 5 ripetizioni ampie, ognuna seguita da 2 s di piccoli aggiustamenti (+-8 gradi).
        let period = 2.5, pause = 2.0
        let c = rotation(1 + 5 * (period + pause) + 1) { t in
            let u = t - 1
            let k = Int(u / (period + pause)), r = u - Double(k) * (period + pause)
            if u < 0 || k >= 5 { return 0 }
            return r < period ? 110 * (1 - cos(2 * .pi * r / period)) / 2 : 8 * sin(2 * .pi * 1.5 * r)
        }
        XCTAssertEqual(c.count, 5)
    }

    func testHalfRepCountsOnlyWhenTheLimbReturns() {
        // Sale a 120 gradi e resta su: nessuna ripetizione.
        let c = rotation(5) { t in t < 1 ? 0 : (t < 2.25 ? 120 * (1 - cos(.pi * (t - 1) / 1.25)) / 2 : 120) }
        XCTAssertEqual(c.count, 0)
    }

    func testTranslationWithoutRotation() {
        // Panca: spostamento di 30 cm avanti e indietro in 2 s, telefono che non ruota.
        var c = RepCounter()
        let w = 2 * Double.pi / 2
        for i in 0..<Int((1 + 8 * 2 + 1.5) * MotionSim.hz) {
            let t = Double(i) / MotionSim.hz, u = t - 1
            let a = (u < 0 || u > 16) ? 0 : 0.15 * w * w * cos(w * u) / 9.80665
            c.process(t: t, gravity: Vector3(rng.noise(0.01), 1 + rng.noise(0.01), rng.noise(0.01)),
                      linear: Vector3(a + rng.noise(0.02), rng.noise(0.02), rng.noise(0.02)))
        }
        XCTAssertEqual(c.signal, .translation)
        XCTAssertEqual(c.count, 8)
    }

    func testVibrationIsNotARep() {
        var c = RepCounter()
        for i in 0..<Int(10 * MotionSim.hz) {
            let t = Double(i) / MotionSim.hz
            c.process(t: t, gravity: Vector3(rng.noise(0.01), 1, rng.noise(0.01)),
                      linear: Vector3(0.3 * sin(2 * .pi * 8 * t), rng.noise(0.05), rng.noise(0.05)))
        }
        XCTAssertEqual(c.count, 0)
    }

    func testIrregularRepsWithNoise() {
        // 12 ripetizioni con ampiezza 70-130 gradi e durata 1,5-3,5 s, rumore forte, brevi soste.
        var r = SeededRandom(seed: 3)
        let segs = (0..<12).map { _ in (amp: 70 + r.nextDouble() * 60, period: 1.5 + r.nextDouble() * 2, gap: r.nextDouble() * 0.8) }
        var starts = [1.0]
        for s in segs { starts.append(starts.last! + s.period + s.gap) }
        let c = rotation(starts.last! + 1.5, noiseG: 0.06) { t in
            guard let k = starts.lastIndex(where: { $0 <= t }), k < segs.count else { return 0 }
            let u = t - starts[k]
            return u < segs[k].period ? segs[k].amp * (1 - cos(2 * .pi * u / segs[k].period)) / 2 : 0
        }
        XCTAssertEqual(c.count, 12)
    }

    func testSuddenBumpIsNotARep() {
        XCTAssertEqual(rotation(6) { (2.0...2.1).contains($0) ? 25 : 0 }.count, 0)   // urto secco di 0,1 s
    }
}
