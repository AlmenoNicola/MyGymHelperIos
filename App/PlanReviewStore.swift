import Foundation
import Observation
import SwiftData
import FoundationModels
import MyGymHelperCore

/// Revisione della scheda ogni due settimane (piano Pro), come PlanReviewService.kt su Android.
/// La scheda usata e' la piu' recente (la stessa dei consigli). La proposta a regole del Core si salva subito;
/// se l'iPhone ha Apple Intelligence, il modello la rivede (un passo al massimo, nella direzione chiesta) e scrive
/// una nota. Lo stato (ultimo controllo, proposta in attesa, copia per tornare indietro) si salva con il consenso
/// in Application Support/plan-review.json, escluso dai backup, e si cancella con i dati sanitari.
@Observable
@MainActor
final class PlanReviewStore {
    static let shared = PlanReviewStore()

    private(set) var state = PlanReviewState()
    /// Vero mentre l'AI del telefono rivede la proposta.
    private(set) var working = false

    private var fileURL: URL { URL.applicationSupportDirectory.appending(path: "plan-review.json") }
    private var persistent: Bool { UserDefaults.standard.double(forKey: ConsentStore.grantedAtKey) > 0 }
    private var context: ModelContext { PersistenceController.container.mainContext }

    private init() { load() }

    // MARK: Scheda attiva e domanda

    /// Scheda usata per i consigli e per la revisione: la piu' recente.
    static func activePlan(_ plans: [TrainingPlanRecord]) -> (record: TrainingPlanRecord, plan: TrainingPlan)? {
        guard let record = plans.max(by: { $0.createdAt < $1.createdAt }),
              let plan = try? JSONDecoder().decode(TrainingPlan.self, from: record.data) else { return nil }
        return (record, plan)
    }

    /// Proposta in attesa, se la sua scheda esiste ancora.
    func pending(in plans: [TrainingPlanRecord]) -> PlanReview? {
        guard let p = state.pending, plans.contains(where: { $0.id == p.planID }) else { return nil }
        return p
    }

    /// Copia per tornare indietro, se la sua scheda esiste ancora.
    func backup(in plans: [TrainingPlanRecord]) -> PlanBackup? {
        guard let b = state.backup, plans.contains(where: { $0.id == b.planID }) else { return nil }
        return b
    }

    /// Vero se a fine allenamento va fatta la domanda (l'esercizio appena fatto e' della scheda attiva).
    func shouldAsk(plans: [TrainingPlanRecord], sessions: [WorkoutSessionRecord], catalog: [CatalogExercise],
                   exerciseID: String, now: Date = Date()) -> Bool {
        guard let active = Self.activePlan(plans) else { return false }
        let ids = Set(active.plan.allEntries.compactMap { PlanAI.exercise(for: $0, in: catalog)?.id })
        guard ids.contains(exerciseID) else { return false }
        let dates = sessions.filter { ids.contains($0.exerciseID) && !$0.sets.isEmpty }.map(\.startedAt)
        return PlanReviewer.isDue(state, planCreatedAt: active.record.createdAt, planSessionDates: dates, now: now)
    }

    /// Risposta dell'utente: prepara la proposta (subito a regole, poi con l'AI se c'e').
    func start(_ feedback: PlanFeedback, plans: [TrainingPlanRecord], sessions: [WorkoutSessionRecord], catalog: [CatalogExercise]) {
        guard let active = Self.activePlan(plans) else { return }
        let now = Date()
        let review = PlanReviewer.build(planID: active.record.id, planName: active.record.name, plan: active.plan,
                                        feedback: feedback, now: now,
                                        resolve: { PlanAI.exercise(for: $0, in: catalog) },
                                        samplesFor: { CoachingService.samples(for: $0, from: sessions) })
        state.lastCheckAt = now
        state.pending = review.changes.isEmpty ? nil : review
        save()
        guard !review.changes.isEmpty, PlanReviewAI.available else { return }
        working = true
        Task { [weak self] in
            let refined = await PlanReviewAI.refine(review)
            guard let self else { return }
            self.working = false
            // Solo se nel frattempo la proposta non e' stata applicata o sostituita.
            guard let refined, self.state.pending?.createdAt == review.createdAt else { return }
            self.state.pending = refined
            self.save()
        }
    }

