import XCTest
@testable import MyGymHelperCore

final class MuscleAndCatalogTests: XCTestCase {
    func testMuscleNameMapping() {
        XCTAssertEqual(MuscleGroup(apiName: "Biceps"), .biceps)
        XCTAssertEqual(MuscleGroup(apiName: "Lower Back"), .lowerBack)
        XCTAssertEqual(MuscleGroup(apiName: "Front-shoulders"), .shoulders)
        XCTAssertEqual(MuscleGroup(apiName: "Lateral deltoid"), .shoulders)
        XCTAssertEqual(MuscleGroup(apiName: "Abdominals"), .abs)
        XCTAssertEqual(MuscleGroup(apiName: "Lats"), .lats)
        XCTAssertNil(MuscleGroup(apiName: "xyz"))
    }

    func testRegions() {
        XCTAssertEqual(BodyRegion.arms.muscles.count, 3)
        XCTAssertTrue(MuscleGroup.quads.isLowerBody)
        XCTAssertFalse(MuscleGroup.chest.isLowerBody)
        // Glutei: zona a sé, fuori da Gambe, ma sempre parte bassa del corpo.
        XCTAssertEqual(BodyRegion.glutes.muscles, [.glutes])
        XCTAssertFalse(BodyRegion.legs.muscles.contains(.glutes))
        XCTAssertTrue(MuscleGroup.glutes.isLowerBody)
    }

    private let catalog = [
        CatalogExercise(id: "b", name: "Chest press", primary: [.chest]),
        CatalogExercise(id: "a", name: "Bench press", primary: [.chest]),
        CatalogExercise(id: "c", name: "Row", primary: [.lats])
    ]

    func testFreeSeesOnePerType() {
        let free = CatalogAccess.visible(catalog, tier: .free)
        XCTAssertEqual(free.map(\.id), ["a", "c"])
        XCTAssertEqual(CatalogAccess.visible(catalog, tier: .full).count, 3)
    }

    func testMatcherFindsSimilarName() {
        let cat = [CatalogExercise(id: "x", name: "Panca piana con bilanciere", primary: [.chest]),
                   CatalogExercise(id: "y", name: "Squat", primary: [.quads])]
        XCTAssertEqual(ExerciseMatcher.bestMatch(for: "Panca piana", in: cat)?.id, "x")
        XCTAssertNil(ExerciseMatcher.bestMatch(for: "Curl", in: cat))
    }

    func testSeedDecodeUsesLanguageAndFallback() throws {
        let json = """
        [{"id":"s1","muscles":["chest"],"secondary":["triceps"],"equipment":"barbell","mechanic":"compound",
          "names":{"it":"Panca","en":"Bench"},"steps":{"en":["Lie down"]}}]
        """.data(using: .utf8)!
        let it = try SeedCatalog.decode(json, language: "it")
        XCTAssertEqual(it.first?.name, "Panca")
        XCTAssertEqual(it.first?.steps, ["Lie down"])   // passo mancante in italiano: ripiega sull'inglese
        let fr = try SeedCatalog.decode(json, language: "fr")
        XCTAssertEqual(fr.first?.name, "Bench")
    }

    func testSeedDecodeReadsCategoryLevelAndPhotos() throws {
        let json = """
        [{"id":"fedb-X","muscles":["quads"],"equipment":"foamRoll","mechanic":"isolation","category":"stretching",
          "level":"beginner","images":["https://a/0.jpg","https://a/1.jpg"],"names":{"en":"X"},"steps":{"it":[],"en":["a"]}}]
        """.data(using: .utf8)!
        let e = try XCTUnwrap(SeedCatalog.decode(json, language: "it").first)
        XCTAssertEqual(e.kind, .stretching)
        XCTAssertEqual(e.level, "beginner")
        XCTAssertEqual(e.images.count, 2)
        XCTAssertEqual(e.steps, ["a"])          // passi italiani vuoti: si usano quelli inglesi
        XCTAssertFalse(e.isTraining)
        XCTAssertEqual(ExerciseKind.of("olympic"), .strength)
        XCTAssertEqual(ExerciseKind.of(""), .strength)
    }

