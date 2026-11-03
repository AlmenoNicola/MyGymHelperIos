import Foundation

public enum BiologicalSex: String, Codable, Sendable { case male, female }

public enum ActivityLevel: Double, Codable, Sendable {
    case sedentary = 1.2, light = 1.375, moderate = 1.55, high = 1.725, veryHigh = 1.9
}

public enum Goal: String, Codable, CaseIterable, Sendable { case lose, maintain, gain }

public enum DietType: String, Codable, CaseIterable, Sendable {
    case omnivore, vegetarian, glutenFree, vegan, lactoseFree
}

public struct DailyTargets: Sendable, Equatable {
    public let calories: Int
    public let proteinGrams: Int
    public let carbsGrams: Int
    public let fatGrams: Int
}

/// Calcoli generali di fabbisogno. I coefficienti sono indicativi e vanno rivisti
/// da un professionista prima del rilascio. Non sostituisce nutrizionista o medico.
public enum NutritionCalculator {
    /// Metabolismo basale, formula di Mifflin-St Jeor.
    public static func bmr(sex: BiologicalSex, weightKg: Double, heightCm: Double, ageYears: Int) -> Double {
        let base = 10 * weightKg + 6.25 * heightCm - 5 * Double(ageYears)
        return sex == .male ? base + 5 : base - 161
    }

    public static func targets(sex: BiologicalSex, weightKg: Double, heightCm: Double,
                               ageYears: Int, activity: ActivityLevel, goal: Goal) -> DailyTargets {
        let tdee = bmr(sex: sex, weightKg: weightKg, heightCm: heightCm, ageYears: ageYears) * activity.rawValue
        let adjusted: Double
        switch goal {
        case .lose: adjusted = tdee * 0.85
        case .maintain: adjusted = tdee
        case .gain: adjusted = tdee * 1.10
        }
        let proteinPerKg = goal == .maintain ? 1.6 : 1.8
        let protein = proteinPerKg * weightKg
        let fat = 0.9 * weightKg
        let carbsKcal = max(0, adjusted - protein * 4 - fat * 9)
        return DailyTargets(calories: Int(adjusted.rounded()),
                            proteinGrams: Int(protein.rounded()),
                            carbsGrams: Int((carbsKcal / 4).rounded()),
                            fatGrams: Int(fat.rounded()))
    }

    /// Fabbisogno per tutti e tre gli obiettivi (dimagrire, mantenere, aumentare), da mostrare affiancati.
    public static func allTargets(sex: BiologicalSex, weightKg: Double, heightCm: Double,
                                  ageYears: Int, activity: ActivityLevel) -> [Goal: DailyTargets] {
        var out: [Goal: DailyTargets] = [:]
        for goal in Goal.allCases {
            out[goal] = targets(sex: sex, weightKg: weightKg, heightCm: heightCm, ageYears: ageYears, activity: activity, goal: goal)
        }
        return out
    }

    /// Obiettivo consigliato dal BMI: sottopeso -> aumentare, normopeso -> mantenere, sovrappeso e obesita' -> dimagrire.
    public static func recommendedGoal(_ category: BMICategory) -> Goal {
        switch category {
        case .underweight: return .gain
        case .normal: return .maintain
        case .overweight, .obese: return .lose
        }
    }

    /// Obiettivo da usare: quello scelto dall'utente oppure, finche' non ne ha scelto uno, quello consigliato dal BMI
    /// (se il BMI non si puo' calcolare: mantenere).
    public static func effectiveGoal(chosen: Bool, goalRaw: String, weightKg: Double, heightCm: Double) -> Goal {
        if chosen { return Goal(rawValue: goalRaw) ?? .maintain }
        guard let bmi = BMICalculator.calculate(weightKg: weightKg, heightCm: heightCm) else { return .maintain }
        return recommendedGoal(bmi.category)
    }
}
