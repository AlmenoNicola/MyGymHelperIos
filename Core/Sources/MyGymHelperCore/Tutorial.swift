import Foundation

/// Tutorial guidato dell'app: passi mostrati in sovraimpressione (riquadro illuminato sulla funzione + fumetto).
/// Equivalente di Tutorial.kt: stessi passi, stesso ordine, stessi identificativi.
///
/// REGOLA DI PROGETTO: a ogni modifica o aggiunta di una funzione dell'app va aggiornato questo elenco
/// (e Tutorial.kt, le stringhe tutorial.* e docs/TUTORIAL.md), poi va aumentato `TutorialGuide.version`.
///
/// Schede principali. I Piani non sono piu' una scheda: sono una voce dell'Area personale (TutorialTarget.infoPlans).
public enum TutorialTab: String, CaseIterable, Sendable { case workout, exercises, nutrition, info }

/// Disegno mostrato nel fumetto dei passi senza un elemento da indicare.
public enum TutorialArt: String, Sendable { case welcome, strap, session, done }

/// Un passo. `tab` = scheda da aprire prima del passo (nil = resta dov'e');
/// `target` = identificativo dell'elemento da illuminare (nil = solo fumetto al centro con `art`).
/// I testi sono le chiavi "tutorial.<id>.title" e "tutorial.<id>.body".
public struct TutorialStep: Hashable, Sendable {
    public let id: String
    public let tab: TutorialTab?
    public let target: String?
    public let art: TutorialArt?

    public init(_ id: String, tab: TutorialTab? = nil, target: String? = nil, art: TutorialArt? = nil) {
        self.id = id; self.tab = tab; self.target = target; self.art = art
    }

    public var titleKey: String { "tutorial.\(id).title" }
    /// "Elenchi e schede": senza caricamento schede (file o foto) si usa il testo che parla solo dell'inserimento a mano.
    public var bodyKey: String {
        id == "exercisesLinks" && !AppFeatures.planImportEnabled ? "tutorial.exercisesLinks.bodyManual" : "tutorial.\(id).body"
    }
}

/// Identificativi degli elementi illuminabili (stessi nomi su Android).
public enum TutorialTarget {
    public static let tabWorkout = "tab.workout"
    public static let tabExercises = "tab.exercises"
    public static let tabNutrition = "tab.nutrition"
    public static let tabInfo = "tab.info"
    public static let workoutList = "workout.list"
    public static let workoutAdd = "workout.add"
    public static let workoutPresets = "workout.presets"
    public static let workoutCues = "workout.cues"
    public static let workoutFree = "workout.free"
    public static let workoutHistory = "workout.history"
    public static let exercisesLinks = "exercises.links"
    public static let exercisesEquipment = "exercises.equipment"
    public static let nutritionProfile = "nutrition.profile"
    public static let infoPlans = "info.plans"
    public static let infoTutorial = "info.tutorial"
    public static let infoAppearance = "info.appearance"
    public static let infoSuggest = "info.suggest"
}

public enum TutorialGuide {
    /// Versione del tutorial: aumentarla a ogni aggiornamento dei passi. Viene salvata quando l'utente lo
    /// completa o lo salta; il tutorial parte da solo solo se non e' mai stato visto (valore salvato 0).
    public static let version = 14  // 2: "Aggiungi esercizio" e "Schede pronte"; 3: scelta del tema grafico;
                                    // 4: passi della Nutrizione nascosti mentre la scheda e' disattivata;
                                    // 5: i Piani passano dalla barra delle schede all'Area personale;
                                    // 6: "Suggerisci una funzione" (ultima voce dell'Area personale);
                                    // 7: serie diverse (ripetizioni e peso di ogni serie, dalla matita dell'esercizio);
                                    // 8: attrezzi in casa e filtro "Solo i miei attrezzi" (piano Full);
                                    // 9: revisione della scheda ogni due settimane (piano Full);
                                    // 10: attrezzi in casa nascosti; filtro "Corpo libero" nei testi di Esercizi e Aggiungi esercizio
                                    // 11: "Fai esercizio alternativo" dalla schermata di avvio dell'esercizio
                                    // 12: difficoltà evidenziata e "Scegli la tua scheda di esercizi" nel passo "presets"
                                    // 13: avviso a voce prima dell'ultima serie con il prossimo esercizio, nel passo "session"
                                    // 14: attrezzi in casa di nuovo visibili (passo "homeEquipment" dopo "exercisesLinks")