    func testFreePrefersOurExercisesAndSkipsStretching() {
        let list = [
            CatalogExercise(id: "fedb-A", name: "A", primary: [.chest]),
            CatalogExercise(id: "seed-bench", name: "Bench", primary: [.chest]),
            CatalogExercise(id: "fedb-B", name: "Stretch", primary: [.lats], category: "stretching"),
            CatalogExercise(id: "fedb-C", name: "Row", primary: [.lats])
        ]
        XCTAssertEqual(CatalogAccess.visible(list, tier: .free).map(\.id), ["seed-bench", "fedb-C"])
        XCTAssertEqual(CatalogFilter.byKind(list, kind: .stretching).count, 1)
        XCTAssertEqual(CatalogFilter.byKind(list, kind: nil).count, 4)
    }

    /// L'elenco incluso nell'app: quasi 900 esercizi, id unici, tutti con muscoli riconosciuti e nome italiano.
    func testBundledSeedIsComplete() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../App/exercises_seed.json").standardized
        let data = try Data(contentsOf: url)
        let it = try SeedCatalog.decode(data, language: "it")
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [Any])
        XCTAssertEqual(it.count, raw.count)          // nessun esercizio scartato
        XCTAssertGreaterThan(it.count, 850)
        XCTAssertEqual(Set(it.map(\.id)).count, it.count)
        XCTAssertEqual(it.filter { $0.id.hasPrefix("seed-") }.count, 25)
        XCTAssertLessThan(it.filter { $0.images.isEmpty }.count, 5)    // la fonte non ha foto per 3 esercizi (Kettlebell Halo...)
        XCTAssertGreaterThan(it.filter { $0.kind == .stretching }.count, 100)
        XCTAssertTrue(it.first { $0.id == "fedb-Barbell_Deadlift" }?.name.contains("Stacco") ?? false)
    }
}

final class RecommenderTests: XCTestCase {
    func testPrefersUndertrainedMuscle() {
        let bench = CatalogExercise(id: "bench", name: "Bench", primary: [.chest], mechanic: .compound)
        let row = CatalogExercise(id: "row", name: "Row", primary: [.lats], mechanic: .compound)
        let curl = CatalogExercise(id: "curl", name: "Curl", primary: [.biceps], mechanic: .isolation)
        let now = Date()
        let history = [HistoryEntry(date: now, exerciseID: "bench", primary: [.chest], setsDone: 12)]
        let recs = ExerciseRecommender.recommend(from: [bench, row, curl], targets: [.chest, .lats], history: history, now: now)
        XCTAssertEqual(recs.first?.exercise.id, "row")
        XCTAssertEqual(recs.count, 2)   // il bicipite non e' tra i muscoli scelti
    }

    func testNeverRecommendsStretchingOrCardio() {
        let stretch = CatalogExercise(id: "s", name: "Stretch", primary: [.hamstrings], category: "stretching")
        let treadmill = CatalogExercise(id: "t", name: "Treadmill", primary: [.quads], category: "cardio")
        let roll = CatalogExercise(id: "r", name: "Roll", primary: [.quads], equipment: "foamRoll")
        let squat = CatalogExercise(id: "q", name: "Squat", primary: [.quads])
        let recs = ExerciseRecommender.recommend(from: [stretch, treadmill, roll, squat], targets: [], history: [])
        XCTAssertEqual(recs.map(\.exercise.id), ["q"])
    }
}

final class AdaptiveCoachTests: XCTestCase {
    private func session(weight: Double, planned: Int = 10, done: [Int], stopped: [Bool]? = nil, peaks: [Double]? = nil) -> SessionSample {
        let sets = done.enumerated().map { i, d in
            SessionSetSample(doneReps: d, plannedReps: planned,
                             stoppedEarly: stopped?[i] ?? (d < planned), averagePeak: peaks?[i] ?? 0)
        }
        return SessionSample(date: Date(), weightKg: weight, sets: sets)
    }

