import Foundation

public struct HistoryEntry: Sendable {
    public let date: Date
    public let exerciseID: String
    public let primary: [MuscleGroup]
    public let setsDone: Int
    public init(date: Date, exerciseID: String, primary: [MuscleGroup], setsDone: Int) {
        self.date = date; self.exerciseID = exerciseID; self.primary = primary; self.setsDone = setsDone
    }
}

public struct Recommendation: Equatable, Sendable {
    public let exercise: CatalogExercise
    public let score: Double
    /// Chiave di localizzazione del motivo.
    public let reasonKey: String
}

/// Consigli sugli esercizi a regole fisse (Pro): privilegia i muscoli scelti che
/// hanno ricevuto meno serie negli ultimi 7 giorni, gli esercizi multiarticolari e quelli non ripetuti da poco.
public enum ExerciseRecommender {
    public static func recommend(from catalog: [CatalogExercise], targets: Set<MuscleGroup>,
                                 history: [HistoryEntry], now: Date = Date(), limit: Int = 5) -> [Recommendation] {
        let weekAgo = now.addingTimeInterval(-7 * 86_400)
        var weeklySets: [MuscleGroup: Int] = [:]
        var lastDone: [String: Date] = [:]
        for h in history {
            if let d = lastDone[h.exerciseID] { lastDone[h.exerciseID] = max(d, h.date) } else { lastDone[h.exerciseID] = h.date }
            guard h.date >= weekAgo else { continue }
            for m in h.primary { weeklySets[m, default: 0] += h.setsDone }
        }
        // Solo forza e pliometria: stretching, cardio e foam roller non sono "esercizi da allenamento".
        let training = catalog.filter(\.isTraining)
        let candidates = targets.isEmpty ? training : training.filter { !Set($0.primary).isDisjoint(with: targets) }
        let scored: [Recommendation] = candidates.map { ex in
            let needs = ex.primary.map { 1.0 / (1.0 + Double(weeklySets[$0, default: 0]) / 6.0) }
            let need = needs.reduce(0, +) / Double(max(needs.count, 1))
            var score = need
            if ex.isCompound { score += 0.25 }
            var reason = need > 0.7 ? "rec.undertrained" : (ex.isCompound ? "rec.compound" : "rec.variety")
            if let last = lastDone[ex.id] {
                if now.timeIntervalSince(last) < 48 * 3600 { score -= 0.5; reason = "rec.recent" }
            } else {
                score += 0.15
            }
            return Recommendation(exercise: ex, score: score, reasonKey: reason)
        }
        return scored.sorted { $0.score != $1.score ? $0.score > $1.score : $0.exercise.id < $1.exercise.id }
            .prefix(limit).map { $0 }
    }
}
