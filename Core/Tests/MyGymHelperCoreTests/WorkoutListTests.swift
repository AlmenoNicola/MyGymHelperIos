import XCTest
@testable import MyGymHelperCore

/// Elenchi di allenamento e scelta degli esercizi. Stessi casi di WorkoutListTests.kt.
final class WorkoutListTests: XCTestCase {
    private let bench = CatalogExercise(id: "bench", name: "Panca piana", primary: [.chest], secondary: [.triceps, .shoulders])
    private let dips = CatalogExercise(id: "dips", name: "Dip", primary: [.triceps], secondary: [.chest])
    private let curl = CatalogExercise(id: "curl", name: "Curl", primary: [.biceps])
    private let pushdown = CatalogExercise(id: "push", name: "Pushdown", primary: [.triceps])
    private let squat = CatalogExercise(id: "squat", name: "Squat", primary: [.quads], secondary: [.glutes])
    private var pool: [CatalogExercise] { [squat, pushdown, curl, dips, bench] }

    func testNoSelectionShowsEverythingByName() {
        XCTAssertEqual(WorkoutListLogic.browse(pool, selected: []).map(\.name), ["Curl", "Dip", "Panca piana", "Pushdown", "Squat"])
    }

    func testSelectionFiltersAndPutsFullMatchesFirst() {
        let selected: Set<MuscleGroup> = [.chest, .triceps]
        XCTAssertEqual(WorkoutListLogic.browse(pool, selected: selected).map(\.name), ["Dip", "Panca piana", "Pushdown"])
        XCTAssertTrue(WorkoutListLogic.coversAll(bench, selected: selected))
        XCTAssertTrue(WorkoutListLogic.coversAll(dips, selected: selected))
        XCTAssertFalse(WorkoutListLogic.coversAll(pushdown, selected: selected))
        // Con un solo muscolo scelto nessuno e' "in evidenza": lo allenerebbero tutti i risultati.
        XCTAssertFalse(WorkoutListLogic.coversAll(bench, selected: [.chest]))
        XCTAssertEqual(WorkoutListLogic.browse(pool, selected: [.quads]).map(\.name), ["Squat"])
        XCTAssertEqual(WorkoutListLogic.browse(pool, selected: [], query: " cur").map(\.name), ["Curl"])
    }

    func testListSearchByListNameShowsAllExercises() {
        XCTAssertEqual(ListSearch.match(listName: "Gambe e glutei", exercises: pool, query: "  ")?.map(\.id), pool.map(\.id))
        XCTAssertEqual(ListSearch.match(listName: "Gambe e glutei", exercises: pool, query: "GLUTEI")?.map(\.id), pool.map(\.id))
    }

    func testListSearchByExerciseShowsOnlyMatches() {
        XCTAssertEqual(ListSearch.match(listName: "Spinta", exercises: pool, query: "panca")?.map(\.name), ["Panca piana"])
        XCTAssertEqual(ListSearch.match(listName: "Spinta", exercises: pool, query: "push")?.map(\.name), ["Pushdown"])
        XCTAssertNil(ListSearch.match(listName: "Spinta", exercises: pool, query: "stacco"))
    }

    func testSecondaryOnlyMatchesAreHidden() {
        XCTAssertEqual(WorkoutListLogic.browse(pool, selected: [.glutes]), [])
    }

    func testNextPendingSkipsDoneAndWraps() {
        let a = WorkoutItem(exerciseID: "a", done: true)
        let b = WorkoutItem(exerciseID: "b")
        let c = WorkoutItem(exerciseID: "c", done: true)
        let d = WorkoutItem(exerciseID: "d")
        let items = [a, b, c, d]
        XCTAssertEqual(WorkoutListLogic.nextPending(items)?.id, b.id)
        XCTAssertEqual(WorkoutListLogic.nextPending(items, after: b.id)?.id, d.id)
        XCTAssertEqual(WorkoutListLogic.nextPending(items, after: d.id)?.id, b.id)
        XCTAssertNil(WorkoutListLogic.nextPending([a, c]))
        var bDone = b; bDone.done = true
        XCTAssertNil(WorkoutListLogic.nextPending([a, bDone], after: a.id))
    }

