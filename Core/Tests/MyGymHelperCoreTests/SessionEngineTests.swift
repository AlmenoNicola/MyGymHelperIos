import XCTest
@testable import MyGymHelperCore

final class SessionEngineTests: XCTestCase {
    func testFullFlowWithCountdownAndStop() {
        var e = SessionEngine(sets: 2, reps: 3, restSeconds: 20)
        XCTAssertEqual(e.start(at: 100), [.setStarted(1)])
        XCTAssertEqual(e.phase, .working(set: 1))

        XCTAssertEqual(e.repsCounted(1, at: 102), [])
        XCTAssertEqual(e.repsCounted(2, at: 106), [])
        XCTAssertEqual(e.repsCounted(3, at: 110), [.targetReached, .restStarted(seconds: 20)])
        XCTAssertEqual(e.phase, .resting(afterSet: 1, remaining: 20))
        XCTAssertEqual(e.records.count, 1)
        XCTAssertFalse(e.records[0].stoppedEarly)
        XCTAssertEqual(e.records[0].durationSeconds, 10, accuracy: 0.001)

        XCTAssertEqual(e.tick(at: 120), [])                      // 10 s rimasti
        XCTAssertEqual(e.tick(at: 127.2), [.restCountdown(3)])   // 3 s rimasti
        XCTAssertEqual(e.tick(at: 127.3), [])                    // stesso secondo: nessun doppione
        XCTAssertEqual(e.tick(at: 129), [.restCountdown(1)])
        XCTAssertEqual(e.tick(at: 130.1), [.restEnded])
        XCTAssertEqual(e.phase, .working(set: 2))

        XCTAssertEqual(e.stop(doneReps: 2, at: 140), [.sessionFinished])
        XCTAssertEqual(e.phase, .finished)
        XCTAssertEqual(e.records.count, 2)
        XCTAssertTrue(e.records[1].stoppedEarly)
        XCTAssertEqual(e.records[1].doneReps, 2)
    }

    func testRepsAreIgnoredDuringRest() {
        var e = SessionEngine(sets: 2, reps: 2, restSeconds: 30)
        _ = e.start(at: 0)
        _ = e.repsCounted(2, at: 5)
        XCTAssertEqual(e.repsCounted(5, at: 6), [])
        XCTAssertEqual(e.records.count, 1)
    }

    func testSkipRestStartsNextSet() {
        var e = SessionEngine(sets: 3, reps: 2, restSeconds: 60)
        _ = e.start(at: 0)
        _ = e.repsCounted(2, at: 5)
        XCTAssertEqual(e.skipRest(at: 8), [.restEnded])
        XCTAssertEqual(e.phase, .working(set: 2))
        XCTAssertEqual(e.currentReps, 0)
    }

    func testStopWithAllRepsIsNotStoppedEarly() {
        var e = SessionEngine(sets: 1, reps: 5, restSeconds: 30)
        _ = e.start(at: 0)
        _ = e.stop(doneReps: 9, at: 10)
        XCTAssertFalse(e.records[0].stoppedEarly)
        XCTAssertEqual(e.records[0].doneReps, 5)
    }

    func testLastSetCompletedFinishesSession() {
        var e = SessionEngine(sets: 1, reps: 2, restSeconds: 30)
        _ = e.start(at: 0)
        XCTAssertEqual(e.repsCounted(2, at: 4), [.targetReached, .sessionFinished])
        XCTAssertEqual(e.phase, .finished)
    }

    func testEndNowSavesPartialSet() {
        var e = SessionEngine(sets: 3, reps: 10, restSeconds: 30)
        _ = e.start(at: 0)
        _ = e.repsCounted(4, at: 8)
        XCTAssertEqual(e.endNow(at: 9), [.sessionFinished])
        XCTAssertEqual(e.records.count, 1)
        XCTAssertEqual(e.records[0].doneReps, 4)
        XCTAssertTrue(e.records[0].stoppedEarly)
    }
}
