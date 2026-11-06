import Foundation

// MARK: - Calorie bruciate (stima) negli allenamenti (uguale su Android: Calories.kt)

/// Stima delle calorie con il metodo MET: kcal = MET × peso corporeo (kg) × ore.
/// Contano solo le serie con almeno una ripetizione. Tempo = durata misurata di ogni serie fatta (riportata tra 1,5 e
/// 8 s a ripetizione; 3 s a ripetizione se la durata è 0) + pausa tra le serie fatte ((serie fatte − 1) × pausa: la
/// pausa dopo l'ultima serie non conta). MET 6,0 per i multiarticolari, 3,5 per gli altri e per il conteggio libero.
/// È solo una stima indicativa, non una misura.
public enum CalorieEstimator {
    public static let metCompound = 6.0
    public static let metIsolation = 3.5
    /// Peso usato se quello corporeo non è inserito (si mostra calories.defaultWeight).
    public static let defaultBodyWeightKg = 70.0
    public static let secondsPerRep = 3.0
    public static let minSecondsPerRep = 1.5
    public static let maxSecondsPerRep = 8.0

    public static func met(isCompound: Bool) -> Double { isCompound ? metCompound : metIsolation }

    /// Secondi di lavoro di una serie: durata misurata, riportata tra 1,5 e 8 s a ripetizione (3 s se manca).
    public static func activeSeconds(doneReps: Int, durationSeconds: Double) -> Double {
        if doneReps <= 0 { return 0 }
        if durationSeconds <= 0 { return Double(doneReps) * secondsPerRep }
        return min(max(durationSeconds, Double(doneReps) * minSecondsPerRep), Double(doneReps) * maxSecondsPerRep)
    }

    /// Calorie di un esercizio: serie fatte, pausa tra le serie, tipo di esercizio e peso corporeo (nil o ≤ 0: 70 kg).
    public static func exerciseKcal(sets: [SetRecord], restSeconds: Int, isCompound: Bool, bodyWeightKg: Double?) -> Double {
        let done = sets.filter { $0.doneReps > 0 }
        if done.isEmpty { return 0 }
        let work = done.reduce(0.0) { $0 + activeSeconds(doneReps: $1.doneReps, durationSeconds: $1.durationSeconds) }
        let rest = Double(done.count - 1) * Double(max(restSeconds, 0))
        let weight = bodyWeightKg.flatMap { $0 > 0 ? $0 : nil } ?? defaultBodyWeightKg
        return met(isCompound: isCompound) * weight * (work + rest) / 3600
    }

    /// Peso corporeo: ultima pesata del Profilo (la più recente per data), altrimenti il peso del profilo; nil se non c'è.
    public static func bodyWeight(weights: [WeightEntry], profileWeightKg: Double?) -> Double? {
        if let last = weights.max(by: { $0.at < $1.at }), last.kg > 0 { return last.kg }
        if let p = profileWeightKg, p > 0 { return p }
        return nil
    }

    /// Totale dell'elenco: solo gli esercizi fatti.
    public static func listKcal(_ items: [WorkoutItem]) -> Double {
        items.filter(\.done).reduce(0.0) { $0 + max($1.kcal, 0) }
    }

    /// Valore da mostrare: intero, metà verso l'alto, negativi a 0.
    public static func display(_ kcal: Double) -> Int { Int(max(kcal, 0).rounded()) }
}
