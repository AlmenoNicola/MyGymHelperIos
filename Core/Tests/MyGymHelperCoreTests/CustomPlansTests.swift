import XCTest
@testable import MyGymHelperCore

/// Scheda personalizzata da altezza, peso, sesso e obiettivo. Stessi casi di CustomPlansTests.kt.
final class CustomPlansTests: XCTestCase {
    private lazy var catalog: [CatalogExercise] = {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../App/exercises_seed.json").standardized
        return (try? SeedCatalog.decode(Data(contentsOf: url), language: "it")) ?? []
    }()
    private lazy var byID: [String: CatalogExercise] = Dictionary(catalog.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    private let base = CustomPlanInput(sex: .male, age: 30, heightCm: 178, weightKg: 75, goal: .maintain,
                                       experience: .beginner, daysPerWeek: 3, place: .gym)

    private func ids(_ p: PresetPlan) -> [String] { p.days.flatMap { $0.items.map(\.exerciseID) } }
    private func with(_ change: (inout CustomPlanInput) -> Void) -> CustomPlanInput { var i = base; change(&i); return i }

    func testOnlyPro() {
        XCTAssertFalse(FeatureGate.isAvailable(.customPlans, for: .free))
        XCTAssertTrue(FeatureGate.isAvailable(.customPlans, for: .full))
    }

    func testBeginnerThreeDaysIsFullBody() {
        let p = CustomPlanGenerator.generate(base, catalog: catalog, seed: "s1")
        XCTAssertEqual(p.days.map(\.titleKey), ["presets.day.a", "presets.day.b", "presets.day.c"])
        XCTAssertTrue(p.days.allSatisfy { $0.items.count == 5 })
        XCTAssertEqual(p.daysPerWeek, 3)
        XCTAssertEqual(p.level, "beginner")
        XCTAssertEqual(p.id, "custom:s1")
        let all = ids(p)
        XCTAssertEqual(all.count, Set(all).count)                       // mai lo stesso esercizio due volte
        XCTAssertTrue(all.allSatisfy { byID[$0]!.isTraining })
        XCTAssertTrue(all.allSatisfy { byID[$0]!.level == "beginner" || byID[$0]!.level.isEmpty })
    }

    func testSplitsByExperienceAndDays() {
        let ppl = CustomPlanGenerator.generate(with { $0.experience = .intermediate }, catalog: catalog, seed: "s")
        XCTAssertEqual(ppl.days.map(\.titleKey), ["presets.day.push", "presets.day.pull", "presets.day.legs"])
        XCTAssertTrue(ppl.days.allSatisfy { $0.items.count == 6 })
        let ul = CustomPlanGenerator.generate(with { $0.experience = .advanced; $0.daysPerWeek = 4 }, catalog: catalog, seed: "s")
        XCTAssertEqual(ul.days.count, 4)
        XCTAssertEqual(ul.daysPerWeek, 4)
        XCTAssertEqual(ul.level, "expert")
        XCTAssertTrue(ul.days.allSatisfy { $0.items.count == 7 })
        // 5 o più allenamenti non esistono: si torna a 4
        XCTAssertEqual(with { $0.daysPerWeek = 6 }.clamped().daysPerWeek, 4)
        XCTAssertEqual(with { $0.daysPerWeek = 1 }.clamped().daysPerWeek, 3)
    }

    func testParametersFollowTheGoal() {
        let squat = byID["seed-squat"]!
        let curl = byID["seed-biceps-curl"]!
        let gain = with { $0.goal = .gain; $0.experience = .intermediate }
        XCTAssertEqual(CustomPlanGenerator.parametersFor(squat, muscle: .quads, gain), PresetItem("seed-squat", sets: 4, reps: 8, restSeconds: 120))
        XCTAssertEqual(CustomPlanGenerator.parametersFor(curl, muscle: .biceps, gain), PresetItem("seed-biceps-curl", sets: 3, reps: 10, restSeconds: 75))
        let lose = with { $0.goal = .lose }
        XCTAssertEqual(CustomPlanGenerator.parametersFor(squat, muscle: .quads, lose), PresetItem("seed-squat", sets: 3, reps: 12, restSeconds: 60))
        XCTAssertEqual(CustomPlanGenerator.parametersFor(curl, muscle: .biceps, lose), PresetItem("seed-biceps-curl", sets: 3, reps: 15, restSeconds: 45))
        XCTAssertEqual(CustomPlanGenerator.parametersFor(squat, muscle: .quads, base), PresetItem("seed-squat", sets: 3, reps: 10, restSeconds: 90))
        // Dai 50 anni: almeno 10 ripetizioni e 30" in più sui multiarticolari; dai 65 al massimo 3 serie
        let older = with { $0.goal = .gain; $0.experience = .advanced; $0.age = 66 }
        XCTAssertEqual(CustomPlanGenerator.parametersFor(squat, muscle: .quads, older), PresetItem("seed-squat", sets: 3, reps: 10, restSeconds: 180))
    }

    func testLoseAddsAPlyometricFinisherUnlessLowImpact() {
        let lose = CustomPlanGenerator.generate(with { $0.goal = .lose }, catalog: catalog, seed: "s")
        XCTAssertTrue(lose.days.allSatisfy { byID[$0.items.last!.exerciseID]!.kind == .plyometrics })
        XCTAssertTrue(lose.days.allSatisfy { $0.items.count == 6 })
        // BMI da obesità (110 kg, 170 cm = 38): niente salti
        let obese = with { $0.goal = .lose; $0.weightKg = 110; $0.heightCm = 170 }
        XCTAssertTrue(CustomPlanGenerator.isLowImpact(obese))
        let p = CustomPlanGenerator.generate(obese, catalog: catalog, seed: "s")
        XCTAssertFalse(ids(p).contains { byID[$0]!.kind == .plyometrics })
        XCTAssertTrue(CustomPlanGenerator.isLowImpact(with { $0.age = 70 }))
        XCTAssertFalse(CustomPlanGenerator.isLowImpact(base))
    }

    func testPlaceLimitsEquipment() {
        let bw = CustomPlanGenerator.generate(with { $0.place = .bodyweight }, catalog: catalog, seed: "s")
        XCTAssertFalse(ids(bw).isEmpty)
        XCTAssertTrue(ids(bw).allSatisfy { HomeEquipment.alwaysAvailable.contains(byID[$0]!.equipment) })
        let home = CustomPlanGenerator.generate(with { $0.place = .home; $0.ownedEquipment = ["dumbbell"] }, catalog: catalog, seed: "s")
        XCTAssertTrue(ids(home).allSatisfy { ["bodyweight", "", "dumbbell"].contains(byID[$0]!.equipment) })
    }

    func testSameSeedSamePlanDifferentSeedCanDiffer() {
        let input = with { $0.experience = .intermediate }
        let a = CustomPlanGenerator.generate(input, catalog: catalog, seed: "x")
        XCTAssertEqual(a, CustomPlanGenerator.generate(input, catalog: catalog, seed: "x"))
        let seeds = Set((1...10).map { ids(CustomPlanGenerator.generate(input, catalog: catalog, seed: "seed\($0)")) })
        XCTAssertTrue(seeds.count > 1)
    }

    func testNotesAndDefaults() {
        let n = CustomPlanGenerator.notes(with { $0.goal = .lose })
        XCTAssertEqual(n.bmi?.category, .normal)
        let tdee = NutritionCalculator.targets(sex: .male, weightKg: 75, heightCm: 178, ageYears: 30, activity: .light, goal: .lose).calories
        XCTAssertEqual(n.dailyCalories, tdee)
        XCTAssertFalse(n.lowImpact); XCTAssertFalse(n.gentleLoads)
        // Dal profilo: obiettivo consigliato dal BMI finché l'utente non lo sceglie
        let fromProfile = CustomPlanInput.fromProfile(HealthProfile(heightCm: 180, weightKg: 50))
        XCTAssertEqual(fromProfile.goal, .gain)
        XCTAssertEqual(CustomPlanInput.fromProfile(nil).goal, .maintain)
    }

    func testSuggestedNames() {
        let plan = CustomPlanGenerator.generate(base, catalog: catalog, seed: "s")
        let recs = [CustomPlanRecord(name: "La mia scheda", input: base, plan: plan),
                    CustomPlanRecord(name: "La mia scheda 2", input: base, plan: plan)]
        XCTAssertEqual(CustomPlanGenerator.suggestedName("La mia scheda", existing: recs), "La mia scheda 3")
        XCTAssertEqual(CustomPlanGenerator.suggestedName("La mia scheda", existing: []), "La mia scheda")
    }

    func testCodecRoundTrip() {
        let input = with { $0.sex = .female; $0.goal = .gain; $0.place = .home; $0.ownedEquipment = ["band", "dumbbell"] }
        let rec = CustomPlanRecord(id: "abc", name: "Gambe", createdAt: 1234, input: input,
                                   plan: CustomPlanGenerator.generate(input, catalog: catalog, seed: "abc"))
        let back = CustomPlanCodec.decodeJSON(CustomPlanCodec.encodeJSON([rec]))
        XCTAssertEqual(back, [rec])
        XCTAssertTrue(CustomPlanCodec.decodeJSON(Data("{}".utf8)).isEmpty)   // dati salvati prima: nessuna scheda
    }
}
