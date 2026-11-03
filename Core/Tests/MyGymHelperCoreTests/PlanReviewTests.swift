import XCTest
@testable import MyGymHelperCore

/// Revisione della scheda ogni due settimane. Stessi casi di PlanReviewTests.kt.
final class PlanReviewTests: XCTestCase {
    private let day: TimeInterval = 86_400
    private lazy var now = Date(timeIntervalSince1970: 100 * day)

    private func session(_ daysAgo: Double, _ weight: Double, _ done: [Int], planned: Int = 8, stopped: Bool = false) -> SessionSample {
        SessionSample(date: now.addingTimeInterval(-daysAgo * day), weightKg: weight,
                      sets: done.map { SessionSetSample(doneReps: $0, plannedReps: planned, stoppedEarly: stopped && $0 < planned, averagePeak: 1) })
    }

    private var easy: [SessionSample] { [session(1, 60, [8, 8, 8, 8]), session(4, 60, [8, 8, 8, 8])] }
    private var hard: [SessionSample] { [session(2, 60, [8, 8, 3, 0], stopped: true)] }
    private let bench = PlanEntry(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000e1")!, name: "Panca piana", sets: 4,
                                  repsMin: 8, repsMax: 10, restSeconds: 90, weightKg: 60, exerciseID: "bench")

    func testDueEveryTwoWeeksWithEnoughSessions() {
        let created = now.addingTimeInterval(-20 * day)
        let times = [now.addingTimeInterval(-day), now.addingTimeInterval(-3 * day)]
        XCTAssertTrue(PlanReviewer.isDue(PlanReviewState(), planCreatedAt: created, planSessionDates: times, now: now))
        XCTAssertFalse(PlanReviewer.isDue(PlanReviewState(lastCheckAt: now.addingTimeInterval(-10 * day)), planCreatedAt: created,
                                          planSessionDates: times, now: now))
        XCTAssertFalse(PlanReviewer.isDue(PlanReviewState(), planCreatedAt: now.addingTimeInterval(-5 * day), planSessionDates: times, now: now))
        XCTAssertFalse(PlanReviewer.isDue(PlanReviewState(), planCreatedAt: created,
                                          planSessionDates: [now.addingTimeInterval(-day), now.addingTimeInterval(-30 * day)], now: now))
    }

    func testQualityOfLastTwoWeeks() {
        let q = PlanReviewer.quality(easy + [session(30, 50, [1, 1, 1, 1])], now: now)
        XCTAssertEqual(q.sessions, 2); XCTAssertEqual(q.completion, 1); XCTAssertTrue(q.correct); XCTAssertTrue(q.easy)
        let h = PlanReviewer.quality(hard, now: now)
        XCTAssertFalse(h.correct); XCTAssertEqual(h.completion, 19.0 / 32)
    }

    func testTooLightRaisesWeight() {
        let c = PlanReviewer.propose(bench, exerciseID: "bench", samples: easy, feedback: .tooLight, now: now)!
        XCTAssertEqual(c.after, Array(repeating: SetTarget(reps: 8, weightKg: 62.5), count: 4))
        XCTAssertEqual(c.afterRest, 75)
        XCTAssertEqual(c.reasonKeys, ["review.lightUp", "review.lessRest"])
        XCTAssertEqual(c.completionPercent, 100)
        XCTAssertTrue(c.changed)
    }

    func testTooLightButMissedRepsKeepsLoad() {
        let c = PlanReviewer.propose(bench, exerciseID: "bench", samples: hard, feedback: .tooLight, now: now)!
        XCTAssertEqual(c.reasonKeys, ["review.lightButMissed"])
        XCTAssertFalse(c.changed)
    }

    func testTooHeavyLowersLoadAndSets() {
        let c = PlanReviewer.propose(bench, exerciseID: "bench", samples: hard, feedback: .tooHeavy, now: now)!
        XCTAssertEqual(c.after, Array(repeating: SetTarget(reps: 8, weightKg: 53.75), count: 3))
        XCTAssertEqual(c.afterRest, 105)
        XCTAssertEqual(c.reasonKeys, ["review.heavyDown", "review.heavyLessSets"])
    }

