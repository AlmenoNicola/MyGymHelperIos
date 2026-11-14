import Foundation

/// Pesi di partenza consigliati (9 novembre 2026), uguale a StartingWeights.kt su Android.
/// Per un esercizio mai fatto si propone un peso prudente: una frazione del peso corporeo che dipende dall'attrezzo,
/// dal tipo di esercizio (multiarticolare o isolamento) e dalla zona (gambe/glutei o parte alta), corretta per sesso,
/// esperienza ed età e portata sulla griglia dei pulsanti +/- del peso.
public enum StartingWeights {
    /// Frazione del peso corporeo per l'esercizio; nil per esercizi non di forza o senza un carico da scegliere
    /// (corpo libero, elastici, palle, rullo, anello pilates, altro).
    public static func fraction(_ ex: CatalogExercise) -> Double? {
        guard ex.kind == .strength else { return nil }
        let legs = ex.isLowerBody, compound = ex.isCompound
        switch ex.equipment {
        case "barbell": return compound ? (legs ? 0.45 : 0.25) : 0.12
        case "ezBar": return compound ? 0.15 : 0.10
        case "dumbbell": return compound ? (legs ? 0.15 : 0.10) : 0.04      // per manubrio
        case "kettlebell": return legs ? 0.15 : 0.08
        case "machine": return compound ? (legs ? 0.45 : 0.25) : 0.18
        case "cable": return compound ? 0.12 : 0.07
        default: return nil
        }
    }

    /// Peso di partenza in kg, o nil se l'esercizio non ha un carico da scegliere o il peso corporeo non è valido.
    /// Donna x0,6; intermedio x1,3, avanzato x1,6; dai 65 anni x0,7, dai 50 x0,85; almeno 1 kg, sulla griglia dei +/-.
    public static func suggest(_ ex: CatalogExercise, sex: BiologicalSex, bodyWeightKg: Double, age: Int,
                               experience: Experience = .beginner) -> Double? {
        guard let f = fraction(ex), bodyWeightKg > 0 else { return nil }
        var w = bodyWeightKg * f
        if sex == .female { w *= 0.6 }
        switch experience {
        case .beginner: break
        case .intermediate: w *= 1.3
        case .advanced: w *= 1.6
        }
        if age >= 65 { w *= 0.7 } else if age >= 50 { w *= 0.85 }
        return snap(max(w, 1.0))
    }

    /// Peso di partenza dal profilo salvato (esperienza da principiante); nil senza profilo.
    public static func suggest(_ ex: CatalogExercise, profile: HealthProfile?) -> Double? {
        guard let profile else { return nil }
        return suggest(ex, sex: profile.sex == "female" ? .female : .male, bodyWeightKg: profile.weightKg,
                       age: profile.age, experience: .beginner)
    }

    /// Peso sulla griglia dei pulsanti +/-: passi di 0,5 kg fino a 4 kg, 1 kg fino a 10 kg, poi 5 kg (almeno 1 kg).
    public static func snap(_ w: Double) -> Double {
        let (step, base): (Double, Double) = w < 4 ? (0.5, 0) : w < 10 ? (1, 4) : (5, 10)
        let n = ((w - base) / step + 0.5).rounded(.down)
        return max(1.0, base + n * step)
    }
}
