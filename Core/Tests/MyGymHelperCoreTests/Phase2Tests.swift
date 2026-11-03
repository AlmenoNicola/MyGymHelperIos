import XCTest
@testable import MyGymHelperCore

final class WorkoutParametersTests: XCTestCase {
    func testClampAndRoundWeight() {
        let p = WorkoutParameters(sets: 20, reps: 0, restSeconds: 5, weightKg: 41.1).clamped()
        XCTAssertEqual(p.sets, 10)
        XCTAssertEqual(p.reps, 1)
        XCTAssertEqual(p.restSeconds, 15)
        XCTAssertEqual(p.weightKg, 41.0, accuracy: 0.001)       // arrotondato a 0,25 kg
        XCTAssertEqual(WorkoutParameters(sets: 3, reps: 10, restSeconds: 90, weightKg: 3.5).clamped().weightKg, 3.5, accuracy: 0.001)
        XCTAssertEqual(WorkoutParameters(sets: 3, reps: 10, restSeconds: 90, weightKg: 41.25).clamped().weightKg, 41.25, accuracy: 0.001)
    }

    func testWeightStepsUp() {
        // 0,5 kg fino a 4, 1 kg fino a 10, poi 5 kg
        var w = 0.0
        var seen: [Double] = []
        for _ in 0..<16 { w = WeightSteps.up(w); seen.append(w) }
        XCTAssertEqual(seen, [0.5, 1, 1.5, 2, 2.5, 3, 3.5, 4, 5, 6, 7, 8, 9, 10, 15, 20])
        XCTAssertEqual(WeightSteps.up(12.5), 15, accuracy: 0.001)    // fuori griglia: al valore successivo
        XCTAssertEqual(WeightSteps.up(3.7), 4, accuracy: 0.001)
        XCTAssertEqual(WeightSteps.up(4.25), 5, accuracy: 0.001)
        XCTAssertEqual(WeightSteps.up(498), 500, accuracy: 0.001)
        XCTAssertEqual(WeightSteps.up(500), 500, accuracy: 0.001)
    }

    func testWeightStepsDown() {
        var w = 20.0
        var seen: [Double] = []
        for _ in 0..<16 { w = WeightSteps.down(w); seen.append(w) }
        XCTAssertEqual(seen, [15, 10, 9, 8, 7, 6, 5, 4, 3.5, 3, 2.5, 2, 1.5, 1, 0.5, 0])
        XCTAssertEqual(WeightSteps.down(12.5), 10, accuracy: 0.001)  // fuori griglia: al valore precedente
        XCTAssertEqual(WeightSteps.down(10.5), 10, accuracy: 0.001)
        XCTAssertEqual(WeightSteps.down(4.25), 4, accuracy: 0.001)
        XCTAssertEqual(WeightSteps.down(0), 0, accuracy: 0.001)
        XCTAssertEqual(WeightSteps.down(0.3), 0, accuracy: 0.001)
    }

    func testWeightInputOnlyNumbers() {
        XCTAssertEqual(WeightInput.sanitize("62,5"), "62,5")
        XCTAssertEqual(WeightInput.sanitize("6a2.5kg"), "62.5")
        XCTAssertEqual(WeightInput.sanitize("12,5,3"), "12,53")         // un solo separatore: il secondo si ignora
        XCTAssertEqual(WeightInput.sanitize("1250,257"), "125,25")      // massimo 3 cifre intere e 2 decimali
        XCTAssertEqual(WeightInput.sanitize("-abc "), "")
        XCTAssertEqual(WeightInput.parse("62,5") ?? -1, 62.5, accuracy: 0.001)
        XCTAssertEqual(WeightInput.parse("62,") ?? -1, 62, accuracy: 0.001)
        XCTAssertEqual(WeightInput.parse(",5") ?? -1, 0.5, accuracy: 0.001)
        XCTAssertNil(WeightInput.parse(""))
        XCTAssertNil(WeightInput.parse(","))
        XCTAssertEqual(WeightInput.format(62, separator: ","), "62")
        XCTAssertEqual(WeightInput.format(62.5, separator: ","), "62,5")
        XCTAssertEqual(WeightInput.format(1.25, separator: "."), "1.25")
        XCTAssertEqual(WeightInput.format(0.05, separator: ","), "0,05")
    }

