import Foundation
import Observation
import FoundationModels
import MyGymHelperCore

/// Scheda consigliata del mese (Mid e Full). Parte da quella a regole fisse del Core (MonthlyPlanner, uguale su
/// Android); se l'iPhone ha Apple Intelligence, il modello sul telefono la rivede scegliendo solo tra gli esercizi
/// candidati di ogni posto e scrive una breve nota. Tutto resta sul telefono (come dice l'informativa privacy).
/// La scheda rivista si salva per il mese (con il consenso, in un file escluso dai backup) e si rifà il mese dopo o
/// se cambia lo storico del mese precedente.
@Observable
@MainActor
final class MonthlyPlanStore {
    static let shared = MonthlyPlanStore()

    /// Scheda da mostrare: quella rivista dall'AI se pronta, altrimenti quella a regole fisse.
    private(set) var plan: MonthlyPlan?
    private(set) var isWorking = false
    @ObservationIgnored private var task: Task<Void, Never>?

    private struct Cached: Codable { var basis: String; var plan: MonthlyPlan }

    private var cacheURL: URL {
        URL.applicationSupportDirectory.appending(path: "monthly-plan.json")
    }
    private var persistent: Bool { UserDefaults.standard.double(forKey: ConsentStore.grantedAtKey) > 0 }

    /// Ricalcola la scheda (subito quella a regole) e, se possibile, avvia la revisione con l'AI.
    func refresh(catalog: [CatalogExercise], sessions: [SessionSummary]) {
        let rules = MonthlyPlanner.generate(catalog: catalog, sessions: sessions)
        let basis = Self.basis(of: rules)
        if let cached = loadCache(), cached.basis == basis { plan = cached.plan; return }
        plan = rules
        guard Self.aiAvailable, task == nil else { return }
        isWorking = true
        task = Task { [weak self] in
            let reviewed = await MonthlyPlanAI.review(rules, catalog: catalog)
            guard let self else { return }
            self.isWorking = false
            self.task = nil
            guard let reviewed, Self.basis(of: rules) == basis else { return }
            self.plan = reviewed
            self.saveCache(Cached(basis: basis, plan: reviewed))
        }
    }

    /// Dopo "Elimina dati" o la revoca del consenso.
    func clear() {
        task?.cancel(); task = nil; isWorking = false; plan = nil
        try? FileManager.default.removeItem(at: cacheURL)
    }

    static var aiAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    /// Cosa determina la scheda: mese ed esercizi scelti dalle regole (cambia se cambia lo storico).
    private static func basis(of plan: MonthlyPlan) -> String {
        plan.summary.monthKey + "|" + plan.plan.days.map { $0.items.map(\.exerciseID).joined(separator: ",") }.joined(separator: ";")
    }

    private func loadCache() -> Cached? {
        guard persistent, let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONDecoder().decode(Cached.self, from: data)
    }

    private func saveCache(_ c: Cached) {
        guard persistent, let data = try? JSONEncoder().encode(c) else { return }
        var url = cacheURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true            // dato ricavato dallo storico: resta solo su questo iPhone
        try? url.setResourceValues(values)
    }
}

/// Risposta richiesta al modello sul telefono (generazione guidata: la forma e' garantita, i valori si controllano).
@Generable
struct AIMonthlyPlan {
    @Guide(description: "Gli allenamenti della scheda, nello stesso ordine e numero della scheda proposta")
    var days: [AIPlanDay]
    @Guide(description: "Nota per l'utente, al massimo due frasi brevi, nella lingua richiesta: perché la scheda del mese è fatta così")
    var note: String
}

@Generable
struct AIPlanDay {
    @Guide(description: "Gli esercizi dell'allenamento, uno per ogni posto, nello stesso ordine dei posti")
    var exercises: [AIPlanExercise]
}

@Generable
struct AIPlanExercise {
    @Guide(description: "Id esatto di uno dei candidati di quel posto")
    var id: String
    @Guide(description: "Numero di serie, tra 2 e 5")
    var sets: Int
    @Guide(description: "Ripetizioni per serie, tra 5 e 20")
    var reps: Int
}

