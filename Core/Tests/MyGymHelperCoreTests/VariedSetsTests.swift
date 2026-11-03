import XCTest
@testable import MyGymHelperCore

/// Serie diverse (ripetizioni e peso diversi sullo stesso esercizio). Stessi casi di VariedSetsTests.kt
/// (la parte sui dati salvati qui controlla la lettura JSON di elenchi e schede: lo storico iOS e' in SwiftData).
final class VariedSetsTests: XCTestCase {
    private let pyramid = [SetTarget(reps: 12, weightKg: 40), SetTarget(reps: 10, weightKg: 45), SetTarget(reps: 8, weightKg: 50)]

    func testParametersFromSets() {
        let equal = WorkoutParameters.of([SetTarget(reps: 10, weightKg: 40), SetTarget(reps: 10, weightKg: 40)], restSeconds: 90)
        XCTAssertFalse(equal.isVaried)
        XCTAssertEqual(equal, WorkoutParameters(sets: 2, reps: 10, restSeconds: 90, weightKg: 40))
        let varied = WorkoutParameters.of(pyramid, restSeconds: 90)
        XCTAssertTrue(varied.isVaried)
        XCTAssertEqual(varied.sets, 3); XCTAssertEqual(varied.reps, 12); XCTAssertEqual(varied.weightKg, 40)
        XCTAssertEqual(varied.targets, pyramid)
        XCTAssertEqual(varied.maxWeightKg, 50)
        XCTAssertEqual(varied.uniform().targets, Array(repeating: SetTarget(reps: 12, weightKg: 40), count: 3))
        // Limiti: al massimo 10 serie, ripetizioni 1-50, peso arrotondato a 0,25 kg.
        let wild = WorkoutParameters.of((0..<12).map { SetTarget(reps: $0 == 0 ? 80 : 5, weightKg: 10.1 + Double($0)) }, restSeconds: 5).clamped()
        XCTAssertEqual(wild.sets, 10); XCTAssertEqual(wild.targets[0].reps, 50); XCTAssertEqual(wild.targets[0].weightKg, 10)
        XCTAssertEqual(wild.restSeconds, 15)
        // Serie che diventano uguali dopo i limiti: tornano serie uguali.
        XCTAssertFalse(WorkoutParameters.of([SetTarget(reps: 60, weightKg: 0), SetTarget(reps: 50, weightKg: 0)], restSeconds: 90).clamped().isVaried)
    }

    func testEqualSetsBecomeOneRow() {
        let sets = [SetTarget(reps: 10, weightKg: 40), SetTarget(reps: 10, weightKg: 40), SetTarget(reps: 10, weightKg: 40),
                    SetTarget(reps: 8, weightKg: 50), SetTarget(reps: 8, weightKg: 50), SetTarget(reps: 10, weightKg: 40)]
        let rows = SetGroup.group(sets)
        XCTAssertEqual(rows, [SetGroup(count: 3, reps: 10, weightKg: 40), SetGroup(count: 2, reps: 8, weightKg: 50),
                              SetGroup(count: 1, reps: 10, weightKg: 40)])
        XCTAssertEqual(SetGroup.expand(rows), sets)
        XCTAssertEqual(SetGroup.group([]), [])
        XCTAssertEqual(SetGroup.expand([SetGroup(count: 0, reps: 10, weightKg: 40), SetGroup(count: 1, reps: 6, weightKg: 0)]),
                       [SetTarget(reps: 6, weightKg: 0)])
    }

    func testWorkoutItemKeepsTheSets() throws {
        let item = WorkoutItem(exerciseID: "bench").with(.of(pyramid, restSeconds: 90))
        XCTAssertEqual(item.perSet, pyramid)
        XCTAssertEqual(item.parameters.targets, pyramid)
        XCTAssertTrue(item.with(WorkoutParameters(sets: 3, reps: 10, restSeconds: 60, weightKg: 20)).perSet.isEmpty)
        // JSON: andata e ritorno; gli elenchi salvati prima non hanno "perSet".
        XCTAssertEqual(WorkoutItem.decodeList(WorkoutItem.encodeList([item])), [item])
        let old = #"[{"id":"8C3F5B2A-1D4E-4F6A-9B7C-2E1D3C4B5A69","exerciseID":"a","sets":3,"reps":10,"restSeconds":90,"weightKg":20,"done":false}]"#
        let decoded = WorkoutItem.decodeList(Data(old.utf8))
        XCTAssertEqual(decoded.count, 1)
        XCTAssertTrue(decoded[0].perSet.isEmpty)
    }

