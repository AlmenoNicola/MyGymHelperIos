import Foundation
import FoundationModels
import MyGymHelperCore

/// Lettura delle schede (PDF, foto, Word...) con Apple Intelligence sul telefono. Le regole fisse restano sempre:
/// il modello legge il testo a pezzi, gli esercizi che non si trovano nel testo si scartano (PlanAI.ground) e si usa
/// la lettura dell'AI completando i dati che non ha trovato con le regole (PlanAI.combine). Poi il modello collega
/// ogni esercizio a uno del catalogo, scegliendo solo tra candidati gia' simili. Tutto resta sul telefono. Come PlanImportAI.kt su Android.
enum PlanImportAI {
    static var status: String {
        switch SystemLanguageModel.default.availability {
        case .available: return "disponibile"
        case .unavailable(let reason): return "non disponibile (\(reason))"
        }
    }

    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    /// Legge la scheda dal testo. Non lancia errori: se l'AI non c'e' o sbaglia, resta la lettura con le regole.
    static func read(_ text: String, catalog: [CatalogExercise]) async -> PlanAI.Result {
        let rules = TrainingPlanParser.parse(text)
        guard isAvailable else {
            return PlanAI.Result(plan: PlanAI.applyMatches(rules, catalog: catalog, chosen: nil), usedAI: false, aiStatus: status)
        }
        let chunks = PlanAI.chunks(text)
        guard chunks.count <= PlanAI.maxChunks else {
            return PlanAI.Result(plan: PlanAI.applyMatches(rules, catalog: catalog, chosen: nil), usedAI: false,
                                 aiStatus: "testo troppo lungo (\(chunks.count) pezzi)")
        }
        var parts: [TrainingPlan] = []
        var lastError: Error?
        for chunk in chunks {
            do { parts.append(try await extract(chunk)) } catch { lastError = error }
        }
        // L'AI e' il motore principale; i dati che non trova si completano con le regole sullo stesso esercizio
        let choice = PlanAI.combine(rules: rules, ai: PlanAI.ground(parts, text: text))
        var chosen: [Int: String]?
        do { chosen = try await match(choice.plan, catalog: catalog) } catch { lastError = lastError ?? error }
        return PlanAI.Result(plan: PlanAI.applyMatches(choice.plan, catalog: catalog, chosen: chosen),
                             usedAI: choice.usedAI, aiStatus: status, aiError: lastError.map { String(reflecting: $0) })
    }

    /// Un pezzo di testo -> giorni ed esercizi (generazione guidata: la forma e' garantita, i valori si controllano).
    private static func extract(_ chunk: String) async throws -> TrainingPlan {
        let session = LanguageModelSession(instructions: PlanAI.instructions)   // una sessione per pezzo: contesto pulito
        let response = try await session.respond(to: "Testo della scheda:\n" + chunk, generating: AIImportPlan.self,
                                                 options: GenerationOptions(temperature: 0.1))
        let days: [PlanDay] = response.content.days.compactMap { d in
            let entries = d.exercises.compactMap { e in
                PlanAI.entry(name: e.name, sets: e.sets, repsMin: e.repsMin, repsMax: e.repsMax,
                             restSeconds: e.restSeconds, weightKg: e.weightKg, seconds: e.seconds)
            }
            return entries.isEmpty ? nil : PlanDay(title: d.title, entries: entries)
        }
        return TrainingPlan(days: days)
    }

    /// Esercizio del catalogo per ogni voce (indici su tutte le voci); a gruppi per restare nel contesto del modello.
    private static func match(_ plan: TrainingPlan, catalog: [CatalogExercise]) async throws -> [Int: String] {
        let names = plan.allEntries.map(\.name)
        let candidates = names.map { PlanAI.candidates(for: $0, in: catalog) }
        var out: [Int: String] = [:]
        var start = 0
        while start < names.count {
            let end = min(start + PlanAI.matchBatch, names.count)
            let batchCandidates = Array(candidates[start..<end])
            if batchCandidates.contains(where: { !$0.isEmpty }) {
                let session = LanguageModelSession()
                let prompt = PlanAI.matchPrompt(names: Array(names[start..<end]), candidates: batchCandidates)
                let response = try await session.respond(to: prompt, generating: AIMatches.self,
                                                         options: GenerationOptions(temperature: 0))
                let valid = PlanAI.validMatches(response.content.matches.map { m -> (Int, String) in (m.number, m.id) }, candidates: batchCandidates)
                for (i, id) in valid { out[start + i] = id }
            }
            start = end
        }
        return out
    }
}

@Generable
struct AIImportPlan {
    @Guide(description: "I giorni o le parti della scheda, nell'ordine del testo")
    var days: [AIImportDay]
}

@Generable
struct AIImportDay {
    @Guide(description: "Titolo del giorno o della parte (es. Riscaldamento, Settimana 1, Giorno A); vuoto se il testo non lo dice")
    var title: String
    @Guide(description: "Gli esercizi, nell'ordine del testo")
    var exercises: [AIImportExercise]
}

@Generable
struct AIImportExercise {
    @Guide(description: "Solo il nome dell'esercizio, come nel testo, senza numeri di serie o ripetizioni")
    var name: String
    @Guide(description: "Numero di serie")
    var sets: Int?
    @Guide(description: "Ripetizioni minime per serie")
    var repsMin: Int?
    @Guide(description: "Ripetizioni massime per serie")
    var repsMax: Int?
    @Guide(description: "Recupero tra le serie in secondi")
    var restSeconds: Int?
    @Guide(description: "Peso in kg, solo se scritto nel testo (es. 20 kg, kg 20, manubri da 8 kg)")
    var weightKg: Double?
    @Guide(description: "Durata in secondi se l'esercizio e' a tempo")
    var seconds: Int?
}

@Generable
struct AIMatches {
    @Guide(description: "Una scelta per ogni esercizio numerato")
    var matches: [AIMatch]
}

@Generable
struct AIMatch {
    @Guide(description: "Numero dell'esercizio")
    var number: Int
    @Guide(description: "Id esatto di uno dei candidati di quell'esercizio, oppure vuoto se nessuno e' lo stesso esercizio")
    var id: String
}
