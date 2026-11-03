import Foundation

public enum BMICategory: Sendable {
    case underweight, normal, overweight, obese
}

public struct BMIResult: Sendable, Equatable {
    public let value: Double
    public let category: BMICategory
}

public enum BMICalculator {
    /// BMI = peso (kg) / altezza (m)^2. Valido per adulti; non sostituisce il parere di un medico.
    public static func calculate(weightKg: Double, heightCm: Double) -> BMIResult? {
        guard weightKg > 0, heightCm > 0 else { return nil }
        let m = heightCm / 100
        let bmi = weightKg / (m * m)
        let category: BMICategory
        switch bmi {
        case ..<18.5: category = .underweight
        case ..<25: category = .normal
        case ..<30: category = .overweight
        default: category = .obese
        }
        return BMIResult(value: bmi, category: category)
    }
}
