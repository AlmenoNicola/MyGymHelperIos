import XCTest
@testable import MyGymHelperCore

final class RepDetectorTests: XCTestCase {
    /// Segnale sinusoidale sintetico a 50 Hz: `reps` ripetizioni a `freq` Hz, ampiezza `amp` (g),
    /// con un disturbo sinusoidale ad alta frequenza.
    private func run(freq: Double, amp: Double, reps: Int, jitter: Double = 0, jitterHz: Double = 9) -> RepDetector {
        var d = RepDetector()
        let sr = 50.0, lead = 1.0, tail = 2.0
        let dur = Double(reps) / freq
        let n = Int((lead + dur + tail) * sr)
        for i in 0..<n {
            let t = Double(i) / sr
            let tt = t - lead
            var v = (tt >= 0 && tt <= dur) ? amp * sin(2 * .pi * freq * tt) : 0
            v += jitter * sin(2 * .pi * jitterHz * t)
            d.process(v, at: t)
        }
        return d
    }

    func testSlowTenReps() { XCTAssertEqual(run(freq: 0.5, amp: 0.5, reps: 10).count, 10) }
    func testFastFiveReps() { XCTAssertEqual(run(freq: 1.0, amp: 0.4, reps: 5).count, 5) }
    func testNoiseOnlyCountsNothing() { XCTAssertEqual(run(freq: 0.5, amp: 0, reps: 10, jitter: 0.03, jitterHz: 7).count, 0) }
    func testNoisyEightReps() { XCTAssertEqual(run(freq: 0.4, amp: 0.5, reps: 8, jitter: 0.05).count, 8) }
    func testTinyMotionCountsNothing() { XCTAssertEqual(run(freq: 0.5, amp: 0.05, reps: 6).count, 0) }

    func testPrincipalAxisFindsDominantDirection() {
        let samples = (0..<200).map { i -> Vector3 in
            let a = sin(Double(i) * 0.2)
            return Vector3(0.9 * a, 0.1 * a, 0.01 * cos(Double(i)))
        }
        let axis = PrincipalAxis.estimate(from: samples)!
        XCTAssertGreaterThan(abs(axis.x), 0.95)
    }
}

final class BMITests: XCTestCase {
    func testNormalBMI() {
        let r = BMICalculator.calculate(weightKg: 70, heightCm: 175)!
        XCTAssertEqual(r.value, 22.86, accuracy: 0.01)
        XCTAssertEqual(r.category, .normal)
    }
    func testInvalidInput() { XCTAssertNil(BMICalculator.calculate(weightKg: 0, heightCm: 170)) }
}

final class NutritionTests: XCTestCase {
    func testBMRMale() { XCTAssertEqual(NutritionCalculator.bmr(sex: .male, weightKg: 80, heightCm: 180, ageYears: 30), 1780, accuracy: 0.01) }
    func testBMRFemale() { XCTAssertEqual(NutritionCalculator.bmr(sex: .female, weightKg: 60, heightCm: 165, ageYears: 25), 1345.25, accuracy: 0.01) }
    func testTargetsLoseIsBelowMaintain() {
        let lose = NutritionCalculator.targets(sex: .male, weightKg: 80, heightCm: 180, ageYears: 30, activity: .moderate, goal: .lose)
        let keep = NutritionCalculator.targets(sex: .male, weightKg: 80, heightCm: 180, ageYears: 30, activity: .moderate, goal: .maintain)
        XCTAssertLessThan(lose.calories, keep.calories)
    }

    func testThreeGoalsAndRecommendation() {
        let all = NutritionCalculator.allTargets(sex: .male, weightKg: 80, heightCm: 180, ageYears: 30, activity: .moderate)
        // 1780 x 1,55 = 2759: dimagrire -15%, aumentare +10%
        XCTAssertEqual(all[.maintain]?.calories, 2759)
        XCTAssertEqual(all[.lose]?.calories, 2345)
        XCTAssertEqual(all[.gain]?.calories, 3035)
        XCTAssertEqual(NutritionCalculator.recommendedGoal(.underweight), .gain)
        XCTAssertEqual(NutritionCalculator.recommendedGoal(.normal), .maintain)
        XCTAssertEqual(NutritionCalculator.recommendedGoal(.overweight), .lose)
        XCTAssertEqual(NutritionCalculator.recommendedGoal(.obese), .lose)
        // Senza scelta si usa il consiglio del BMI (100 kg, 175 cm = 32,7: obesita' -> dimagrire); con la scelta, quella.
        XCTAssertEqual(NutritionCalculator.effectiveGoal(chosen: false, goalRaw: "maintain", weightKg: 100, heightCm: 175), .lose)
        XCTAssertEqual(NutritionCalculator.effectiveGoal(chosen: true, goalRaw: "maintain", weightKg: 100, heightCm: 175), .maintain)
        XCTAssertEqual(NutritionCalculator.effectiveGoal(chosen: false, goalRaw: "maintain", weightKg: 50, heightCm: 175), .gain)
    }
}

final class FeatureGateTests: XCTestCase {
    func testFreeHasBMIAndCounting() {
        XCTAssertTrue(FeatureGate.isAvailable(.bmi, for: .free))
        XCTAssertTrue(FeatureGate.isAvailable(.repCounting, for: .free))
        XCTAssertFalse(FeatureGate.isAvailable(.catalogFull, for: .free))
    }
    func testWatchIsMidAndUp() {
        XCTAssertFalse(FeatureGate.isAvailable(.appleWatch, for: .free))
        XCTAssertTrue(FeatureGate.isAvailable(.appleWatch, for: .mid))
        XCTAssertTrue(FeatureGate.isAvailable(.appleWatch, for: .full))
    }
    func testAdaptiveOnlyFull() {
        XCTAssertFalse(FeatureGate.isAvailable(.adaptiveCoaching, for: .mid))
        XCTAssertTrue(FeatureGate.isAvailable(.adaptiveCoaching, for: .full))
    }
}

final class FixedCoachingTests: XCTestCase {
    func testAllCompletedIncreasesWeightAndAddsSet() {
        let sets = (0..<3).map { _ in SetOutcome(plannedReps: 10, doneReps: 10, stoppedEarly: false) }
        let r = FixedCoaching.advise(sets: sets, isCompound: true, isLowerBody: true)
        XCTAssertTrue(r.advice.contains(.increaseWeight(byKg: 2.5)))
        XCTAssertTrue(r.advice.contains(.addSet))
        XCTAssertEqual(r.restSeconds, 120)
    }
    func testManyStoppedDecreases() {
        let sets = [SetOutcome(plannedReps: 10, doneReps: 6, stoppedEarly: true),
                    SetOutcome(plannedReps: 10, doneReps: 5, stoppedEarly: true),
                    SetOutcome(plannedReps: 10, doneReps: 10, stoppedEarly: false)]
        let r = FixedCoaching.advise(sets: sets, isCompound: false, isLowerBody: false)
        XCTAssertTrue(r.advice.contains(.decreaseWeight(percent: 10)))
        XCTAssertTrue(r.advice.contains(.removeSet))
    }
}