    func testRightFollowsTheReps() {
        XCTAssertEqual(PlanReviewer.propose(bench, exerciseID: "bench", samples: easy, feedback: .right, now: now)!.reasonKeys, ["review.progress"])
        XCTAssertEqual(PlanReviewer.propose(bench, exerciseID: "bench", samples: hard, feedback: .right, now: now)!.reasonKeys, ["review.missedDown"])
        XCTAssertNil(PlanReviewer.propose(bench, exerciseID: "bench", samples: [session(20, 60, [8])], feedback: .right, now: now))
    }

    func testBodyweightUsesReps() {
        let pushUp = PlanEntry(name: "Piegamenti", sets: 3, repsMin: 12)
        let s = [session(1, 0, [12, 12, 12], planned: 12), session(2, 0, [12, 12, 12], planned: 12)]
        let c = PlanReviewer.propose(pushUp, exerciseID: "push", samples: s, feedback: .tooLight, now: now)!
        XCTAssertEqual(c.after, Array(repeating: SetTarget(reps: 14, weightKg: 0), count: 3))
        var noWeight = bench; noWeight.weightKg = nil
        XCTAssertEqual(PlanReviewer.propose(noWeight, exerciseID: "bench", samples: easy, feedback: .right, now: now)!.before[0].weightKg, 60)
    }

    func testApplyUpdatesPlanAndLists() {
        let other = PlanEntry(name: "Altro")
        let plan = TrainingPlan(days: [PlanDay(title: "A", entries: [bench, other])])
        let review = PlanReviewer.build(planID: UUID(), planName: "Scheda", plan: plan, feedback: .tooLight, now: now,
                                        resolve: { $0.exerciseID == "bench" ? CatalogExercise(id: "bench", name: "Bench", primary: [.chest]) : nil },
                                        samplesFor: { _ in self.easy })
        XCTAssertEqual(review.changes.count, 1)
        let updated = PlanReviewer.apply(review, to: plan).days[0].entries
        var expected = bench; expected.weightKg = 62.5; expected.restSeconds = 75
        XCTAssertEqual(updated[0], expected)
        XCTAssertEqual(updated[1], other)

        let i1 = WorkoutItem(exerciseID: "bench", sets: 4, reps: 8, restSeconds: 90, weightKg: 60, done: true)
        let i2 = WorkoutItem(exerciseID: "row")
        let newItems = PlanReviewer.apply(review, to: [i1, i2])
        XCTAssertEqual(newItems[0], WorkoutItem(id: i1.id, exerciseID: "bench", sets: 4, reps: 8, restSeconds: 75, weightKg: 62.5, done: true))
        XCTAssertEqual(newItems[1], i2)
        let l1 = UUID(), l2 = UUID()
        XCTAssertEqual(PlanReviewer.touchedLists([l1: [i1, i2], l2: [i2]], review: review), [l1])

        let varied = bench.withSets([PlanSet(reps: 10, weightKg: 40), PlanSet(reps: 8, weightKg: 50)])
        let vc = PlanReviewer.propose(varied, exerciseID: "bench", samples: easy, feedback: .tooLight, now: now)!
        XCTAssertEqual(PlanReviewer.updatedEntry(varied, vc).perSet, [PlanSet(reps: 10, weightKg: 42.5), PlanSet(reps: 8, weightKg: 52.5)])
    }

    func testPlanPreferredAfterApply() {
        let state = PlanReviewState(backup: PlanBackup(planID: UUID(), appliedAt: now, plan: TrainingPlan(days: []), listItems: [:], exerciseIDs: ["bench"]))
        XCTAssertTrue(PlanReviewer.prefersPlan(state, exerciseID: "bench", lastSessionAt: now.addingTimeInterval(-day)))
        XCTAssertFalse(PlanReviewer.prefersPlan(state, exerciseID: "bench", lastSessionAt: now.addingTimeInterval(day)))
        XCTAssertFalse(PlanReviewer.prefersPlan(state, exerciseID: "row", lastSessionAt: nil))
    }

