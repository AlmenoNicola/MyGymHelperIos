import XCTest
@testable import MyGymHelperCore

/// Lettura delle schede con l'AI: tutto quello che non dipende dal modello (come PlanAITests.kt).
final class PlanAITests: XCTestCase {
    private let text = [
        "RISCALDAMENTO", "40” Gatto mucca", "8 Hip thrust monopodalico gamba destra", "Settimana 1",
        "SET 1 DA RIPETERE 4 VOLTE (1.30 MIN DI RECUPERO)", "6 Low bar squat (o squat normale) O SUMO SQUAT",
        "SET 3 (1.30 MIN DI RECUPERO)", "10 - 6 - 10 - 6 - 10 Hip Thrust con bilanciere",
        "SET 6 DA RIPETERE 1 VOLTA", "60” Polpacci"].joined(separator: "\n")

    func testEntriesAreChecked() {
        let timed = PlanAI.entry(name: " Gatto  mucca ", sets: nil, repsMin: 8, repsMax: nil, restSeconds: nil, weightKg: nil, seconds: 40)
        XCTAssertEqual(timed?.name, "Gatto mucca (40\")")
        XCTAssertNil(timed?.repsMin)                                  // a tempo: niente ripetizioni
        let ht = PlanAI.entry(name: "Hip Thrust", sets: 5, repsMin: 10, repsMax: 6, restSeconds: 90, weightKg: 0, seconds: nil)
        XCTAssertEqual(ht?.repsMin, 6); XCTAssertEqual(ht?.repsMax, 10)
        XCTAssertNil(ht?.weightKg)                                    // 0 kg = valore mancante
        let panca = PlanAI.entry(name: "Panca", sets: 99, repsMin: 8, repsMax: 8, restSeconds: nil, weightKg: 700, seconds: nil)
        XCTAssertNil(panca?.sets); XCTAssertNil(panca?.weightKg)
        XCTAssertNil(PlanAI.entry(name: "ab", sets: 3, repsMin: 8, repsMax: 8, restSeconds: nil, weightKg: nil, seconds: nil))
    }

    func testInventedExercisesAreDropped() {
        let ai = TrainingPlan(days: [
            PlanDay(title: "Settimana 1", entries: [PlanEntry(name: "Low bar squat", sets: 4), PlanEntry(name: "Leg press orizzontale")]),
            PlanDay(title: "", entries: [PlanEntry(name: "Polpaccio (60\")")])])
        let plan = PlanAI.ground([ai], text: text)
        XCTAssertEqual(plan?.days.count, 1)                           // il giorno senza titolo si unisce a quello prima
        XCTAssertEqual(plan?.allEntries.map(\.name), ["Low bar squat", "Polpaccio (60\")"])
    }

    func testAIIsUsedOnlyWhenItFindsEnough() {
        let rules = TrainingPlanParser.parse(text)
        let few = TrainingPlan(days: [PlanDay(title: "", entries: [PlanEntry(name: "Squat")])])
        XCTAssertFalse(PlanAI.choose(rules: rules, ai: few).usedAI)
        XCTAssertFalse(PlanAI.choose(rules: rules, ai: nil).usedAI)
        XCTAssertTrue(PlanAI.choose(rules: rules, ai: TrainingPlan(days: [PlanDay(title: "", entries: rules.allEntries)])).usedAI)
    }

