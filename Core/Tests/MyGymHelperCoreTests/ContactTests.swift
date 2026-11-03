import XCTest
@testable import MyGymHelperCore

/// Indirizzo dell'app e testo dei suggerimenti. Stessi casi di ContactTests.kt.
final class ContactTests: XCTestCase {
    private let info = ErrorReport.Info(appVersion: "1.0 (7)", platform: "iOS 26.0", device: "iPhone17,1",
                                        language: "it_IT", timeISO: "2026-10-31T16:00:00Z")

    func testEveryEmailGoesToTheAppAddress() {
        XCTAssertEqual(AppContact.email, "mygymhelper@gmail.com")
        XCTAssertEqual(ErrorReport.email, AppContact.email)
        XCTAssertEqual(Suggestion.email, AppContact.email)
    }

    func testSuggestionHasSubjectIntroAndTechnicalInfo() {
        XCTAssertEqual(Suggestion.subject(info: info), "MyGymHelper 1.0 (7) – suggerimento")
        let body = Suggestion.body(intro: "Scrivi qui la tua idea:", info: info)
        XCTAssertTrue(body.hasPrefix("Scrivi qui la tua idea:\n"))
        XCTAssertTrue(body.contains("App: 1.0 (7)"))
        XCTAssertTrue(body.contains("Telefono: iPhone17,1"))
        XCTAssertTrue(body.hasSuffix("Lingua: it_IT"))
    }

    func testAIReportHasSubjectIntroAITextAndTechnicalInfo() {
        XCTAssertEqual(AIContentReport.email, AppContact.email)
        XCTAssertEqual(AIContentReport.subject(info: info), "MyGymHelper 1.0 (7) – segnalazione testo IA")
        let body = AIContentReport.body(intro: "Descrivi cosa non va:", aiText: "Aumenta il carico del 5%", info: info)
        XCTAssertTrue(body.hasPrefix("Descrivi cosa non va:\n"))
        XCTAssertTrue(body.contains("Testo dell'IA: Aumenta il carico del 5%"))
        XCTAssertTrue(body.hasSuffix("Lingua: it_IT"))
    }
}