    func testAICanOnlyMoveOneStepTheRightWay() {
        var fly = bench; fly.id = UUID()
        let light = PlanReview(planID: UUID(), planName: "S", createdAt: now, feedback: .tooLight, changes: [
            PlanReviewer.propose(bench, exerciseID: "bench", samples: easy, feedback: .tooLight, now: now)!,
            PlanReviewer.propose(fly, exerciseID: "fly", samples: hard, feedback: .tooLight, now: now)!])
        let decoded = PlanReviewer.decodeAI("ES | 1 | -5\n- ES | 2 | +1\nNOTA | Ripetizioni pulite: si sale.")
        XCTAssertEqual(decoded.adjustments, [1: -5, 2: 1])
        let r = PlanReviewer.applyAI(light, adjustments: decoded.adjustments, note: decoded.note)
        XCTAssertTrue(r.byAI); XCTAssertEqual(r.note, "Ripetizioni pulite: si sale.")
        XCTAssertEqual(r.changes[0].after[0].weightKg, 61.25)
        XCTAssertTrue(r.changes[0].reasonKeys.contains("review.aiAdjusted"))
        XCTAssertEqual(r.changes[1], light.changes[1])

        let heavy = PlanReview(planID: UUID(), planName: "S", createdAt: now, feedback: .tooHeavy, changes: [
            PlanReviewer.propose(bench, exerciseID: "bench", samples: hard, feedback: .tooHeavy, now: now)!])
        XCTAssertEqual(PlanReviewer.applyAI(heavy, adjustments: [1: 1], note: nil).changes[0].after[0].weightKg, 55)
        XCTAssertEqual(PlanReviewer.applyAI(heavy, adjustments: [:], note: "  "), heavy)
    }

    func testCodableRoundTrip() throws {
        let review = PlanReview(planID: UUID(), planName: "Scheda", createdAt: now, feedback: .tooHeavy,
                                changes: [PlanReviewer.propose(bench, exerciseID: "bench", samples: hard, feedback: .tooHeavy, now: now)!],
                                note: "nota", byAI: true)
        let item = WorkoutItem(exerciseID: "bench", perSet: [SetTarget(reps: 10, weightKg: 40), SetTarget(reps: 8, weightKg: 50)])
        let state = PlanReviewState(lastCheckAt: now.addingTimeInterval(-day), pending: review,
                                    backup: PlanBackup(planID: review.planID, appliedAt: now,
                                                       plan: TrainingPlan(days: [PlanDay(title: "A", entries: [bench])]),
                                                       listItems: [UUID(): [item]], exerciseIDs: ["bench"]))
        let data = try JSONEncoder().encode(state)
        XCTAssertEqual(try JSONDecoder().decode(PlanReviewState.self, from: data), state)
    }

    func testFakeHistoryMakesTheReviewDue() {
        let ex = CatalogExercise(id: "bench", name: "Bench", primary: [.chest], equipment: "barbell")
        let pushEx = CatalogExercise(id: "push", name: "Push-up", primary: [.chest], equipment: "body only")
        let pushUp = PlanEntry(name: "Piegamenti", sets: 3, repsMin: 12)
        let easy = FakePlanHistory.sessions([(bench, ex), (pushUp, pushEx), (bench, ex)], kind: .easy, now: now)
        XCTAssertEqual(easy.count, 8)
        XCTAssertEqual(easy.first { $0.exerciseID == "push" }?.weightKg, 0)
        XCTAssertEqual(easy.first { $0.exerciseID == "bench" }?.weightKg, 60)
        let created = now.addingTimeInterval(-day)
        let shifted = created.addingTimeInterval(FakePlanHistory.planShift(activeCreatedAt: created, now: now))
        XCTAssertTrue(PlanReviewer.isDue(PlanReviewState(), planCreatedAt: shifted, planSessionDates: easy.map(\.startedAt), now: now))
        XCTAssertEqual(FakePlanHistory.planShift(activeCreatedAt: now.addingTimeInterval(-30 * day), now: now), 0)
        func samples(_ list: [FakeSession]) -> [SessionSample] {
            list.filter { $0.exerciseID == "bench" }.map { s in
                SessionSample(date: s.startedAt, weightKg: s.weightKg, sets: s.sets.map {
                    SessionSetSample(doneReps: $0.doneReps, plannedReps: $0.plannedReps, stoppedEarly: $0.stoppedEarly, averagePeak: $0.averagePeak) })
            }
        }
        XCTAssertTrue(PlanReviewer.quality(samples(easy), now: now).easy)
        XCTAssertFalse(PlanReviewer.quality(samples(FakePlanHistory.sessions([(bench, ex)], kind: .hard, now: now)), now: now).correct)
    }
}