    func testChunksKeepTheBlockHeader() {
        let long = (1...40).map { "10 Esercizio numero \($0) con manubri" }.joined(separator: "\n")
        let chunks = PlanAI.chunks("Giorno A\nSET 1 DA RIPETERE 3 VOLTE (60” DI RECUPERO)\n" + long, max: 400)
        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 500 })
        XCTAssertTrue(chunks.dropFirst().allSatisfy { $0.hasPrefix("Giorno A\nSET 1") })
    }

    func testCatalogMatching() {
        func ex(_ id: String, _ name: String) -> CatalogExercise {
            CatalogExercise(id: id, name: name, primary: [], secondary: [], equipment: "", mechanic: .compound, steps: [])
        }
        let catalog = [ex("a", "Squat con bilanciere"), ex("b", "Hip thrust con bilanciere"),
                       ex("c", "Calf raise in piedi (polpacci)"), ex("d", "Panca piana")]
        let names = ["Hip Thrust con bilanciere", "Polpacci (60\")", "Gatto mucca (40\")"]
        let cands = names.map { PlanAI.candidates(for: $0, in: catalog) }
        XCTAssertEqual(cands[0].first?.id, "b")
        XCTAssertTrue(cands[2].isEmpty)
        XCTAssertTrue(PlanAI.matchPrompt(names: names, candidates: cands).contains("2. Polpacci (60\") -> candidati: c = Calf raise in piedi (polpacci)"))
        XCTAssertEqual(PlanAI.validMatches([(1, "b"), (2, "c"), (3, "d"), (4, "a")], candidates: cands), [0: "b", 1: "c"])
        let plan = TrainingPlan(days: [PlanDay(title: "", entries: names.map { PlanEntry(name: $0) })])
        XCTAssertEqual(PlanAI.applyMatches(plan, catalog: catalog, chosen: [1: "c"]).allEntries.map(\.exerciseID), ["b", "c", nil])
        XCTAssertEqual(PlanAI.applyMatches(plan, catalog: catalog, chosen: nil).allEntries.map(\.exerciseID), ["b", nil, nil])
    }

    func testMissingDataIsCompletedFromRulesThenReported() {
        let rules = TrainingPlan(days: [PlanDay(title: "Giorno A", entries: [
            PlanEntry(name: "Panca piana", sets: 4, repsMin: 8, repsMax: 8, restSeconds: 90, weightKg: 60),
            PlanEntry(name: "Squat con bilanciere", sets: 3, repsMin: 10, repsMax: 10),
            PlanEntry(name: "Plank (40\")", sets: 3)])])
        let ai = TrainingPlan(days: [PlanDay(title: "Giorno A", entries: [
            PlanEntry(name: "Panca piana", sets: 5, repsMin: 6, repsMax: 6),      // l'AI ha letto 5x6 ma non il peso
            PlanEntry(name: "Squat con bilanciere"),                                // l'AI ha letto solo il nome
            PlanEntry(name: "Plank (40\")"),
            PlanEntry(name: "Crunch")])])                                         // le regole non l'hanno trovato
        let c = PlanAI.combine(rules: rules, ai: ai)
        XCTAssertTrue(c.usedAI)
        let e = c.plan.allEntries
        // i valori dell'AI restano, quelli mancanti arrivano dalle regole
        XCTAssertEqual(e[0].sets, 5); XCTAssertEqual(e[0].repsMin, 6); XCTAssertEqual(e[0].weightKg, 60); XCTAssertEqual(e[0].restSeconds, 90)
        XCTAssertEqual(e[1].sets, 3); XCTAssertEqual(e[1].repsMin, 10); XCTAssertEqual(e[1].repsMax, 10); XCTAssertNil(e[1].weightKg)
        XCTAssertEqual(e[2].sets, 3)
        XCTAssertNil(e[3].sets)
        // quello che manca ancora va confermato dall'utente
        let gaps = PlanAI.gaps(c.plan)
        XCTAssertEqual(gaps.map(\.name), ["Squat con bilanciere", "Plank (40\")", "Crunch"])
        XCTAssertEqual(gaps[0].day, "Giorno A")
        XCTAssertEqual(gaps[0].missing, [.weight])
        XCTAssertEqual(gaps[1].missing, [.weight])                                // a tempo: le ripetizioni non servono
        XCTAssertEqual(gaps[2].missing, [.sets, .reps, .weight])
        XCTAssertTrue(PlanAI.isTimed(e[2])); XCTAssertFalse(PlanAI.isTimed(e[0]))
        // senza AI resta la lettura delle regole; le voci senza nome non contano
        XCTAssertFalse(PlanAI.combine(rules: rules, ai: nil).usedAI)
        XCTAssertTrue(PlanAI.gaps(TrainingPlan(days: [PlanDay(title: "", entries: [PlanEntry(name: " ")])])).isEmpty)
    }

    func testSameExerciseIsCompletedOnceInOrder() {
        let rules = TrainingPlan(days: [
            PlanDay(title: "Giorno A", entries: [PlanEntry(name: "Squat", sets: 3, repsMin: 10, repsMax: 10)]),
            PlanDay(title: "Giorno B", entries: [PlanEntry(name: "Squat", sets: 5, repsMin: 5, repsMax: 5, weightKg: 80)])])
        let ai = TrainingPlan(days: [
            PlanDay(title: "Giorno A", entries: [PlanEntry(name: "Squat")]),
            PlanDay(title: "Giorno B", entries: [PlanEntry(name: "Squat")])])
        let out = PlanAI.complete(ai, with: rules).allEntries
        XCTAssertEqual(out.map(\.sets), [3, 5])
        XCTAssertEqual(out.map(\.weightKg), [nil, 80])
        XCTAssertTrue(PlanAI.sameName("Low bar squat", "Low bar squat (o squat normale) O SUMO SQUAT"))
        XCTAssertFalse(PlanAI.sameName("Squat", "Hip thrust con bilanciere"))
    }
}