    func testSessionUsesTheRepsOfEachSet() {
        var e = SessionEngine(repsPerSet: [12, 10, 8], restSeconds: 60)
        XCTAssertEqual(e.totalSets, 3)
        _ = e.start(at: 0)
        XCTAssertEqual(e.targetReps, 12)
        _ = e.repsCounted(12, at: 30)
        guard case .resting = e.phase else { return XCTFail("attesa la pausa") }
        XCTAssertEqual(e.targetReps, 10)          // in pausa: obiettivo della prossima serie
        _ = e.skipRest(at: 40)
        _ = e.repsCounted(11, at: 60)             // oltre l'obiettivo: si ferma a 10
        XCTAssertEqual(e.records[1].doneReps, 10)
        _ = e.skipRest(at: 70)
        _ = e.stop(doneReps: 5, at: 90)
        XCTAssertEqual(e.records.map(\.plannedReps), [12, 10, 8])
        XCTAssertTrue(e.records[2].stoppedEarly)
        XCTAssertEqual(e.phase, .finished)
        // Inizializzatore con serie uguali come prima.
        let same = SessionEngine(sets: 2, reps: 10, restSeconds: 60)
        XCTAssertEqual([same.targetReps(forSet: 1), same.targetReps(forSet: 2)], [10, 10])
    }

    func testFixedCoachingKeepsTheScheme() {
        let done = pyramid.map { SetOutcome(plannedReps: $0.reps, doneReps: $0.reps, stoppedEarly: false) }
        let advice = FixedCoaching.advise(sets: done, isCompound: false, isLowerBody: false)
        let p = advice.applied(to: .of(pyramid, restSeconds: 90))
        XCTAssertEqual(p.targets, [SetTarget(reps: 12, weightKg: 41.25), SetTarget(reps: 10, weightKg: 46.25),
                                   SetTarget(reps: 8, weightKg: 51.25), SetTarget(reps: 8, weightKg: 51.25)])
        XCTAssertEqual(p.restSeconds, 75)
        // Corpo libero in una serie: +1 ripetizione su quella serie.
        let mixed = WorkoutParameters.of([SetTarget(reps: 10, weightKg: 0), SetTarget(reps: 8, weightKg: 20)], restSeconds: 90)
        let q = FixedCoaching.advise(sets: [SetOutcome(plannedReps: 10, doneReps: 10, stoppedEarly: false),
                                            SetOutcome(plannedReps: 8, doneReps: 8, stoppedEarly: false)],
                                     isCompound: false, isLowerBody: false).applied(to: mixed)
        XCTAssertEqual(q.targets, [SetTarget(reps: 11, weightKg: 0), SetTarget(reps: 8, weightKg: 21.25)])
        // Molte serie interrotte: -10% su ogni serie e una serie in meno.
        let bad = FixedCoaching.advise(sets: [SetOutcome(plannedReps: 12, doneReps: 6, stoppedEarly: true),
                                              SetOutcome(plannedReps: 10, doneReps: 5, stoppedEarly: true),
                                              SetOutcome(plannedReps: 8, doneReps: 8, stoppedEarly: false)],
                                       isCompound: false, isLowerBody: false).applied(to: .of(pyramid, restSeconds: 90))
        XCTAssertEqual(bad.targets, [SetTarget(reps: 12, weightKg: 35), SetTarget(reps: 10, weightKg: 40)])
    }

    func testAdaptiveCoachKeepsTheScheme() {
        let sample = SessionSample(date: Date(timeIntervalSince1970: 0), weightKg: 50,
                                   sets: pyramid.map { SessionSetSample(doneReps: $0.reps, plannedReps: $0.reps, stoppedEarly: false) })
        let advice = AdaptiveCoach.advise(history: [sample], isCompound: true, defaultSets: 3, defaultReps: 12)
        XCTAssertEqual(advice.reasonKeys, ["coach.progress"])
        let p = advice.parameters(from: .of(pyramid, restSeconds: 90))
        XCTAssertEqual(p.targets, [SetTarget(reps: 12, weightKg: 41.25), SetTarget(reps: 10, weightKg: 46.25), SetTarget(reps: 8, weightKg: 51.25)])
        XCTAssertEqual(p.restSeconds, 120)
        // Serie uguali: come prima.
        XCTAssertEqual(advice.parameters(from: WorkoutParameters(sets: 3, reps: 10, restSeconds: 90, weightKg: 40)),
                       advice.parameters(keepingWeight: 40))
    }

