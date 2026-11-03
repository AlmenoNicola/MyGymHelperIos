import XCTest
@testable import MyGymHelperCore

/// Tema grafico. Stessi casi di AppearanceTests.kt.
final class AppearanceTests: XCTestCase {
    func testDefaultIsTheNeutralSystemTheme() {
        XCTAssertEqual(AppAppearance.defaultValue, .system)
        XCTAssertEqual(AppAppearance.fromRaw(nil), .system)
        XCTAssertEqual(AppAppearance.fromRaw(""), .system)
        XCTAssertEqual(AppAppearance.fromRaw("sconosciuto"), .system)
    }

    func testSavedValuesRoundTrip() {
        for a in AppAppearance.allCases { XCTAssertEqual(AppAppearance.fromRaw(a.rawValue), a) }
        XCTAssertEqual(AppAppearance.allCases.map(\.rawValue), ["system", "original", "dark"])
        XCTAssertEqual(AppAppearance.key, "appearance.theme")
        XCTAssertEqual(AppAppearance.dark.titleKey, "appearance.dark")
    }

    func testOnlyTheSystemThemeFollowsThePhone() {
        XCTAssertTrue(AppAppearance.system.isDark(systemDark: true))
        XCTAssertFalse(AppAppearance.system.isDark(systemDark: false))
        XCTAssertTrue(AppAppearance.original.isDark(systemDark: false))
        XCTAssertTrue(AppAppearance.dark.isDark(systemDark: false))
    }
}