    /// Tutti i passi, compresi quelli delle funzioni disattivate.
    public static let allSteps: [TutorialStep] = [
        TutorialStep("welcome", art: .welcome),
        TutorialStep("strap", art: .strap),
        TutorialStep("workoutTab", tab: .workout, target: TutorialTarget.tabWorkout),
        TutorialStep("list", tab: .workout, target: TutorialTarget.workoutList),
        TutorialStep("addExercise", tab: .workout, target: TutorialTarget.workoutAdd),
        TutorialStep("variedSets", tab: .workout, target: TutorialTarget.workoutList),
        TutorialStep("presets", tab: .workout, target: TutorialTarget.workoutPresets),
        TutorialStep("session", art: .session),
        TutorialStep("alternative", art: .session),
        TutorialStep("cues", tab: .workout, target: TutorialTarget.workoutCues),
        TutorialStep("free", tab: .workout, target: TutorialTarget.workoutFree),
        TutorialStep("history", tab: .workout, target: TutorialTarget.workoutHistory),
        TutorialStep("planReview", tab: .workout, target: TutorialTarget.workoutHistory),
        TutorialStep("exercisesTab", tab: .exercises, target: TutorialTarget.tabExercises),
        TutorialStep("exercisesLinks", tab: .exercises, target: TutorialTarget.exercisesLinks),
        TutorialStep("homeEquipment", tab: .exercises, target: TutorialTarget.exercisesEquipment),
        TutorialStep("nutritionTab", tab: .nutrition, target: TutorialTarget.tabNutrition),
        TutorialStep("nutritionProfile", tab: .nutrition, target: TutorialTarget.nutritionProfile),
        TutorialStep("infoTab", tab: .info, target: TutorialTarget.tabInfo),
        TutorialStep("plans", tab: .info, target: TutorialTarget.infoPlans),
        TutorialStep("appearance", tab: .info, target: TutorialTarget.infoAppearance),
        TutorialStep("replay", tab: .info, target: TutorialTarget.infoTutorial),
        TutorialStep("suggest", tab: .info, target: TutorialTarget.infoSuggest),
        TutorialStep("done", art: .done)
    ]

    /// Schede principali visibili (la Nutrizione solo se attiva: AppFeatures.nutritionEnabled).
    public static var visibleTabs: [TutorialTab] {
        TutorialTab.allCases.filter { $0 != .nutrition || AppFeatures.nutritionEnabled }
    }

    /// Passi mostrati: si saltano quelli delle schede e delle funzioni disattivate (attrezzi in casa: AppFlags.homeEquipment).
    public static let steps: [TutorialStep] = allSteps.filter {
        ($0.tab.map(visibleTabs.contains) ?? true) && ($0.id != "homeEquipment" || AppFlags.homeEquipment)
    }

    /// Il tutorial parte da solo al primo avvio (dopo disclaimer e consenso) se non e' mai stato completato o saltato.
    public static func shouldAutoStart(seenVersion: Int) -> Bool { seenVersion <= 0 }

    /// Indice del passo successivo (nil = fine).
    public static func next(_ index: Int) -> Int? { index + 1 < steps.count ? index + 1 : nil }

    /// Indice del passo precedente (nil = siamo al primo).
    public static func previous(_ index: Int) -> Int? { index > 0 ? index - 1 : nil }
}