    func testNoHistoryUsesDefaultsAndPlan() {
        let a = AdaptiveCoach.advise(history: [], isCompound: false, defaultSets: 3, defaultReps: 10)
        XCTAssertEqual(a.reasonKeys, ["coach.nodata"])
        XCTAssertEqual(a.sets, 3); XCTAssertEqual(a.reps, 10); XCTAssertEqual(a.restSeconds, 75)
        let p = AdaptiveCoach.advise(history: [], isCompound: true, defaultSets: 3, defaultReps: 10,
                                     plan: PlanTarget(sets: 4, repsMin: 8, repsMax: 10, restSeconds: 90, weightKg: 60))
        XCTAssertEqual(p.sets, 4); XCTAssertEqual(p.reps, 8); XCTAssertEqual(p.restSeconds, 90); XCTAssertEqual(p.weightKg, 60)
    }

    func testProgressIncreasesWeight() {
        let a = AdaptiveCoach.advise(history: [session(weight: 100, done: [10, 10, 10])],
                                     isCompound: true, defaultSets: 3, defaultReps: 10)
        XCTAssertEqual(a.weightKg, 102.5, accuracy: 0.001)
        XCTAssertEqual(a.reasonKeys, ["coach.progress"])
        XCTAssertEqual(a.restSeconds, 120)
    }

    func testPlanRepRangeAddsRepsBeforeWeight() {
        let a = AdaptiveCoach.advise(history: [session(weight: 100, done: [10, 10, 10])], isCompound: true,
                                     defaultSets: 3, defaultReps: 10, plan: PlanTarget(repsMin: 8, repsMax: 12))
        XCTAssertEqual(a.reps, 11)
        XCTAssertEqual(a.weightKg, 100, accuracy: 0.001)
        XCTAssertEqual(a.reasonKeys, ["coach.morereps"])
    }

    func testTwoPoorSessionsDeload() {
        let poor = session(weight: 100, done: [5, 5, 5])
        let a = AdaptiveCoach.advise(history: [poor, poor], isCompound: true, defaultSets: 3, defaultReps: 10)
        XCTAssertEqual(a.weightKg, 90, accuracy: 0.001)
        XCTAssertTrue(a.reasonKeys.contains("coach.deload"))
    }

    func testPoorSessionReducesLoadAndSet() {
        let a = AdaptiveCoach.advise(history: [session(weight: 80, done: [5, 5, 5])],
                                     isCompound: false, defaultSets: 3, defaultReps: 10)
        XCTAssertEqual(a.weightKg, 72.5, accuracy: 0.001)
        XCTAssertEqual(a.sets, 2)
        XCTAssertEqual(a.reasonKeys, ["coach.reduce"])
    }

    func testHighFatigueKeepsLoadAndRestsMore() {
        let a = AdaptiveCoach.advise(history: [session(weight: 60, done: [10, 10, 10], peaks: [1.0, 0.9, 0.6])],
                                     isCompound: false, defaultSets: 3, defaultReps: 10)
        XCTAssertEqual(a.weightKg, 60, accuracy: 0.001)
        XCTAssertEqual(a.reasonKeys, ["coach.highfatigue"])
        XCTAssertEqual(a.restSeconds, 105)
    }

    func testBodyweightProgressesByReps() {
        let a = AdaptiveCoach.advise(history: [session(weight: 0, done: [10, 10])],
                                     isCompound: false, defaultSets: 2, defaultReps: 10)
        XCTAssertEqual(a.reps, 11)
        XCTAssertEqual(a.weightKg, 0)
    }
}

final class PlanParserTests: XCTestCase {
    private let sample = """
    Scheda forza - Mario
    Giorno A
    1. Panca piana 4x8-10 60kg rec 90s
    2) Croci con manubri 3 x 12 recupero 1'
    - Squat 5x5 80 kg pausa 2 min
    Giorno B
    Lat machine: 4 serie da 10 rec 75
    3x15 Curl bilanciere 20kg
    Note: bere acqua
    Venerdì
    Stacco 3x5 100kg rec 3"
    """

