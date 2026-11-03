import XCTest
@testable import MyGymHelperCore

/// Attrezzi in casa e relativo filtro. Stessi casi di HomeEquipmentTests.kt.
final class HomeEquipmentTests: XCTestCase {
    private func ex(_ id: String, _ equipment: String) -> CatalogExercise {
        CatalogExercise(id: id, name: id, primary: [.chest], equipment: equipment)
    }
    private var list: [CatalogExercise] {
        [ex("corpo", "bodyweight"), ex("vuoto", ""), ex("manubri", "dumbbell"), ex("bilanciere", "barbell"), ex("libero", "Dumbbells")]
    }

    func testOnlyFullPlanHasIt() {
        XCTAssertFalse(FeatureGate.isAvailable(.homeEquipment, for: .free))
        XCTAssertFalse(FeatureGate.isAvailable(.homeEquipment, for: .mid))
        XCTAssertTrue(FeatureGate.isAvailable(.homeEquipment, for: .full))
    }

    func testFilterOffKeepsEverything() {
        XCTAssertEqual(HomeEquipment.filter(list, owned: [], enabled: false).map(\.id), list.map(\.id))
    }

    func testFilterKeepsBodyweightAndOwnedEquipment() {
        XCTAssertEqual(HomeEquipment.filter(list, owned: [], enabled: true).map(\.id), ["corpo", "vuoto"])
        XCTAssertEqual(HomeEquipment.filter(list, owned: ["dumbbell"], enabled: true).map(\.id), ["corpo", "vuoto", "manubri"])
    }

    func testBodyweightFilterExcludesEveryEquipment() {
        XCTAssertEqual(CatalogFilter.bodyweightOnly(list, on: false).map(\.id), list.map(\.id))
        let external = ex("esterno", "Bodyweight")
        XCTAssertEqual(CatalogFilter.bodyweightOnly(list + [external], on: true).map(\.id), ["corpo", "esterno"])
    }

    func testEncodeAndDecodeKeepOnlyKnownNames() {
        XCTAssertEqual(HomeEquipment.encode(["band", "dumbbell"]), "dumbbell,band")
        XCTAssertEqual(HomeEquipment.decode("dumbbell, band,xyz,"), ["dumbbell", "band"])
        XCTAssertEqual(HomeEquipment.decode(nil), [])
        XCTAssertFalse(HomeEquipment.choices.contains("bodyweight"))
    }
}
