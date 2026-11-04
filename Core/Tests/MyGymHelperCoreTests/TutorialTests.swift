import XCTest
@testable import MyGymHelperCore

/// Passi del tutorial. Stessi casi di TutorialTests.kt.
final class TutorialTests: XCTestCase {
    private let steps = TutorialGuide.steps

    func testIdsAreUniqueAndOrderIsFixed() {
        XCTAssertEqual(Set(steps.map(\.id)).count, steps.count)
        XCTAssertEqual(steps.first?.id, "welcome")
        XCTAssertEqual(steps.last?.id, "done")
        XCTAssertEqual(TutorialGuide.allSteps.count, 24)
        // Con la Nutrizione disattivata si saltano i suoi 2 passi.
        // Con gli attrezzi in casa nascosti (AppFlags.homeEquipment) si salta anche il loro passo.
        XCTAssertEqual(steps.count, 24 - (AppFeatures.nutritionEnabled ? 0 : 2) - (AppFlags.homeEquipment ? 0 : 1))
        // Attrezzi in casa: subito dopo i collegamenti di Esercizi, nella stessa scheda (se accesi).
        if AppFlags.homeEquipment {
            let equipment = steps.firstIndex { $0.id == "homeEquipment" }!
            XCTAssertEqual(steps[equipment - 1].id, "exercisesLinks")
            XCTAssertEqual(steps[equipment].target, TutorialTarget.exercisesEquipment)
        } else {
            XCTAssertNil(steps.firstIndex { $0.id == "homeEquipment" })
        }
        // Serie diverse: subito dopo "Aggiungi esercizio", sull'elenco (dalla matita di un esercizio).
        let varied = steps.firstIndex { $0.id == "variedSets" }!
        XCTAssertEqual(steps[varied - 1].id, "addExercise")
        XCTAssertEqual(steps[varied].target, TutorialTarget.workoutList)
        // Revisione della scheda ogni due settimane: subito dopo lo Storico, da cui prende i dati.
        let review = steps.firstIndex { $0.id == "planReview" }!
        XCTAssertEqual(steps[review - 1].id, "history")
        XCTAssertEqual(steps[review].target, TutorialTarget.workoutHistory)
        // Esercizio alternativo: subito dopo la sessione, con il disegno della sessione.
        let alternative = steps.firstIndex { $0.id == "alternative" }!
        XCTAssertEqual(steps[alternative - 1].id, "session")
        XCTAssertEqual(steps[alternative].art, .session)
    }

    func testEveryStepHasATargetOrADrawing() {
        for s in steps { XCTAssertTrue(s.target != nil || s.art != nil, s.id) }
        // Un passo con elemento da indicare deve dire in quale scheda si trova.
        for s in steps where s.target != nil { XCTAssertNotNil(s.tab, s.id) }
    }

    func testEveryMainTabIsShownAndTheReplayIsInThePersonalArea() {
        for tab in TutorialGuide.visibleTabs { XCTAssertTrue(steps.contains { $0.tab == tab }, tab.rawValue) }
        // Nessun passo porta a una scheda nascosta.
        for s in steps { if let tab = s.tab { XCTAssertTrue(TutorialGuide.visibleTabs.contains(tab), s.id) } }
        XCTAssertEqual(TutorialGuide.visibleTabs.contains(.nutrition), AppFeatures.nutritionEnabled)
        let replay = steps.first { $0.target == TutorialTarget.infoTutorial }
        XCTAssertEqual(replay?.tab, .info)
        // I Piani sono una voce dell'Area personale, subito dopo la presentazione della scheda.
        let plans = steps.firstIndex { $0.target == TutorialTarget.infoPlans }!
        XCTAssertEqual(steps[plans].tab, .info)
        XCTAssertEqual(steps[plans - 1].id, "infoTab")
        // Avvisi: nell'Area personale, voce "Voce e musica", subito dopo la riga Tutorial.
        let cues = steps.firstIndex { $0.id == "cues" }!
        XCTAssertEqual(steps[cues].tab, .info)
        XCTAssertEqual(steps[cues].target, TutorialTarget.infoAudio)
        XCTAssertEqual(steps[cues - 1].id, "replay")
        // "Suggerisci una funzione" e' l'ultimo passo con un elemento, prima della fine.
        XCTAssertEqual(steps[steps.count - 2].target, TutorialTarget.infoSuggest)
        XCTAssertEqual(steps[steps.count - 2].tab, .info)
    }

    func testKeysFollowTheNamingRule() {
        let s = steps[3]
        XCTAssertEqual(s.titleKey, "tutorial.list.title")
        XCTAssertEqual(s.bodyKey, "tutorial.list.body")
    }

    func testNavigationStopsAtTheEnds() {
        XCTAssertNil(TutorialGuide.previous(0))
        XCTAssertEqual(TutorialGuide.next(0), 1)
        XCTAssertNil(TutorialGuide.next(steps.count - 1))
        XCTAssertEqual(TutorialGuide.previous(steps.count - 1), steps.count - 2)
    }

    func testAutoStartOnlyTheFirstTime() {
        XCTAssertTrue(TutorialGuide.shouldAutoStart(seenVersion: 0))
        XCTAssertFalse(TutorialGuide.shouldAutoStart(seenVersion: 1))
        XCTAssertFalse(TutorialGuide.shouldAutoStart(seenVersion: TutorialGuide.version))
    }
}
