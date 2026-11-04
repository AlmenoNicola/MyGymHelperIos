import Foundation
import MyGymHelperCore

/// Prepara i dati dello storico (SwiftData) per i motori di consiglio del Core.
enum CoachingService {
    static func samples(for exerciseID: String, from sessions: [WorkoutSessionRecord]) -> [SessionSample] {
        sessions
            .filter { $0.exerciseID == exerciseID && !$0.sets.isEmpty }
            .sorted { $0.startedAt < $1.startedAt }
            .map { s in
                // Serie diverse: il peso di riferimento e' il piu' alto della sessione.
                SessionSample(date: s.startedAt, weightKg: s.maxWeightKg,
                              sets: s.sets.sorted { $0.number < $1.number }.map {
                                  SessionSetSample(doneReps: $0.doneReps, plannedReps: $0.plannedReps,
                                                   stoppedEarly: $0.stoppedEarly, averagePeak: $0.averagePeak)
                              })
            }
    }

    static func historyEntries(from sessions: [WorkoutSessionRecord], catalog: [CatalogExercise]) -> [HistoryEntry] {
        sessions.compactMap { s in
            guard let ex = catalog.first(where: { $0.id == s.exerciseID }) else { return nil }
            return HistoryEntry(date: s.startedAt, exerciseID: ex.id, primary: ex.primary, setsDone: s.sets.count)
        }
    }

    /// Obiettivi della scheda caricata per un esercizio, se il nome corrisponde.
    static func planTarget(for exercise: CatalogExercise, plans: [TrainingPlanRecord]) -> PlanTarget? {
        guard let record = plans.sorted(by: { $0.createdAt > $1.createdAt }).first,
              let plan = try? JSONDecoder().decode(TrainingPlan.self, from: record.data) else { return nil }
        // Prima la voce collegata all'esercizio, poi quelle non collegate con il nome simile
        if let linked = plan.allEntries.first(where: { $0.exerciseID == exercise.id }) { return linked.target }
        let best = plan.allEntries
            .filter { $0.exerciseID == nil }
            .map { ($0, ExerciseMatcher.similarity($0.name, exercise.name)) }
            .filter { $0.1 >= 0.5 }
            .max { $0.1 < $1.1 }
        return best?.0.target
    }

    /// Consiglio adattivo del piano Pro per il prossimo allenamento dell'esercizio.
    static func adaptive(exercise: CatalogExercise, sessions: [WorkoutSessionRecord],
                         plans: [TrainingPlanRecord], defaultSets: Int, defaultReps: Int) -> AdaptiveAdvice {
        AdaptiveCoach.advise(history: samples(for: exercise.id, from: sessions), isCompound: exercise.isCompound,
                             defaultSets: defaultSets, defaultReps: defaultReps,
                             plan: planTarget(for: exercise, plans: plans))
    }

    /// Consiglio a regole fisse (ex piano Mid, ora parte del Pro) sull'ultima sessione dell'esercizio.
    static func fixed(exercise: CatalogExercise, sessions: [WorkoutSessionRecord]) -> CoachingResult? {
        guard let last = samples(for: exercise.id, from: sessions).last else { return nil }
        let outcomes = last.sets.map { SetOutcome(plannedReps: $0.plannedReps, doneReps: $0.doneReps, stoppedEarly: $0.stoppedEarly) }
        return FixedCoaching.advise(sets: outcomes, isCompound: exercise.isCompound, isLowerBody: exercise.isLowerBody)
    }
}
