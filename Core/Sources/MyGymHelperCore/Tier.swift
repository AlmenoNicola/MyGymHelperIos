import Foundation

/// Livelli di abbonamento: Free (gratuito) e `.full`, mostrato come "Pro" / "abbonamento Pro" (a pagamento).
/// Il piano Mid è stato tolto il 4 novembre 2026: le sue funzioni sono passate al Pro. Il nome interno resta
/// `full` (prodotti app.mygymhelper.full.*, valore 'full' nel database).
public enum SubscriptionTier: Int, Comparable, Codable, Sendable {
    case free = 0
    case full = 2

    /// Livello salvato come numero (UserDefaults, JSON...). Prima del 4 novembre 2026: 0 Free, 1 Mid, 2 Full.
    /// Qualunque valore da 1 in su è Pro (il vecchio Mid diventa Pro); negativo: nil.
    public init?(storedLevel: Int) {
        if storedLevel < 0 { return nil }
        self = storedLevel == 0 ? .free : .full
    }

    /// Decodifica tollerante: un vecchio 1 (Mid) salvato in JSON diventa Pro invece di far fallire la lettura.
    /// L'encode resta quello automatico del rawValue.
    public init(from decoder: Decoder) throws {
        let level = try decoder.singleValueContainer().decode(Int.self)
        self = SubscriptionTier(storedLevel: level) ?? .free
    }

    public static func < (lhs: SubscriptionTier, rhs: SubscriptionTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Funzioni dell'app soggette al livello di abbonamento.
public enum Feature: CaseIterable, Sendable {
    case repCounting            // conteggio con serie, ripetizioni e pausa impostati dall'utente
    case bmi
    case catalogOnePerType      // catalogo limitato: un esercizio per tipologia
    case catalogFull
    case savedExerciseLists
    case muscleSelection
    case fixedCoaching          // consigli a regole fisse in base alle serie fatte
    case generalNutritionAdvice
    case appleWatch
    case adaptiveCoaching
    case uploadTrainingAndNutritionPlans
    case dietPlans
    case offlineFull
    case cloudSync
    case presetPlans            // schede pronte (oltre a quella base total body, per tutti)
    case monthlyPlan            // scheda consigliata del mese
    case variedSets             // serie diverse sullo stesso esercizio (ripetizioni e peso di ogni serie)
    case homeEquipment          // attrezzi in casa e filtro degli esercizi fattibili con quegli attrezzi
    case customPlans            // "Crea la tua scheda": scheda su misura da altezza, peso, sesso e obiettivo
}

/// Funzioni accese o spente in questa versione dell'app (uguale su Android: AppFlags in Basics.kt).
public enum AppFlags {
    /// Spotify integrato (accesso all'account, scelta della playlist, avvio con l'SDK). Spento per ora (28 ottobre 2026):
    /// in modalita' sviluppo Spotify accetta solo 5 utenti registrati a mano. Il codice resta; per riaccenderlo basta true.
    public static let spotifyIntegration = false

    /// Attrezzi in casa e filtro "Solo i miei attrezzi" (piano Pro). Riaccesi il 3 novembre 2026 (erano stati nascosti
    /// per errore il 2 novembre). Con false spariscono riquadro, elenco, filtro, passo del tutorial e riga dei piani
    /// (uguale su Android: AppFlags.HOME_EQUIPMENT in Basics.kt).
    public static let homeEquipment = true

    /// Strumenti di test anche nelle versioni non di debug (2 novembre 2026): piano simulato e cronologia finta per
    /// provare la revisione della scheda ogni due settimane. DA METTERE A false PRIMA DELLA PUBBLICAZIONE
    /// (insieme a AppFlags.TEST_TOOLS in Basics.kt).
    public static let testTools = false

    /// Esercizi MuscleWiki dalla funzione Supabase `catalog` (serve il piano MuscleWiki a pagamento). Spento il
    /// 3 novembre 2026: l'app usa solo l'elenco incluso (nostri + Free Exercise DB). Il codice resta; per
    /// riaccenderlo basta true, insieme a AppFlags.MUSCLEWIKI_CATALOG in Basics.kt e alla funzione `catalog` pubblicata.
    public static let muscleWikiCatalog = false
}

public enum FeatureGate {
    /// Livello minimo richiesto per ogni funzione (da confermare: vedi documento specifiche).
    public static func minimumTier(for feature: Feature) -> SubscriptionTier {
        switch feature {
        case .repCounting, .bmi, .catalogOnePerType:
            return .free
        // Tutto il resto è nel Pro (comprese le funzioni dell'ex piano Mid).
        case .catalogFull, .savedExerciseLists, .muscleSelection,
             .fixedCoaching, .generalNutritionAdvice, .appleWatch, .presetPlans, .monthlyPlan, .variedSets,
             .adaptiveCoaching, .uploadTrainingAndNutritionPlans,
             .dietPlans, .offlineFull, .cloudSync, .homeEquipment, .customPlans:
            return .full
        }
    }

    public static func isAvailable(_ feature: Feature, for tier: SubscriptionTier) -> Bool {
        tier >= minimumTier(for: feature)
    }
}
