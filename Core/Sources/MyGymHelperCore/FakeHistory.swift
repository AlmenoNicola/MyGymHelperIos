import Foundation

// MARK: - Cronologia finta per le prove (solo build di debug)
//
// Serve a provare la revisione della scheda ogni due settimane senza aspettare: crea sessioni finte degli esercizi
// della scheda attiva negli ultimi 12 giorni e sposta indietro le date delle schede, cosi' la domanda compare alla
// prossima fine allenamento. Le sessioni finte si ricordano per poterle togliere.
// Uguale su Android: FakeHistory.kt.

/// Andamento simulato: tutto facile (ripetizioni complete, velocita' stabile) o faticoso (serie interrotte).
public enum FakeHistoryKind: Sendable { case easy, hard }

public struct FakeSet: Equatable, Sendable {
    public let number: Int
    public let plannedReps: Int
    public let doneReps: Int
    public let stoppedEarly: Bool
    public let weightKg: Double
    public let averagePeak: Double
}

public struct FakeSession: Equatable, Sendable {
    public let exerciseID: String
    public let exerciseName: String
    public let startedAt: Date
    public let restSeconds: Int
    public let sets: [FakeSet]
    public var weightKg: Double { sets.first?.weightKg ?? 0 }
}

public enum FakePlanHistory {
    /// Giorni fa delle sessioni finte (tutte nelle ultime due settimane).
    public static let daysAgo = [12, 8, 4, 1]
    /// Peso usato se la scheda non lo indica e l'esercizio non e' a corpo libero.
    public static let defaultWeight = 20.0

    /// Sessioni finte: per ogni esercizio della scheda (collegato al catalogo) una sessione per ogni giorno di `daysAgo`.
    public static func sessions(_ entries: [(PlanEntry, CatalogExercise)], kind: FakeHistoryKind, now: Date) -> [FakeSession] {
        var out: [FakeSession] = []
        var seen = Set<String>()
        for (index, pair) in entries.enumerated() {
            let (entry, ex) = pair
            guard seen.insert(ex.id).inserted else { continue }
            let fallback = ex.equipment.localizedCaseInsensitiveContains("body") ? 0 : defaultWeight
            let targets = PlanReviewer.baseTargets(entry, lastWeight: fallback)
            let rest = entry.restSeconds ?? WorkoutItem.defaultParameters.restSeconds
            for days in daysAgo {
                // Esercizi della stessa giornata a pochi minuti l'uno dall'altro.
                let start = now.addingTimeInterval(-Double(days) * 86_400 + Double(index) * 600)
                let sets = targets.enumerated().map { (i, t) -> FakeSet in
                    let tired = kind == .hard && i >= targets.count - 2
                    return FakeSet(number: i + 1, plannedReps: t.reps, doneReps: tired ? max(1, t.reps / 2) : t.reps,
                                   stoppedEarly: tired, weightKg: t.weightKg,
                                   averagePeak: kind == .hard ? 1.0 - 0.15 * Double(i) : 1.0)
                }
                out.append(FakeSession(exerciseID: ex.id, exerciseName: ex.name, startedAt: start, restSeconds: rest, sets: sets))
            }
        }
        return out.sorted { $0.startedAt < $1.startedAt }
    }

    /// Quanto spostare indietro le date di tutte le schede (secondi, 0 se non serve) perche' quella attiva risulti
    /// caricata da piu' di due settimane. Spostandole tutte insieme la scheda attiva resta la piu' recente.
    public static func planShift(activeCreatedAt: Date, now: Date) -> TimeInterval {
        let target = now.addingTimeInterval(-PlanReviewer.interval - 86_400)
        return activeCreatedAt > target ? target.timeIntervalSince(activeCreatedAt) : 0
    }
}
