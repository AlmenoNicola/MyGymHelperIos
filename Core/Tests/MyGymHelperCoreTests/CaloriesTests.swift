import XCTest
@testable import MyGymHelperCore

/// Calorie bruciate (stima). Stessi casi di CaloriesTests.kt.
final class CaloriesTests: XCTestCase {
    private func set(_ n: Int, _ reps: Int, _ seconds: Double) -> SetRecord {
        SetRecord(number: n, plannedReps: 10, doneReps: reps, stoppedEarly: false, durationSeconds: seconds)
    }

    func testActiveSeconds() {
        XCTAssertEqual(CalorieEstimator.activeSeconds(doneReps: 0, durationSeconds: 30), 0)
        XCTAssertEqual(CalorieEstimator.activeSeconds(doneReps: 10, durationSeconds: 0), 30)
        XCTAssertEqual(CalorieEstimator.activeSeconds(doneReps: 10, durationSeconds: 25), 25)
        XCTAssertEqual(CalorieEstimator.activeSeconds(doneReps: 10, durationSeconds: 5), 15)
        XCTAssertEqual(CalorieEstimator.activeSeconds(doneReps: 10, durationSeconds: 600), 80)
    }

    func testExerciseKcal() {
        let three = [set(1, 10, 30), set(2, 10, 30), set(3, 10, 30)]
        XCTAssertEqual(CalorieEstimator.exerciseKcal(sets: three, restSeconds: 90, isCompound: true, bodyWeightKg: 80), 36.0, accuracy: 1e-9)
        let lastEmpty = [set(1, 10, 30), set(2, 10, 30), set(3, 0, 4)]
        XCTAssertEqual(CalorieEstimator.exerciseKcal(sets: lastEmpty, restSeconds: 90, isCompound: true, bodyWeightKg: 80), 20.0, accuracy: 1e-9)
        XCTAssertEqual(CalorieEstimator.exerciseKcal(sets: [], restSeconds: 90, isCompound: true, bodyWeightKg: 80), 0)
        let one = [set(1, 12, 36)]
        XCTAssertEqual(CalorieEstimator.exerciseKcal(sets: one, restSeconds: 60, isCompound: false, bodyWeightKg: nil), 2.45, accuracy: 1e-9)
        XCTAssertEqual(CalorieEstimator.exerciseKcal(sets: one, restSeconds: 60, isCompound: false, bodyWeightKg: 0), 2.45, accuracy: 1e-9)
    }

    func testBodyWeight() {
        XCTAssertNil(CalorieEstimator.bodyWeight(weights: [], profileWeightKg: nil))
        XCTAssertEqual(CalorieEstimator.bodyWeight(weights: [], profileWeightKg: 82), 82)
        let log = [WeightEntry(at: 5000, kg: 78.5), WeightEntry(at: 1000, kg: 80)]
        XCTAssertEqual(CalorieEstimator.bodyWeight(weights: log, profileWeightKg: 82), 78.5)
    }

    func testListTotalAndDisplay() {
        let items = [WorkoutItem(exerciseID: "a", done: true, kcal: 20.4), WorkoutItem(exerciseID: "b", done: true, kcal: 15.3),
                     WorkoutItem(exerciseID: "c", done: false, kcal: 99)]
        XCTAssertEqual(CalorieEstimator.listKcal(items), 35.7, accuracy: 1e-9)
        XCTAssertEqual(CalorieEstimator.display(35.7), 36)
        XCTAssertEqual(CalorieEstimator.display(-3), 0)
    }

    func testWorkoutItemKeepsKcal() throws {
        let item = WorkoutItem(exerciseID: "a", done: true, kcal: 12.5)
        let back = try JSONDecoder().decode(WorkoutItem.self, from: JSONEncoder().encode(item))
        XCTAssertEqual(back.kcal, 12.5)
        // Elenchi salvati prima delle calorie: nessun valore
        let old = #"{"id":"\#(UUID().uuidString)","exerciseID":"a","sets":3,"reps":10,"restSeconds":90,"weightKg":0,"done":true}"#
        XCTAssertEqual(try JSONDecoder().decode(WorkoutItem.self, from: Data(old.utf8)).kcal, 0)
    }
}