    /// "Ignora": la proposta si scarta; la prossima domanda arriva fra due settimane.
    func discard() { state.pending = nil; save() }

    // MARK: Applica e torna indietro

    /// "Applica": aggiorna la scheda e gli elenchi che contengono gli esercizi modificati, e tiene la copia di prima
    /// (una versione) per "Torna alla scheda precedente". false se la scheda non esiste piu'.
    @discardableResult
    func apply(_ review: PlanReview, plans: [TrainingPlanRecord]) -> Bool {
        guard let record = plans.first(where: { $0.id == review.planID }),
              let plan = try? JSONDecoder().decode(TrainingPlan.self, from: record.data),
              let data = try? JSONEncoder().encode(PlanReviewer.apply(review, to: plan)) else { return false }
        let store = WorkoutListStore.shared
        var lists: [UUID: [WorkoutItem]] = [:]
        for l in store.lists { lists[l.id] = l.items }
        let touched = PlanReviewer.touchedLists(lists, review: review)
        state.backup = PlanBackup(planID: record.id, appliedAt: Date(), plan: plan,
                                  listItems: lists.filter { touched.contains($0.key) },
                                  exerciseIDs: review.changes.filter(\.changed).map(\.exerciseID))
        state.pending = nil
        record.data = data
        try? context.save()
        for id in touched { store.replaceItems(PlanReviewer.apply(review, to: lists[id] ?? []), in: id) }
        save()
        return true
    }

    /// "Torna alla scheda precedente": la scheda torna com'era prima dell'ultimo "Applica"; negli elenchi tornano
    /// serie, ripetizioni, pesi e pausa degli esercizi di allora (restano quelli aggiunti dopo e lo stato "fatto").
    func restore(plans: [TrainingPlanRecord]) {
        guard let b = state.backup else { return }
        if let record = plans.first(where: { $0.id == b.planID }), let data = try? JSONEncoder().encode(b.plan) {
            record.data = data
            try? context.save()
        }
        let store = WorkoutListStore.shared
        for (id, old) in b.listItems {
            guard let list = store.list(id) else { continue }
            let items = list.items.map { item in old.first { $0.id == item.id }.map { item.with($0.parameters) } ?? item }
            store.replaceItems(items, in: id)
        }
        state.backup = nil
        save()
    }

    /// Strumenti di test (cronologia finta): azzera ultimo controllo, proposta e copia per tornare indietro.
    func resetForTests() { state = PlanReviewState(); working = false; save() }

    // MARK: Salvataggio

    /// Dopo "Elimina dati" o la revoca del consenso.
    func clear() {
        state = PlanReviewState(); working = false
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func load() {
        guard persistent, let data = try? Data(contentsOf: fileURL),
              let s = try? JSONDecoder().decode(PlanReviewState.self, from: data) else { return }
        state = s
    }

    private func save() {
        guard persistent, let data = try? JSONEncoder().encode(state) else { return }
        var url = fileURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true            // dato ricavato dallo storico: resta solo su questo iPhone
        try? url.setResourceValues(values)
    }
}

/// Apple Intelligence (FoundationModels) per ritoccare la proposta: stessa richiesta e stessa lettura delle righe
/// di Android (PlanReviewer.aiPrompt / decodeAI). nil se non disponibile o se la risposta non cambia nulla.
enum PlanReviewAI {
    static var available: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    static func refine(_ review: PlanReview) async -> PlanReview? {
        let italian = (Locale.current.language.languageCode?.identifier ?? "en") == "it"
        let session = LanguageModelSession()
        do {
            let response = try await session.respond(to: PlanReviewer.aiPrompt(review, italian: italian))
            let decoded = PlanReviewer.decodeAI(response.content)
            let refined = PlanReviewer.applyAI(review, adjustments: decoded.adjustments, note: decoded.note)
            return refined.byAI ? refined : nil
        } catch {
            return nil
        }
    }
}