enum MonthlyPlanAI {
    /// Chiede al modello di rivedere la scheda; nil se non disponibile o se la risposta non e' valida.
    static func review(_ rules: MonthlyPlan, catalog: [CatalogExercise]) async -> MonthlyPlan? {
        let alternatives = MonthlyPlanner.alternatives(for: rules, catalog: catalog)
        let italian = (Locale.current.language.languageCode?.identifier ?? "en") == "it"
        let session = LanguageModelSession(instructions: """
            Sei un allenatore. Rivedi una scheda di palestra per il mese: per ogni posto scegli uno dei candidati \
            (puoi tenere il primo, che è quello proposto) e serie e ripetizioni adatte. Varia gli esercizi rispetto \
            al mese scorso senza stravolgere la scheda. Usa solo gli id dei candidati. Non dare consigli medici.
            """)
        let prompt = Self.prompt(rules, alternatives: alternatives, italian: italian)
        do {
            let response = try await session.respond(to: prompt, generating: AIMonthlyPlan.self)
            return apply(response.content, to: rules, alternatives: alternatives, catalog: catalog)
        } catch {
            return nil
        }
    }

    static func prompt(_ rules: MonthlyPlan, alternatives: [[[CatalogExercise]]], italian: Bool) -> String {
        let s = rules.summary
        var text = "Lingua della nota: \(italian ? "italiano" : "English").\n"
        text += "Mese scorso: \(s.trainingDays) giorni di allenamento, \(s.sessions) esercizi svolti."
        if !s.undertrained.isEmpty { text += " Muscoli allenati poco: \(s.undertrained.map(\.rawValue).joined(separator: ", "))." }
        text += "\nScheda proposta (\(rules.plan.days.count) allenamenti):\n"
        for (i, day) in rules.plan.days.enumerated() {
            text += "Allenamento \(i + 1):\n"
            for (j, item) in day.items.enumerated() {
                let options = alternatives[i][j].map { "\($0.id) (\($0.name))" }.joined(separator: " | ")
                text += "- posto \(j + 1), proposto \(item.sets)x\(item.reps): candidati \(options)\n"
            }
        }
        return text
    }

    /// Applica la risposta solo dove e' valida: id tra i candidati e non ripetuto, serie e ripetizioni nei limiti.
    static func apply(_ ai: AIMonthlyPlan, to rules: MonthlyPlan, alternatives: [[[CatalogExercise]]],
                      catalog: [CatalogExercise]) -> MonthlyPlan? {
        guard ai.days.count == rules.plan.days.count else { return nil }
        var result = rules
        var used = Set<String>()
        var changed = 0
        for (i, day) in rules.plan.days.enumerated() {
            var items: [PresetItem] = []
            for (j, item) in day.items.enumerated() {
                let candidates = alternatives[i][j]
                let proposal = j < ai.days[i].exercises.count ? ai.days[i].exercises[j] : nil
                if let proposal, let ex = candidates.first(where: { $0.id == proposal.id }), !used.contains(ex.id),
                   let muscle = ex.primary.first {
                    var p = MonthlyPlanner.parameters(for: ex, muscle: muscle, advanced: rules.plan.level == "intermediate")
                    p.sets = min(max(proposal.sets, 2), 5)
                    p.reps = min(max(proposal.reps, 5), 20)
                    p.weightKg = item.weightKg
                    if ex.id != item.exerciseID || p.sets != item.sets || p.reps != item.reps { changed += 1 }
                    used.insert(ex.id); items.append(p)
                } else if !used.contains(item.exerciseID) {
                    used.insert(item.exerciseID); items.append(item)
                }
            }
            result.plan.days[i].items = items
        }
        let note = ai.note.trimmingCharacters(in: .whitespacesAndNewlines)
        result.aiNote = note.isEmpty ? nil : String(note.prefix(400))
        return changed > 0 || result.aiNote != nil ? result : nil
    }
}