    func testRepeatedRowsBecomeOneExercise() {
        let plan = TrainingPlan(days: [
            PlanDay(title: "A", entries: [
                PlanEntry(name: "Panca piana", sets: 2, repsMin: 10, repsMax: 10, weightKg: 40),
                PlanEntry(name: "Croci", sets: 3, repsMin: 12, repsMax: 12),
                PlanEntry(name: "panca  piana", sets: 2, repsMin: 8, repsMax: 8, restSeconds: 90, weightKg: 50, exerciseID: "bench"),
                PlanEntry(name: "Plank (40\")", sets: 1),
                PlanEntry(name: "Plank (40\")", sets: 1)
            ]),
            PlanDay(title: "B", entries: [PlanEntry(name: "Panca piana", sets: 3, repsMin: 6, repsMax: 6)])
        ])
        let merged = PlanAI.mergeRepeated(plan)
        let a = merged.days[0].entries
        XCTAssertEqual(a.map(\.name), ["Panca piana", "Croci", "Plank (40\")", "Plank (40\")"])
        let bench = a[0]
        XCTAssertEqual(bench.sets, 4)
        XCTAssertEqual(bench.perSet, [PlanSet(reps: 10, weightKg: 40), PlanSet(reps: 10, weightKg: 40),
                                      PlanSet(reps: 8, weightKg: 50), PlanSet(reps: 8, weightKg: 50)])
        XCTAssertEqual(bench.restSeconds, 90)
        XCTAssertEqual(bench.exerciseID, "bench")
        XCTAssertEqual(bench.target.perSet, [SetTarget(reps: 10, weightKg: 40), SetTarget(reps: 10, weightKg: 40),
                                             SetTarget(reps: 8, weightKg: 50), SetTarget(reps: 8, weightKg: 50)])
        // Ogni giorno per conto suo.
        XCTAssertEqual(merged.days[1].entries[0].sets, 3)
        XCTAssertTrue(merged.days[1].entries[0].perSet.isEmpty)
        // Righe uguali: una voce normale con le serie sommate.
        let same = PlanAI.mergeRepeated(TrainingPlan(days: [PlanDay(title: "", entries: [
            PlanEntry(name: "Curl", sets: 2, repsMin: 8, repsMax: 12, weightKg: 10),
            PlanEntry(name: "Curl", sets: 1, repsMin: 8, repsMax: 12, weightKg: 10)])])).allEntries
        XCTAssertEqual(same.count, 1)
        XCTAssertEqual(same[0].sets, 3); XCTAssertEqual(same[0].repsMin, 8); XCTAssertEqual(same[0].repsMax, 12)
        XCTAssertTrue(same[0].perSet.isEmpty)
    }

    func testMissingDataOnVariedSets() {
        let e = PlanEntry(name: "Panca", sets: 3, perSet: [PlanSet(reps: 10, weightKg: 40), PlanSet(reps: nil, weightKg: 45), PlanSet(reps: 8, weightKg: nil)])
        XCTAssertEqual(PlanAI.missing(e), [.reps, .weight])
        var ok = e; ok.perSet = [PlanSet(reps: 10, weightKg: 40), PlanSet(reps: 8, weightKg: 45)]
        XCTAssertEqual(PlanAI.missing(ok), [])
        // Ripetizioni mancanti in una serie: si usano quelle della voce (o 10).
        XCTAssertEqual(e.target.perSet.map(\.reps), [10, 10, 8])
    }

    func testSavedPlansKeepTheSets() throws {
        let plan = TrainingPlan(days: [PlanDay(title: "A", entries: [
            PlanEntry(name: "Panca", sets: 2, perSet: [PlanSet(reps: 10, weightKg: 40), PlanSet(reps: nil, weightKg: 50)])])])
        let back = try JSONDecoder().decode(TrainingPlan.self, from: JSONEncoder().encode(plan))
        XCTAssertEqual(back, plan)
        // Schede salvate prima: senza "perSet".
        let old = #"{"days":[{"id":"8C3F5B2A-1D4E-4F6A-9B7C-2E1D3C4B5A69","title":"A","entries":[{"id":"9C3F5B2A-1D4E-4F6A-9B7C-2E1D3C4B5A69","name":"Panca","sets":3}]}]}"#
        let decoded = try JSONDecoder().decode(TrainingPlan.self, from: Data(old.utf8))
        XCTAssertTrue(decoded.allEntries[0].perSet.isEmpty)
        XCTAssertEqual(decoded.allEntries[0].sets, 3)
    }

    func testReviewEditsKeepTheEntryInStep() {
        let e = PlanEntry(name: "Panca").withSets([PlanSet(reps: nil, weightKg: nil), PlanSet(reps: 8, weightKg: 50), PlanSet(reps: 6, weightKg: 55)])
        XCTAssertEqual(e.sets, 3); XCTAssertEqual(e.repsMin, 8); XCTAssertEqual(e.repsMax, 8); XCTAssertEqual(e.weightKg, 50)
    }
}
