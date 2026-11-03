import XCTest
@testable import MyGymHelperCore

/// Schede pronte e scheda del mese. Stessi casi di PresetsTests.kt.
final class PresetsTests: XCTestCase {
    private lazy var catalog: [CatalogExercise] = {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../App/exercises_seed.json").standardized
        return (try? SeedCatalog.decode(Data(contentsOf: url), language: "it")) ?? []
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d, hour: 18))!
    }

    private func session(_ id: String, _ at: Date, sets: Int = 3, kg: Double = 0) -> SessionSummary {
        SessionSummary(exerciseID: id, startedAt: at, sets: sets, weightKg: kg)
    }

    func testEveryPresetExerciseIsInTheCatalog() {
        let ids = Set(catalog.map(\.id))
        for p in PresetPlans.all { for d in p.days { for i in d.items { XCTAssertTrue(ids.contains(i.exerciseID), i.exerciseID) } } }
        XCTAssertEqual(PresetPlans.all.count, 5)
        XCTAssertEqual(PresetPlans.all.first?.id, PresetPlans.freeID)
    }

    func testFreeSeesOnlyTheBasePlan() {
        XCTAssertEqual(PresetPlans.all.filter { PresetPlans.isAvailable($0, for: .free) }.map(\.id), [PresetPlans.freeID])
        XCTAssertEqual(PresetPlans.all.filter { PresetPlans.isAvailable($0, for: .mid) }.count, 5)
        XCTAssertFalse(FeatureGate.isAvailable(.monthlyPlan, for: .free))
    }

    func testItemsTakeTheLastWeight() {
        let day = PresetPlans.freeTotalBody.days[0]
        let items = PresetPlans.items(for: day, sessions: [session("seed-squat", Date(timeIntervalSince1970: 1), kg: 40),
                                                         session("seed-squat", Date(timeIntervalSince1970: 2), kg: 50)])
        XCTAssertEqual(items.first?.weightKg, 50)
        XCTAssertEqual(items[1].weightKg, 0)
        XCTAssertEqual(items.count, day.items.count)
    }

    func testStableHashMatchesAndroid() {
        XCTAssertEqual(MonthlyPlanner.stableHash("a"), 0xE40C292C)
        XCTAssertEqual(MonthlyPlanner.stableHash(""), 0x811C9DC5)
    }

    func testNoHistoryGivesThreeFullBodyDays() {
        let m = MonthlyPlanner.generate(catalog: catalog, sessions: [], now: date(2026, 10, 15))
        XCTAssertEqual(m.summary.monthKey, "2026-10")
        XCTAssertEqual(m.plan.days.count, 3)
        let ids = m.plan.days.flatMap { $0.items.map(\.exerciseID) }
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertTrue(m.plan.days.allSatisfy { $0.items.count == 6 })
        let byID = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })
        XCTAssertTrue(ids.allSatisfy { byID[$0]?.isTraining == true })
        XCTAssertEqual(m, MonthlyPlanner.generate(catalog: catalog, sessions: [], now: date(2026, 10, 28)))
    }

    func testFrequentTrainingGivesUpperLowerAndKeepsExercises() {
        let sessions = (1...18).flatMap { d in
            [session("seed-bench-press", date(2026, 9, d), kg: 60), session("seed-squat", date(2026, 9, d), kg: 80)]
        }
        let m = MonthlyPlanner.generate(catalog: catalog, sessions: sessions, now: date(2026, 10, 3))
        XCTAssertEqual(m.plan.days.count, 4)
        XCTAssertEqual(m.summary.trainingDays, 18)
        let ids = m.plan.days.flatMap { $0.items.map(\.exerciseID) }
        XCTAssertTrue(ids.contains("seed-bench-press") && ids.contains("seed-squat"))
        XCTAssertFalse(m.summary.undertrained.isEmpty)
        XCTAssertEqual(m.plan.level, "intermediate")
    }

    func testBodyweightOnlyStaysBodyweight() {
        let sessions = (1...8).map { d in session("seed-pushup", date(2026, 9, d * 3)) }
        let m = MonthlyPlanner.generate(catalog: catalog, sessions: sessions, now: date(2026, 10, 3))
        let byID = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })
        let light: Set<String> = ["bodyweight", "band", "exerciseBall", "other"]
        XCTAssertTrue(m.plan.days.flatMap(\.items).allSatisfy { light.contains(byID[$0.exerciseID]?.equipment ?? "") })
        XCTAssertEqual(m.plan.days.count, 2)
        XCTAssertEqual(m.plan.daysPerWeek, 3)   // ma sempre almeno 3 a settimana (A e B alternati)
    }

    func testEveryPlanHasThreeOrFourWorkoutsAWeek() {
        for p in PresetPlans.all { XCTAssertTrue((3...4).contains(p.daysPerWeek), p.id) }
        XCTAssertEqual(MonthlyPlanner.generate(catalog: catalog, sessions: [], now: date(2026, 10, 15)).plan.daysPerWeek, 3)
    }
}