    func testParsesDaysAndEntries() {
        let plan = TrainingPlanParser.parse(sample)
        XCTAssertEqual(plan.days.count, 3)
        let bench = plan.days[0].entries[0]
        XCTAssertEqual(bench.name, "Panca piana")
        XCTAssertEqual(bench.sets, 4); XCTAssertEqual(bench.repsMin, 8); XCTAssertEqual(bench.repsMax, 10)
        XCTAssertEqual(bench.weightKg, 60); XCTAssertEqual(bench.restSeconds, 90)
        XCTAssertEqual(plan.days[0].entries[1].restSeconds, 60)
        XCTAssertEqual(plan.days[0].entries[2].restSeconds, 120)
        XCTAssertEqual(plan.days[1].entries[0].name, "Lat machine")
        XCTAssertEqual(plan.days[1].entries[0].restSeconds, 75)
        XCTAssertEqual(plan.days[1].entries[1].name, "Curl bilanciere")
        XCTAssertEqual(plan.days[2].entries[0].restSeconds, 180)
    }

    func testIgnoresLinesWithoutSets() {
        XCTAssertEqual(TrainingPlanParser.parse("Tempo totale 45 min\nBere acqua").days.count, 0)
    }

    func testNutritionParser() {
        let text = """
        Piano alimentare - 2200 kcal
        Proteine 150 g, carboidrati 250 g, grassi 70 g
        Colazione: latte e cereali
        - 1 banana
        Spuntino
        yogurt greco
        Cena
        pesce, verdure
        """
        let p = NutritionPlanParser.parse(text)
        XCTAssertEqual(p.calories, 2200); XCTAssertEqual(p.proteinG, 150)
        XCTAssertEqual(p.carbsG, 250); XCTAssertEqual(p.fatG, 70)
        XCTAssertEqual(p.meals.map(\.name), ["Colazione", "Spuntino", "Cena"])
        XCTAssertEqual(p.meals[0].items, ["latte e cereali", "1 banana"])
    }

    func testAIOutputIsValidatedAndClamped() {
        let output = """
        Ecco: {"days":[{"title":"A","entries":[{"name":"Squat","sets":99,"repsMin":5,"repsMax":5,"weightKg":80},{"name":"","sets":3}]}]} fine
        """
        let plan = PlanAIOutput.decodeTrainingPlan(from: output)
        XCTAssertEqual(plan?.days.first?.entries.count, 1)
        XCTAssertNil(plan?.days.first?.entries.first?.sets)      // 99 serie non e' plausibile
        XCTAssertEqual(plan?.days.first?.entries.first?.weightKg, 80)
        XCTAssertNil(PlanAIOutput.decodeTrainingPlan(from: "nessun json"))
    }
    /// Scheda a blocchi da Word/PDF (testo vero di una scheda di palestra). Come blockPlanFromWord in Kotlin.
    func testBlockPlanFromWord() {
        let text = [
            "Palestra - Avanzato",
            "Gambe e Glutei",
            "RISCALDAMENTO",
            "40” Gatto mucca",
            "40\" Mobilità anche in squat",
            "8 Hip thrust monopodalico gamba destra",
            "Settimana 1",
            "SET 1 DA RIPETERE 4 VOLTE (1.30 MIN DI RECUPERO)",
            "6 Low bar squat (o squat normale) (no al multipower) O SUMO SQUAT",
            "SET 3 (1.30 MIN DI RECUPERO)",
            "10 - 6 - 10 - 6 - 10 Hip Thrust con bilanciere",
            "SET 5 DA RIPETERE 3 VOLTE (60” DI RECUPERO)",
            "10 Abductor machine pesante + 8 Abductor machine con peso più basso + 8 Abductor",
            "machine con peso ancora più basso",
            "SET 6 DA RIPETERE 1 VOLTA",
            "60” Polpacci",
            "Defaticamento Post Allenamento per Gambe Leggere + Esercizio di Vacuum (Durata",
            "15 minuti)"
        ].joined(separator: "\n")
        let plan = TrainingPlanParser.parse(text)
        XCTAssertEqual(plan.days.map(\.title), ["RISCALDAMENTO", "Settimana 1"])
        let warm = plan.days[0].entries
        XCTAssertEqual(warm.map(\.name), ["Gatto mucca (40\")", "Mobilità anche in squat (40\")", "Hip thrust monopodalico gamba destra"])
        XCTAssertEqual(warm[2].repsMin, 8)
        let main = plan.days[1].entries
        XCTAssertEqual(main.count, 6)
        XCTAssertEqual(main[0].sets, 4); XCTAssertEqual(main[0].repsMin, 6); XCTAssertEqual(main[0].restSeconds, 90)
        XCTAssertEqual(main[1].name, "Hip Thrust con bilanciere")
        XCTAssertEqual(main[1].sets, 5); XCTAssertEqual(main[1].repsMin, 6); XCTAssertEqual(main[1].repsMax, 10)
        XCTAssertEqual(main[2..<5].map(\.name), ["Abductor machine pesante", "Abductor machine con peso più basso", "Abductor machine con peso ancora più basso"])
        XCTAssertTrue(main[2..<5].allSatisfy { $0.sets == 3 && $0.restSeconds == 60 })
        XCTAssertEqual(main[5].name, "Polpacci (60\")")
        XCTAssertNil(main[5].repsMin)
    }

