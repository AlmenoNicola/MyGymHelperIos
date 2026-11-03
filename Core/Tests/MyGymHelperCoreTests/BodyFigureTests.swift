import XCTest
@testable import MyGymHelperCore

/// Controlli sui dati della figura anatomica (generati da android/tools/body_figure.py). Stessi controlli su Android.
final class BodyFigureTests: XCTestCase {
    func testPathsParse() {
        for d in BodyFigure.silhouette + (BodyFigure.front + BodyFigure.back).map(\.path) {
            guard let cmds = BodyFigure.commands(d) else { return XCTFail("tracciato non valido: \(d.prefix(40))") }
            guard case .move = cmds.first else { return XCTFail("deve iniziare con M") }
            XCTAssertEqual(cmds.last, .close)
            XCTAssertGreaterThan(cmds.count, 4)
        }
    }

    func testParserReadsNumbers() {
        XCTAssertEqual(BodyFigure.commands("M1 2C3 4 5.5 6 7 8Z"), [.move(1, 2), .curve(3, 4, 5.5, 6, 7, 8), .close])
        XCTAssertNil(BodyFigure.commands("M1 2L3 4Z"))      // L non e' previsto
        XCTAssertNil(BodyFigure.commands("M1C2 3Z"))        // numeri mancanti
    }

    func testEveryMuscleIsDrawn() {
        XCTAssertEqual(BodyFigure.muscles(front: true).union(BodyFigure.muscles(front: false)), Set(MuscleGroup.allCases))
    }

    func testSidesShowTheRightMuscles() {
        XCTAssertTrue(BodyFigure.muscles(front: true).isSuperset(of: [.chest, .abs, .quads, .biceps]))
        XCTAssertTrue(BodyFigure.muscles(front: false).isSuperset(of: [.lats, .glutes, .hamstrings, .triceps]))
        XCTAssertFalse(BodyFigure.muscles(front: true).contains(.lats))
        XCTAssertFalse(BodyFigure.muscles(front: false).contains(.chest))
    }

    func testFigureIsSymmetric() {
        for parts in [BodyFigure.front, BodyFigure.back] {
            let counts = Dictionary(grouping: parts, by: { $0.muscle?.rawValue ?? "-" }).mapValues(\.count)
            for (_, n) in counts { XCTAssertEqual(n % 2, 0) }
        }
    }
}
