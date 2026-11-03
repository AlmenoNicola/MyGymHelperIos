import Foundation

/// Obiettivi di una scheda per un esercizio (caricata dall'utente o dall'allenatore).
/// `perSet` = serie diverse (righe della scheda con lo stesso esercizio); vuoto = serie uguali.
public struct PlanTarget: Codable, Equatable, Sendable {
    public var sets: Int?
    public var repsMin: Int?
    public var repsMax: Int?
    public var restSeconds: Int?
    public var weightKg: Double?
    public var perSet: [SetTarget]
    public init(sets: Int? = nil, repsMin: Int? = nil, repsMax: Int? = nil, restSeconds: Int? = nil, weightKg: Double? = nil,
                perSet: [SetTarget] = []) {
        self.sets = sets; self.repsMin = repsMin; self.repsMax = repsMax
        self.restSeconds = restSeconds; self.weightKg = weightKg; self.perSet = perSet
    }
}

public struct SessionSetSample: Equatable, Sendable {
    public let doneReps: Int
    public let plannedReps: Int
    public let stoppedEarly: Bool
    public let averagePeak: Double   // proxy della velocita'; 0 se non disponibile
    public init(doneReps: Int, plannedReps: Int, stoppedEarly: Bool, averagePeak: Double = 0) {
        self.doneReps = doneReps; self.plannedReps = plannedReps
        self.stoppedEarly = stoppedEarly; self.averagePeak = averagePeak
    }
}

public struct SessionSample: Equatable, Sendable {
    public let date: Date
    public let weightKg: Double
    public let sets: [SessionSetSample]
    public init(date: Date, weightKg: Double, sets: [SessionSetSample]) {
        self.date = date; self.weightKg = weightKg; self.sets = sets
    }
}

public struct AdaptiveAdvice: Equatable, Sendable {
    public let weightKg: Double
    public let sets: Int
    public let reps: Int
    public let restSeconds: Int
    public let reasonKeys: [String]
}

/// Motore adattivo del piano Full: usa lo storico dell'esercizio (completamento, interruzioni, calo di velocita')
/// e, se presente, gli obiettivi della scheda caricata. Ogni consiglio ha un motivo spiegabile.
/// Soglie e incrementi sono un punto di partenza da rivedere con un professionista.
public enum AdaptiveCoach {
    /// Aumento di carico: circa 2,5% del peso, a passi di `step` (almeno un passo).
    static func increment(_ w: Double, step: Double) -> Double { max(step, ((w * 0.025) / step).rounded() * step) }

    /// Peso ridotto del fattore indicato, arrotondato per difetto al passo.
    static func lowered(_ w: Double, factor: Double, step: Double) -> Double { max(0, ((w * factor) / step).rounded(.down) * step) }

    static func completionRate(_ s: SessionSample) -> Double {
        let planned = s.sets.reduce(0) { $0 + $1.plannedReps }
        guard planned > 0 else { return 0 }
        return Double(s.sets.reduce(0) { $0 + min($1.doneReps, $1.plannedReps) }) / Double(planned)
    }

    /// Calo di velocita' tra prima e ultima serie (0...1), 0 se non misurabile.
    static func velocityDrop(_ s: SessionSample) -> Double {
        guard s.sets.count >= 2, let first = s.sets.first?.averagePeak, let last = s.sets.last?.averagePeak,
              first > 0, last > 0 else { return 0 }
        return max(0, 1 - last / first)
    }

    private static func clamp(_ v: Int, _ lo: Int, _ hi: Int) -> Int { min(max(v, lo), hi) }

    public static func advise(history: [SessionSample], isCompound: Bool, defaultSets: Int, defaultReps: Int,
                              plan: PlanTarget? = nil, weightStep: Double = 1.25) -> AdaptiveAdvice {
        let baseRest = plan?.restSeconds ?? (isCompound ? 120 : 75)
        guard let last = history.last, !last.sets.isEmpty else {
            return AdaptiveAdvice(weightKg: plan?.weightKg ?? 0,
                                  sets: clamp(plan?.sets ?? defaultSets, 1, 8),
                                  reps: clamp(plan?.repsMin ?? defaultReps, 1, 50),
                                  restSeconds: clamp(baseRest, 30, 300),
                                  reasonKeys: ["coach.nodata"])
        }
        let completion = completionRate(last)
        let stopped = last.sets.filter(\.stoppedEarly).count
        let fatigue = velocityDrop(last)
        let previous = history.dropLast().last
        let poorStreak = (previous.map { completionRate($0) < 0.8 } ?? false) && completion < 0.8

        var weight = last.weightKg
        var sets = plan?.sets ?? last.sets.count
        var reps = last.sets.first?.plannedReps ?? defaultReps
        var rest = baseRest
        var reasons: [String] = []

        func increment(_ w: Double) -> Double { Self.increment(w, step: weightStep) }
        func lowered(_ w: Double, _ factor: Double) -> Double { Self.lowered(w, factor: factor, step: weightStep) }

        if poorStreak {
            weight = lowered(weight, 0.9); rest += 30; reasons.append("coach.deload")
        } else if completion >= 1.0 && stopped == 0 {
            if fatigue < 0.2 {
                let ceiling = plan?.repsMax
                if weight == 0 || (ceiling != nil && reps < ceiling!) {
                    reps = min(reps + 1, ceiling ?? 50); reasons.append("coach.morereps")
                } else {
                    weight += increment(weight)
                    if let minReps = plan?.repsMin { reps = minReps }
                    reasons.append("coach.progress")
                }
                if plan?.sets == nil, sets < 5, last.sets.count >= 3, (previous.map { completionRate($0) >= 1 } ?? false) {
                    sets += 1; reasons.append("coach.addset")
                }
            } else if fatigue < 0.35 {
                rest += 15; reasons.append("coach.keepfatigue")
            } else {
                rest += 30; reasons.append("coach.highfatigue")
            }
        } else if completion >= 0.85 {
            rest += 15; reasons.append("coach.keep")
        } else if completion >= 0.7 {
            rest += 30; reasons.append("coach.keep")
        } else {
            weight = lowered(weight, 0.92)
            if plan?.sets == nil, sets > 2 { sets -= 1 }
            rest += 30; reasons.append("coach.reduce")
        }
        return AdaptiveAdvice(weightKg: weight, sets: clamp(sets, 1, 8), reps: clamp(reps, 1, 50),
                              restSeconds: clamp(rest, 30, 300), reasonKeys: reasons)
    }
}