    func testLastSetNoticeAnnouncesNextExerciseOrEndOfDay() {
        let a = WorkoutItem(exerciseID: "bench")
        let b = WorkoutItem(exerciseID: "squat")
        let c = WorkoutItem(exerciseID: "missing")
        let all = pool
        let find: (String) -> CatalogExercise? = { id in all.first { $0.id == id } }
        XCTAssertEqual(WorkoutListLogic.lastSetNotice([a, b], currentItemID: a.id, exercise: find), .nextExercise(squat, position: .legThigh))
        // Dopo l'ultimo dell'elenco si riparte dal primo non svolto.
        XCTAssertEqual(WorkoutListLogic.lastSetNotice([a, b], currentItemID: b.id, exercise: find), .nextExercise(bench, position: .armUpper))
        // Nessun altro esercizio da fare: fine della giornata.
        var bDone = b; bDone.done = true
        var aDone = a; aDone.done = true
        XCTAssertEqual(WorkoutListLogic.lastSetNotice([a, bDone], currentItemID: a.id, exercise: find), .endOfDay)
        XCTAssertEqual(WorkoutListLogic.lastSetNotice([aDone], currentItemID: a.id, exercise: find), .endOfDay)
        // Esercizio non trovato nel catalogo, nessun elenco o esercizio fuori dall'elenco: solo "ultima serie".
        XCTAssertEqual(WorkoutListLogic.lastSetNotice([a, c], currentItemID: a.id, exercise: find), .lastSetOnly)
        XCTAssertEqual(WorkoutListLogic.lastSetNotice(nil, currentItemID: nil, exercise: find), .lastSetOnly)
        XCTAssertEqual(WorkoutListLogic.lastSetNotice([a, b], currentItemID: UUID(), exercise: find), .lastSetOnly)
    }

    func testRestBeforeLastSetNeedsTwoSets() {
        XCTAssertTrue(WorkoutListLogic.isRestBeforeLastSet(afterSet: 2, totalSets: 3))
        XCTAssertFalse(WorkoutListLogic.isRestBeforeLastSet(afterSet: 1, totalSets: 3))
        XCTAssertTrue(WorkoutListLogic.isRestBeforeLastSet(afterSet: 1, totalSets: 2))
        XCTAssertFalse(WorkoutListLogic.isRestBeforeLastSet(afterSet: 0, totalSets: 1))
    }

    func testItemParametersAreClamped() {
        let item = WorkoutItem(exerciseID: "a").with(WorkoutParameters(sets: 99, reps: 0, restSeconds: 5, weightKg: 61.3))
        XCTAssertEqual(item.parameters, WorkoutParameters(sets: 10, reps: 1, restSeconds: 15, weightKg: 61.25))
    }

    func testListEncodingRoundTrip() {
        let items = [WorkoutItem(exerciseID: "a", sets: 4, reps: 8, restSeconds: 120, weightKg: 62.5, done: true), WorkoutItem(exerciseID: "b")]
        XCTAssertEqual(WorkoutItem.decodeList(WorkoutItem.encodeList(items)), items)
        XCTAssertEqual(WorkoutItem.decodeList(Data()), [])
        XCTAssertEqual(WorkoutItem.decodeList(Data("x".utf8)), [])
    }

    func testSuggestedPosition() {
        XCTAssertEqual(WorkoutListLogic.suggestedPosition(squat), .legThigh)
        XCTAssertEqual(WorkoutListLogic.suggestedPosition(curl), .armUpper)
        XCTAssertEqual(WorkoutListLogic.suggestedPosition(nil), .armUpper)
    }

    func testAlternativeExercise() {
        // Si parte dai muscoli principali dell'esercizio originale, che non viene proposto.
        XCTAssertEqual(WorkoutListLogic.alternativeMuscles(bench), [.chest])
        XCTAssertEqual(WorkoutListLogic.alternatives(pool, original: bench, selected: [.chest, .triceps]).map(\.name), ["Dip", "Pushdown"])
        // Con attrezzo: parametri invariati; a corpo libero: stesse serie, ripetizioni e pausa, senza peso.
        let p = WorkoutParameters.of([SetTarget(reps: 12, weightKg: 40), SetTarget(reps: 10, weightKg: 45)], restSeconds: 90)
        XCTAssertEqual(WorkoutListLogic.alternativeParameters(p, alternative: dips), p)
        let pushUp = CatalogExercise(id: "pushup", name: "Piegamenti", primary: [.chest], equipment: "bodyweight")
        let bw = WorkoutListLogic.alternativeParameters(p, alternative: pushUp)
        XCTAssertEqual(bw.targets.map(\.reps), [12, 10])
        XCTAssertTrue(bw.targets.allSatisfy { $0.weightKg == 0 })
        XCTAssertEqual(bw.restSeconds, 90)
        // Mappa aperta sul retro solo se tutti i muscoli principali stanno dietro.
        XCTAssertFalse(WorkoutListLogic.alternativeOnBack(bench))
        XCTAssertTrue(WorkoutListLogic.alternativeOnBack(pushdown))
        // Sostituzione definitiva: stessa riga, nuovo esercizio e nuovi parametri.
        let item = WorkoutItem(exerciseID: "bench", sets: 4, reps: 8, restSeconds: 90, weightKg: 60, done: true)
        let replaced = WorkoutListLogic.replaceExercise(item, exerciseID: "pushup", parameters: bw)
        XCTAssertEqual(replaced.id, item.id)
        XCTAssertEqual(replaced.exerciseID, "pushup")
        XCTAssertEqual(replaced.parameters.targets, bw.targets)
        XCTAssertTrue(replaced.done)
    }
}
