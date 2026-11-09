import XCTest
@testable import MyGymHelperCore

/// Asse del movimento (su/giu' o sinistra/destra rispetto al pavimento) e regole del catalogo.
/// Port di MovementAxisTests.kt: movimenti simulati a 50 Hz, gravita' vista dal telefono lungo y.
final class MovementAxisTests: XCTestCase {
    private let hz = 50.0
    private let g = 9.80665

    /// Ripetizioni a coseno: 0 -> amp -> 0 in `period` secondi, dopo 2 s da fermo.
    private func wave(_ t: Double, reps: Int, period: Double, amp: Double) -> Double {
        let u = t - 2.0
        if u < 0 || u > Double(reps) * period { return 0 }
        return amp * (1 - cos(2 * .pi * u / period)) / 2
    }

    /// Derivata seconda numerica (m/s^2) della posizione p(t).
    private func acc(_ p: (Double) -> Double, _ t: Double) -> Double { let d = 1 / hz; return (p(t + d) - 2 * p(t) + p(t - d)) / (d * d) }

    /// Spostamento lungo una direzione del telefono (y = verticale, x = orizzontale), senza rotazioni.
    private func translation(_ axis: MovementAxis?, vertical: Bool, reps: Int = 8, period: Double = 2.5, amp: Double = 0.35) -> RepCounter {
        var rng = SeededRandom(seed: 11)
        var c = RepCounter(config: RepCounterConfig(axis: axis))
        let p = { (t: Double) in self.wave(t, reps: reps, period: period, amp: amp) }
        let n = Int((3.5 + Double(reps) * period) * hz)
        for i in 0..<n {
            let t = Double(i) / hz
            let a = acc(p, t) / g
            let lin = vertical ? Vector3(rng.noise(0.01), a + rng.noise(0.01), rng.noise(0.01))
                               : Vector3(a + rng.noise(0.01), rng.noise(0.01), rng.noise(0.01))
            c.process(t: t, gravity: Vector3(rng.noise(0.01), 1, rng.noise(0.01)), linear: lin,
                      rotation: Vector3(rng.noise(0.01), rng.noise(0.01), rng.noise(0.01)))
        }
        return c
    }

    /// Rotazione del busto attorno alla verticale (twist): la gravita' non cambia, il giroscopio si'.
    private func twist(_ axis: MovementAxis?, reps: Int = 8, period: Double = 2.5, ampDeg: Double = 70, gyro: Bool = true) -> RepCounter {
        var rng = SeededRandom(seed: 13)
        var c = RepCounter(config: RepCounterConfig(axis: axis))
        let th = { (t: Double) in self.wave(t, reps: reps, period: period, amp: ampDeg * .pi / 180) }
        let n = Int((3.5 + Double(reps) * period) * hz)
        let d = 1 / hz
        for i in 0..<n {
            let t = Double(i) / hz
            let w = (th(t + d) - th(t - d)) / (2 * d)
            // Telefono sul braccio a 30 cm dall'asse: piccola accelerazione orizzontale (tangenziale).
            let lin = Vector3(0.3 * acc(th, t) / g + rng.noise(0.01), rng.noise(0.01), rng.noise(0.01))
            c.process(t: t, gravity: Vector3(rng.noise(0.01), 1, rng.noise(0.01)), linear: lin,
                      rotation: gyro ? Vector3(rng.noise(0.02), w + rng.noise(0.02), rng.noise(0.02)) : nil)
        }
        return c
    }

    func testUpDownCountsVerticalMovementOnly() {
        let v = translation(.upDown, vertical: true)
        XCTAssertEqual(v.signal, .translation)
        XCTAssertEqual(v.count, 8)
        // Spostamento orizzontale (es. rematore seduto) con asse su/giu': non conta.
        XCTAssertEqual(translation(.upDown, vertical: false).count, 0)
    }

    func testLeftRightCountsHorizontalMovementOnly() {
        XCTAssertEqual(translation(.leftRight, vertical: false).count, 8)
        XCTAssertEqual(translation(.leftRight, vertical: true).count, 0)
    }

