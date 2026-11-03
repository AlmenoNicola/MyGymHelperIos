import Foundation

public struct SetOutcome: Sendable, Equatable {
    public let plannedReps: Int
    public let doneReps: Int
    public let stoppedEarly: Bool
    public init(plannedReps: Int, doneReps: Int, stoppedEarly: Bool) {
        self.plannedReps = plannedReps; self.doneReps = doneReps; self.stoppedEarly = stoppedEarly
    }
    public var completed: Bool { !stoppedEarly && doneReps >= plannedReps }
}

public enum CoachingAdvice: Sendable, Equatable {
    case increaseWeight(byKg: Double)
    case keepAsIs
    case decreaseWeight(percent: Int)
    case addSet
    case removeSet
}

public struct CoachingResult: Sendable, Equatable {
    public let advice: [CoachingAdvice]
    public let restSeconds: Int
    /// Chiavi di localizzazione per spiegare il motivo all'utente.
    public let reasonKey: String
}

/// Regole fisse del piano Mid. Il piano Full usa un motore adattivo (da sviluppare).
public enum FixedCoaching {
    public static func advise(sets: [SetOutcome], isCompound: Bool, isLowerBody: Bool,
                              maxSets: Int = 5, minSets: Int = 2) -> CoachingResult {
        let rest = isCompound ? 120 : 75
        guard !sets.isEmpty else { return CoachingResult(advice: [.keepAsIs], restSeconds: rest, reasonKey: "coach.nodata") }
        let completedCount = sets.filter(\.completed).count
        let allDone = completedCount == sets.count
        let stopped = sets.filter(\.stoppedEarly).count

        if allDone {
            var advice: [CoachingAdvice] = [.increaseWeight(byKg: isLowerBody ? 2.5 : 1.25)]
            if sets.count < maxSets && sets.count >= 3 { advice.append(.addSet) }
            return CoachingResult(advice: advice, restSeconds: rest, reasonKey: "coach.alldone")
        }
        if stopped * 2 >= sets.count {
            var advice: [CoachingAdvice] = [.decreaseWeight(percent: 10)]
            if sets.count > minSets { advice.append(.removeSet) }
            return CoachingResult(advice: advice, restSeconds: rest + 30, reasonKey: "coach.manystopped")
        }
        return CoachingResult(advice: [.keepAsIs], restSeconds: rest, reasonKey: "coach.keep")
    }
}
