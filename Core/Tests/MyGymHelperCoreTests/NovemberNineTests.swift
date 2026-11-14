import XCTest
@testable import MyGymHelperCore

/// Modifiche del 9 novembre 2026 (sera): anello pilates e pesi di partenza. Stessi casi di NovemberNineTests.kt.
final class NovemberNineTests: XCTestCase {
    private lazy var catalog: [CatalogExercise] = {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../App/exercises_seed.json").standardized
        return (try? SeedCatalog.decode(Data(contentsOf: url), language: "it")) ?? []
    }()
    private func byID(_ id: String) -> CatalogExercise? { catalog.first { $0.id == id } }

    // ---------- Anello pilates ----------

    func testPilatesRingExercises() {
        XCTAssertTrue(HomeEquipment.choices.contains("pilatesRing"))
        let ring = catalog.filter { $0.equipment == "pilatesRing" }
        XCTAssertGreaterThanOrEqual(ring.count, 10)
        XCTAssertTrue(ring.allSatisfy { $0.isTraining && !$0.id.hasPrefix("seed-") })
        // Filtro attrezzi acceso: senza attrezzi segnati nessuno, con l'anello tutti
        XCTAssertTrue(HomeEquipment.filter(ring, owned: [], enabled: true).isEmpty)
        XCTAssertEqual(HomeEquipment.filter(ring, owned: ["pilatesRing"], enabled: true).count, ring.count)
        XCTAssertEqual(byID("ring-oblique-twist")?.movementAxis, .leftRight)
    }

    func testCustomPlansUseTheRingOnlyAtHome() {
        let gym = CustomPlanInput(sex: .male, age: 30, heightCm: 178, weightKg: 75, goal: .maintain,
                                  experience: .beginner, daysPerWeek: 3, place: .gym)
        for seed in ["r1", "r2", "r3", "r4", "r5", "r6"] {
            let p = CustomPlanGenerator.generate(gym, catalog: catalog, seed: seed)
            let ids = p.days.flatMap { $0.items.map(\.exerciseID) }
            XCTAssertFalse(ids.contains { byID($0)?.equipment == "pilatesRing" }, seed)
        }
        var home = gym; home.place = .home; home.ownedEquipment = ["pilatesRing"]
        let ring = catalog.filter { $0.equipment == "pilatesRing" }
        XCTAssertTrue(ring.allSatisfy { CustomPlanGenerator.isDoable($0, home) })
        XCTAssertFalse(ring.contains { CustomPlanGenerator.isDoable($0, gym) })
    }

    // ---------- Pesi di partenza ----------

    func testSnapToThePlusMinusGrid() {
        XCTAssertEqual(StartingWeights.snap(3.7), 3.5)
        XCTAssertEqual(StartingWeights.snap(4.4), 4.0)
        XCTAssertEqual(StartingWeights.snap(9.6), 10.0)
        XCTAssertEqual(StartingWeights.snap(13), 15.0)
        XCTAssertEqual(StartingWeights.snap(0.3), 1.0)
    }

    func testSuggestedStartingWeights() throws {
        let bench = try XCTUnwrap(byID("seed-bench-press"))
        XCTAssertEqual(StartingWeights.suggest(bench, sex: .male, bodyWeightKg: 80, age: 30), 20.0)
        XCTAssertEqual(StartingWeights.suggest(bench, sex: .female, bodyWeightKg: 80, age: 30), 10.0)
        XCTAssertEqual(StartingWeights.suggest(bench, sex: .male, bodyWeightKg: 80, age: 65), 15.0)
        XCTAssertEqual(StartingWeights.suggest(bench, sex: .male, bodyWeightKg: 80, age: 30, experience: .intermediate), 25.0)
        let squat = try XCTUnwrap(byID("seed-squat"))
        XCTAssertEqual(StartingWeights.suggest(squat, sex: .male, bodyWeightKg: 80, age: 30), 35.0)
        let ring = try XCTUnwrap(byID("ring-squat"))
        XCTAssertNil(StartingWeights.suggest(ring, sex: .male, bodyWeightKg: 80, age: 30))
        let bodyweight = try XCTUnwrap(catalog.first { $0.kind == .strength && $0.equipment == "bodyweight" })
        XCTAssertNil(StartingWeights.suggest(bodyweight, sex: .male, bodyWeightKg: 80, age: 30))
        XCTAssertNil(StartingWeights.suggest(bench, profile: nil))
    }

    func testCustomPlanItemsHaveTheStartingWeight() {
        let input = CustomPlanInput(sex: .male, age: 30, heightCm: 178, weightKg: 75, goal: .maintain,
                                    experience: .beginner, daysPerWeek: 3, place: .gym)
        let p = CustomPlanGenerator.generate(input, catalog: catalog, seed: "w1")
        let items = p.days.flatMap(\.items)
        for item in items {
            let ex = byID(item.exerciseID)!
            let expected = StartingWeights.suggest(ex, sex: .male, bodyWeightKg: 75, age: 30, experience: .beginner) ?? 0
            XCTAssertEqual(item.weightKg, expected, item.exerciseID)
        }
        XCTAssertTrue(items.contains { $0.weightKg > 0 })
    }
}