    func testLeftRightCountsRotationsAroundTheVertical() {
        let c = twist(.leftRight)
        XCTAssertEqual(c.signal, .yaw)
        XCTAssertEqual(c.count, 8)
        // Su/giu': girando attorno alla verticale la gravita' non cambia, nessuna ripetizione.
        XCTAssertEqual(twist(.upDown).count, 0)
    }

    func testSmallTwistsAreIgnored() {
        XCTAssertEqual(twist(.leftRight, ampDeg: 8).count, 0)
    }

    func testNoAxisKeepsTheAutomaticChoice() {
        XCTAssertEqual(translation(nil, vertical: true).count, 8)
        XCTAssertEqual(translation(nil, vertical: false).count, 8)
    }

    func testOtherAxisAndRawValues() {
        XCTAssertEqual(MovementAxis.upDown.other, .leftRight)
        XCTAssertEqual(MovementAxis(rawValue: "upDown"), .upDown)
        XCTAssertNil(MovementAxis(rawValue: "x"))
    }

    func testTuningKeepsAxisAndScalesYaw() {
        var c = PositionTuning(sensitivity: 2.0).config()
        c.axis = .leftRight
        XCTAssertEqual(c.axis, .leftRight)
        XCTAssertLessThan(c.minYawSwing, RepCounterConfig().minYawSwing)
    }

    // ---------- Regole del catalogo ----------

    private func ex(_ id: String, _ category: String = "strength", movement: MovementAxis? = nil) -> CatalogExercise {
        CatalogExercise(id: id, name: id, primary: [MuscleGroup.allCases[0]], category: category, movement: movement)
    }

    func testCatalogRules() {
        let lr = ["seed-russian-twist", "fedb-Cable_Russian_Twists", "fedb-Standing_Cable_Wood_Chop", "fedb-Butterfly",
                  "fedb-Seated_Cable_Rows", "fedb-Face_Pull", "fedb-Thigh_Abductor", "fedb-Cable_Chest_Press", "fedb-Landmine_180s",
                  "fedb-External_Rotation_with_Cable", "fedb-Cable_Crossover", "fedb-Pallof_Press"]
        for id in lr { XCTAssertEqual(MovementRules.of(ex(id)), .leftRight, id) }
        let ud = ["seed-bench-press", "seed-lateral-raise", "seed-bent-row", "fedb-Upright_Barbell_Row", "fedb-Low_Cable_Crossover",
                  "fedb-Incline_Dumbbell_Flyes_-_With_A_Twist", "fedb-Kneeling_High_Pulley_Row", "fedb-Lateral_Raise_-_With_Bands",
                  "fedb-Stride_Jump_Crossover", "fedb-Wrist_Rotations_with_Straight_Bar", "fedb-Dumbbell_Side_Bend"]
        for id in ud { XCTAssertEqual(MovementRules.of(ex(id)), .upDown, id) }
        XCTAssertEqual(MovementRules.of(ex("fedb-Lateral_Bound", "plyometrics")), .leftRight)
        XCTAssertEqual(MovementRules.of(ex("fedb-Box_Jump_Multiple_Response", "plyometrics")), .upDown)
        // Valore scritto nel catalogo: vince sulle regole.
        XCTAssertEqual(MovementRules.of(ex("seed-russian-twist", movement: .upDown)), .upDown)
    }

    func testItemOverrideWins() {
        let e = ex("seed-bench-press")
        XCTAssertEqual(MovementRules.forItem(e, WorkoutItem(exerciseID: e.id)), .upDown)
        var chosen = WorkoutItem(exerciseID: e.id); chosen.movement = .leftRight
        XCTAssertEqual(MovementRules.forItem(e, chosen), .leftRight)
        // Esercizio alternativo: la scelta salvata sulla riga e' dell'esercizio originale e non vale.
        var other = WorkoutItem(exerciseID: e.id); other.movement = .upDown
        XCTAssertEqual(MovementRules.forItem(ex("seed-russian-twist"), other), .leftRight)
        XCTAssertEqual(MovementRules.forItem(nil, nil), .upDown)
        // Scelta uguale a quella del catalogo: sulla riga non si salva niente.
        XCTAssertNil(MovementRules.override(e, .upDown))
        XCTAssertEqual(MovementRules.override(e, .leftRight), .leftRight)
    }
}
