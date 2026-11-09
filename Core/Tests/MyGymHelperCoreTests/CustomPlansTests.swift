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
        // Da 1 a 7 allenamenti: fuori dai limiti si torna a 1 o a 7
        XCTAssertEqual(with { $0.daysPerWeek = 6 }.clamped().daysPerWeek, 6)
        XCTAssertEqual(with { $0.daysPerWeek = 1 }.clamped().daysPerWeek, 1)
        XCTAssertEqual(with { $0.daysPerWeek = 9 }.clamped().daysPerWeek, 7)
        XCTAssertEqual(with { $0.daysPerWeek = 0 }.clamped().daysPerWeek, 1)
    }

    func testOneDayIsSingleFullBody() {
        let p = CustomPlanGenerator.generate(with { $0.daysPerWeek = 1 }, catalog: catalog, seed: "s1d")
        XCTAssertEqual(p.days.map(\.titleKey), ["presets.day.single"])
        XCTAssertEqual(p.daysPerWeek, 1)
        XCTAssertEqual(p.days[0].items.count, 5)
    }

    func testFiveDaysIsUpperLowerPushPullLegs() {
        let p = CustomPlanGenerator.generate(with { $0.experience = .intermediate; $0.daysPerWeek = 5 }, catalog: catalog, seed: "s5")
        XCTAssertEqual(p.days.map(\.titleKey), ["presets.day.upper", "presets.day.lower", "presets.day.push",
                                                "presets.day.pull", "presets.day.legs"])
        XCTAssertTrue(p.days.allSatisfy { $0.items.count == 6 })
    }

    func testSixAndSevenDays() {
        let six = CustomPlanGenerator.generate(with { $0.experience = .advanced; $0.daysPerWeek = 6 }, catalog: catalog, seed: "s6")
        let ppl = ["presets.day.pushA", "presets.day.pullA", "presets.day.legsA",
                   "presets.day.pushB", "presets.day.pullB", "presets.day.legsB"]
        XCTAssertEqual(six.days.map(\.titleKey), ppl)
        for d in six.days {
            let ids = d.items.map(\.exerciseID)
            XCTAssertEqual(ids.count, Set(ids).count, d.titleKey)          // mai lo stesso esercizio nello stesso giorno
        }
        let seven = CustomPlanGenerator.generate(with { $0.experience = .advanced; $0.daysPerWeek = 7; $0.goal = .lose },
                                                 catalog: catalog, seed: "s7")
        XCTAssertEqual(seven.days.map(\.titleKey), ppl + [CustomPlanGenerator.stretchingDayKey])
        XCTAssertEqual(seven.daysPerWeek, 7)
        let stretch = seven.days.last!.items
        XCTAssertFalse(stretch.isEmpty)
        XCTAssertTrue(stretch.allSatisfy { byID[$0.exerciseID]?.kind == .stretching })
    }

    func testManyDaysBeginnerNote() {
        XCTAssertFalse(CustomPlanGenerator.notes(with { $0.daysPerWeek = 4 }).manyDaysBeginner)
        XCTAssertTrue(CustomPlanGenerator.notes(with { $0.daysPerWeek = 5 }).manyDaysBeginner)
        XCTAssertFalse(CustomPlanGenerator.notes(with { $0.experience = .intermediate; $0.daysPerWeek = 6 }).manyDaysBeginner)
        let k6 = CustomPlanGenerator.notes(with { $0.daysPerWeek = 6 }).dailyCalories
        let k4 = CustomPlanGenerator.notes(with { $0.daysPerWeek = 4 }).dailyCalories
        let k1 = CustomPlanGenerator.notes(with { $0.daysPerWeek = 1 }).dailyCalories
        XCTAssertGreaterThan(k6, k4)
        XCTAssertGreaterThan(k4, k1)
    }

    func testTwoDaysIsFullBodyForEveryLevel() {
        for e in Experience.allCases {
            let p = CustomPlanGenerator.generate(with { $0.experience = e; $0.daysPerWeek = 2 }, catalog: catalog, seed: "s2")
            XCTAssertEqual(p.days.map(\.titleKey), ["presets.day.a", "presets.day.b"], "\(e)")
            XCTAssertEqual(p.daysPerWeek, 2)
            XCTAssertTrue(p.days.allSatisfy { $0.items.count == CustomPlanGenerator.exercisesPerDay(e) }, "\(e)")
            let ids = p.days.flatMap { $0.items.map(\.exerciseID) }
            XCTAssertEqual(ids.count, Set(ids).count, "\(e)")
        }
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