    func testLeadingNumbersAreNotFoods() {
        XCTAssertNil(TrainingPlanParser.parseLeading("100 g riso basmati", blockSets: nil, blockRest: nil))
        XCTAssertNil(TrainingPlanParser.parseLeading("15 minuti)", blockSets: nil, blockRest: nil))
        XCTAssertEqual(TrainingPlanParser.blockHeader("SET 1 DA RIPETERE 4 VOLTE (1.30 MIN DI RECUPERO)")?.rest, 90)
        XCTAssertEqual(TrainingPlanParser.blockHeader("SET 1 DA RIPETERE 4 VOLTE (1.30 MIN DI RECUPERO)")?.sets, 4)
        XCTAssertNil(TrainingPlanParser.blockHeader("Serie A"))
    }
}

final class DietPlannerTests: XCTestCase {
    func testVeganExcludesAnimalFoods() {
        let proteins = DietPlanner.allowedFoods(for: [.vegan], category: .protein)
        XCTAssertFalse(proteins.contains("food.chicken"))
        XCTAssertFalse(proteins.contains("food.eggs"))
        XCTAssertFalse(proteins.contains("food.greekYogurt"))
        XCTAssertTrue(proteins.contains("food.tofu"))
    }

    func testGlutenFreeAndLactoseFree() {
        let carbs = DietPlanner.allowedFoods(for: [.glutenFree], category: .carbs)
        XCTAssertFalse(carbs.contains("food.pasta")); XCTAssertFalse(carbs.contains("food.bread"))
        XCTAssertTrue(carbs.contains("food.rice"))
        let dairy = DietPlanner.allowedFoods(for: [.lactoseFree], category: .protein)
        XCTAssertFalse(dairy.contains("food.greekYogurt"))
        XCTAssertTrue(dairy.contains("food.lactoseFreeYogurt"))
    }

    func testTrainingDayHasMoreCaloriesAndMealsAddUp() {
        let t = NutritionCalculator.targets(sex: .male, weightKg: 80, heightCm: 180, ageYears: 30, activity: .moderate, goal: .maintain)
        let rest = DietPlanner.plan(targets: t, diets: [.omnivore], trainingDay: false)
        let train = DietPlanner.plan(targets: t, diets: [.omnivore], trainingDay: true)
        XCTAssertGreaterThan(train.calories, rest.calories)
        XCTAssertEqual(rest.meals.count, 5)
        XCTAssertLessThanOrEqual(abs(rest.meals.map(\.calories).reduce(0, +) - rest.calories), 3)
    }
}
