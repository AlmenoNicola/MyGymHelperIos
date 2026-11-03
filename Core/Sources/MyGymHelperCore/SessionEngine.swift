import Foundation

public enum SessionPhase: Equatable, Sendable {
    case notStarted
    case working(set: Int)
    case resting(afterSet: Int, remaining: Int)
    case finished
}

/// Avvisi che l'app trasforma in suono, vibrazione e voce.
public enum SessionCue: Equatable, Sendable {
    case setStarted(Int)          // "Via!"
    case targetReached            // "Serie completata, fermati"
    case restStarted(seconds: Int)
    case restCountdown(Int)       // 3, 2, 1
    case restEnded                // "Ricomincia"
    case sessionFinished
}

public struct SetRecord: Equatable, Sendable {
    public let number: Int
    public let plannedReps: Int
    public let doneReps: Int
    public let stoppedEarly: Bool
    public let durationSeconds: Double

    public var outcome: SetOutcome {
        SetOutcome(plannedReps: plannedReps, doneReps: doneReps, stoppedEarly: stoppedEarly)
    }
}

/// Macchina a stati della sessione di allenamento. Non dipende da UI, sensori o orologio:
/// il tempo arriva dall'esterno (`now`), cosi' si testa senza telefono e si riscrive uguale su Android.
/// Ogni serie ha le sue ripetizioni obiettivo (serie diverse); con `init(sets:reps:restSeconds:)` sono tutte uguali.
public struct SessionEngine {
    private let plan: [Int]
    public let totalSets: Int
    public let restSeconds: Int
    public private(set) var phase: SessionPhase = .notStarted
    public private(set) var records: [SetRecord] = []
    public private(set) var currentReps = 0

    private var setStartedAt: TimeInterval = 0
    private var restEndsAt: TimeInterval = 0
    private var lastCountdown: Int?

    /// `repsPerSet` = ripetizioni obiettivo di ogni serie, nell'ordine.
    public init(repsPerSet: [Int], restSeconds: Int) {
        let p = repsPerSet.map { max(1, $0) }
        let list = p.isEmpty ? [1] : p
        self.plan = list
        self.totalSets = list.count
        self.restSeconds = max(0, restSeconds)
    }

    /// Serie tutte uguali: `sets` serie da `reps` ripetizioni.
    public init(sets: Int, reps: Int, restSeconds: Int) {
        self.init(repsPerSet: Array(repeating: reps, count: max(1, sets)), restSeconds: restSeconds)
    }

    /// Ripetizioni obiettivo della serie `set` (1 = prima).
    public func targetReps(forSet set: Int) -> Int { plan[min(max(set, 1), totalSets) - 1] }

    /// Ripetizioni obiettivo della serie in corso (in pausa: della prossima; a fine sessione: dell'ultima).
    public var targetReps: Int {
        switch phase {
        case .working(let n): return targetReps(forSet: n)
        case .resting(let n, _): return targetReps(forSet: n + 1)
        case .notStarted: return targetReps(forSet: 1)
        case .finished: return targetReps(forSet: totalSets)
        }
    }

    public mutating func start(at now: TimeInterval) -> [SessionCue] {
        guard phase == .notStarted else { return [] }
        beginSet(1, at: now)
        return [.setStarted(1)]
    }

    /// Ripetizioni contate dal sensore nella serie corrente (valore cumulativo). Ignorato durante la pausa.
    public mutating func repsCounted(_ count: Int, at now: TimeInterval) -> [SessionCue] {
        guard case .working = phase else { return [] }
        currentReps = min(max(count, currentReps), targetReps)
        guard currentReps >= targetReps else { return [] }
        return finishSet(done: targetReps, stoppedEarly: false, at: now)
    }

    /// L'utente dice di essersi fermato e indica quante ripetizioni ha fatto.
    public mutating func stop(doneReps: Int, at now: TimeInterval) -> [SessionCue] {
        guard case .working = phase else { return [] }
        let done = min(max(doneReps, 0), targetReps)
        return finishSet(done: done, stoppedEarly: done < targetReps, at: now)
    }

    /// Termina l'allenamento subito (la serie in corso viene salvata come interrotta, se ha ripetizioni).
    public mutating func endNow(at now: TimeInterval) -> [SessionCue] {
        switch phase {
        case .working(let n):
            if currentReps > 0 {
                records.append(SetRecord(number: n, plannedReps: targetReps(forSet: n), doneReps: currentReps,
                                         stoppedEarly: true, durationSeconds: max(0, now - setStartedAt)))
            }
            phase = .finished
            return [.sessionFinished]
        case .resting:
            phase = .finished
            return [.sessionFinished]
        default:
            return []
        }
    }

    /// Da chiamare spesso (per esempio 4 volte al secondo): aggiorna la pausa e produce il conto alla rovescia.
    public mutating func tick(at now: TimeInterval) -> [SessionCue] {
        guard case .resting(let n, _) = phase else { return [] }
        let remaining = Int((restEndsAt - now).rounded(.up))
        if remaining <= 0 {
            beginSet(n + 1, at: now)
            return [.restEnded]
        }
        phase = .resting(afterSet: n, remaining: remaining)
        if remaining <= 3, lastCountdown != remaining {
            lastCountdown = remaining
            return [.restCountdown(remaining)]
        }
        return []
    }

    public mutating func skipRest(at now: TimeInterval) -> [SessionCue] {
        guard case .resting(let n, _) = phase else { return [] }
        beginSet(n + 1, at: now)
        return [.restEnded]
    }

    private mutating func beginSet(_ number: Int, at now: TimeInterval) {
        phase = .working(set: number)
        currentReps = 0
        setStartedAt = now
    }

    private mutating func finishSet(done: Int, stoppedEarly: Bool, at now: TimeInterval) -> [SessionCue] {
        guard case .working(let n) = phase else { return [] }
        records.append(SetRecord(number: n, plannedReps: targetReps(forSet: n), doneReps: done,
                                 stoppedEarly: stoppedEarly, durationSeconds: max(0, now - setStartedAt)))
        var cues: [SessionCue] = stoppedEarly ? [] : [.targetReached]
        if n >= totalSets {
            phase = .finished
            cues.append(.sessionFinished)
            return cues
        }
        restEndsAt = now + Double(restSeconds)
        lastCountdown = nil
        phase = .resting(afterSet: n, remaining: restSeconds)
        cues.append(.restStarted(seconds: restSeconds))
        return cues
    }
}