    func testFixedAdviceAllDoneLowerBody() {
        let outcomes = (1...3).map { _ in SetOutcome(plannedReps: 10, doneReps: 10, stoppedEarly: false) }
        let result = FixedCoaching.advise(sets: outcomes, isCompound: true, isLowerBody: true)
        let next = result.applied(to: WorkoutParameters(sets: 3, reps: 10, restSeconds: 90, weightKg: 60))
        XCTAssertEqual(next.weightKg, 62.5, accuracy: 0.001)
        XCTAssertEqual(next.sets, 4)
        XCTAssertEqual(next.restSeconds, 120)
    }

    func testFixedAdviceManyStopped() {
        let outcomes = [SetOutcome(plannedReps: 10, doneReps: 6, stoppedEarly: true),
                        SetOutcome(plannedReps: 10, doneReps: 5, stoppedEarly: true),
                        SetOutcome(plannedReps: 10, doneReps: 10, stoppedEarly: false)]
        let result = FixedCoaching.advise(sets: outcomes, isCompound: false, isLowerBody: false)
        let next = result.applied(to: WorkoutParameters(sets: 3, reps: 10, restSeconds: 60, weightKg: 20))
        XCTAssertEqual(next.weightKg, 17.5, accuracy: 0.001)   // 18 kg arrotondato in basso al passo di 1,25
        XCTAssertEqual(next.sets, 2)
        XCTAssertEqual(next.restSeconds, 105)
    }

    func testFixedAdviceBodyweightAddsRepInsteadOfLoad() {
        let outcomes = (1...2).map { _ in SetOutcome(plannedReps: 12, doneReps: 12, stoppedEarly: false) }
        let result = FixedCoaching.advise(sets: outcomes, isCompound: true, isLowerBody: false)
        let next = result.applied(to: WorkoutParameters(sets: 2, reps: 12, restSeconds: 90, weightKg: 0))
        XCTAssertEqual(next.weightKg, 0, accuracy: 0.001)
        XCTAssertEqual(next.reps, 13)
        XCTAssertEqual(next.sets, 2)   // con meno di 3 serie non si aggiunge una serie
    }

    func testAdaptiveKeepsCurrentWeightWithoutData() {
        let advice = AdaptiveCoach.advise(history: [], isCompound: true, defaultSets: 3, defaultReps: 10)
        XCTAssertEqual(advice.parameters(keepingWeight: 40).weightKg, 40, accuracy: 0.001)
    }
}

final class FoodFactsTests: XCTestCase {
    func testLenientDecoding() throws {
        let json = """
        {"products":[
          {"code":"8001","product_name":"Yogurt greco","brands":"Marca A, Marca B",
           "nutriments":{"energy-kcal_100g":"97","proteins_100g":9.5,"carbohydrates_100g":"3,8","fat_100g":5}},
          {"code":8002,"product_name":"","generic_name":"Riso","nutriments":{"energy_100g":1464}},
          {"code":"8003","product_name":"   "},
          {"product_name":"Senza codice"}
        ]}
        """.data(using: .utf8)!
        let items = try FoodFactsDecoder.decodeSearch(json)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].brand, "Marca A")
        XCTAssertEqual(items[0].kcal100g ?? 0, 97, accuracy: 0.01)
        XCTAssertEqual(items[0].carbs100g ?? 0, 3.8, accuracy: 0.01)
        XCTAssertEqual(items[1].id, "8002")
        XCTAssertEqual(items[1].name, "Riso")
        XCTAssertEqual(items[1].kcal100g ?? 0, 350, accuracy: 1)   // da kJ
        XCTAssertNil(items[1].protein100g)
    }

    func testImplausibleValuesAreDropped() throws {
        let json = #"{"products":[{"code":"1","product_name":"X","nutriments":{"proteins_100g":250,"fat_100g":-3}}]}"#.data(using: .utf8)!
        let item = try XCTUnwrap(FoodFactsDecoder.decodeSearch(json).first)
        XCTAssertNil(item.protein100g)
        XCTAssertNil(item.fat100g)
    }

    func testRequestHasUserAgentAndQuery() throws {
        let client = FoodFactsClient(userAgent: "MyGymHelper/1.0 (test@example.com)")
        XCTAssertNil(client.searchRequest(" a ", language: "it"))
        let request = try XCTUnwrap(client.searchRequest("yogurt greco", language: "it"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "MyGymHelper/1.0 (test@example.com)")
        let url = try XCTUnwrap(request.url?.absoluteString)
        XCTAssertTrue(url.contains("search_terms=yogurt%20greco"))
        XCTAssertTrue(url.contains("json=1"))
    }
}
