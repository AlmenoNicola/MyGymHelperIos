import XCTest
@testable import MyGymHelperCore

/// Calibrazione per posizione: stessi casi di `android/core/.../CalibrationTests.kt`.
final class CalibrationTests: XCTestCase {
    private var rng = SeededRandom(seed: 11)

    private func rotate(reps: Int, amp: Double, period: Double = 2.5, feed: (Double, Vector3, Vector3) -> Void) {
        let total = 1 + Double(reps) * period + 1.5
        MotionSim.rotate(seconds: total, rng: &rng, theta: { MotionSim.curl($0, reps: reps, period: period, amp: amp) }, feed: feed)
    }

    private func counted(_ config: RepCounterConfig, reps: Int, amp: Double) -> Int {
        var c = RepCounter(config: config)
        rotate(reps: reps, amp: amp) { t, g, l in c.process(t: t, gravity: g, linear: l) }
        return c.count
    }

    private func calibrate(reps: Int, amp: Double, period: Double = 2.5) -> RepCalibrator {
        var cal = RepCalibrator()
        rotate(reps: reps, amp: amp, period: period) { t, g, l in cal.process(t: t, gravity: g, linear: l) }
        return cal
    }

    func testSmallMovementsAreMissedByDefaultButCountedAfterCalibration() {
        XCTAssertEqual(counted(RepCounterConfig(), reps: 8, amp: 14), 0)          // coscia che si muove di 14 gradi
        let result = calibrate(reps: 5, amp: 14).result()
        XCTAssertNotNil(result)
        let tuning = result!.toTuning()
        XCTAssertEqual(tuning.signal, .tilt)
        XCTAssertEqual(counted(tuning.config(), reps: 8, amp: 14), 8)
    }

    func testCalibrationOnBigMovementsIgnoresSmallOnes() {
        let tuning = calibrate(reps: 5, amp: 110).result()!.toTuning()
        XCTAssertEqual(counted(tuning.config(), reps: 8, amp: 110), 8)
        XCTAssertEqual(counted(tuning.config(), reps: 8, amp: 20), 0)
        XCTAssertGreaterThan(counted(RepCounterConfig(), reps: 8, amp: 20), 0)
    }

    func testCalibratorNeedsEnoughRepsAndReportsProgress() {
        let cal = calibrate(reps: 2, amp: 90)
        XCTAssertEqual(cal.repsDetected, 2)
        XCTAssertNil(cal.result())
        XCTAssertFalse(cal.isComplete)
        let full = calibrate(reps: 6, amp: 90)
        XCTAssertTrue(full.isComplete)
        let r = full.result()!
        XCTAssertTrue(r.isReliable, "regolare: \(r.consistency)")
        XCTAssertEqual(r.repSeconds, 2.5, accuracy: 0.3)
    }

    func testCalibrationPicksTranslationWhenLimbDoesNotRotate() {
        var cal = RepCalibrator()
        let w = 2 * Double.pi / 2
        for i in 0..<Int((1 + 8 * 2 + 1.5) * MotionSim.hz) {
            let t = Double(i) / MotionSim.hz, u = t - 1
            let a = (u < 0 || u > 16) ? 0 : 0.15 * w * w * cos(w * u) / 9.80665
            cal.process(t: t, gravity: Vector3(rng.noise(0.01), 1 + rng.noise(0.01), rng.noise(0.01)),
                        linear: Vector3(a + rng.noise(0.02), rng.noise(0.02), rng.noise(0.02)))
        }
        let r = cal.result()!
        XCTAssertEqual(r.signal, .translation)
        let cfg = r.toTuning().config()
        XCTAssertEqual(cfg.forcedSignal, .translation)
        XCTAssertTrue((PositionTuning.minTranslation...PositionTuning.maxTranslation).contains(cfg.minTranslationSwing))
    }

    func testSensitivityScalesThresholdsWithinLimits() {
        let base = RepCounterConfig()
        XCTAssertEqual(PositionTuning().config(base: base), base)              // predefinita: nessun cambiamento
        XCTAssertEqual(PositionTuning(sensitivity: 2).config(base: base).minTiltSwing, base.minTiltSwing / 2, accuracy: 1e-9)
        XCTAssertEqual(PositionTuning(sensitivity: 0.5).config(base: base).minTiltSwing, base.minTiltSwing * 2, accuracy: 1e-9)
        XCTAssertEqual(PositionTuning(sensitivity: 9).config(base: base).minTiltSwing, base.minTiltSwing / 2, accuracy: 1e-9)
        let extreme = PositionTuning(sensitivity: 2, typicalSwing: 0.01, signal: .tilt).config(base: base)
        XCTAssertEqual(extreme.minTiltSwing, PositionTuning.minTilt, accuracy: 1e-9)
    }

    func testForcedSignalIsRespected() {
        var c = RepCounter(config: RepCounterConfig(forcedSignal: .translation))
        rotate(reps: 4, amp: 100) { t, g, l in c.process(t: t, gravity: g, linear: l) }
        XCTAssertEqual(c.signal, .translation)
    }

    func testPositionsMapLegacyLimbs() {
        XCTAssertEqual(SensorPosition.fromLegacy("arm"), .armUpper)
        XCTAssertEqual(SensorPosition.fromLegacy("leg"), .legThigh)
        XCTAssertEqual(SensorPosition.fromLegacy("abs"), .abs)
        XCTAssertEqual(SensorPosition.from("legShin"), .legShin)
        XCTAssertTrue(SensorPosition.legShin.isLowerBody && !SensorPosition.abs.isLowerBody)
        XCTAssertEqual(SensorPosition.allCases.count, 5)
    }
}
