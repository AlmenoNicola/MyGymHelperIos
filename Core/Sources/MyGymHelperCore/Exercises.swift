import Foundation

public struct Exercise: Codable, Identifiable, Hashable, Sendable {
    public let id: Int
    public let name: String
    public let primaryMuscles: [String]
    public let secondaryMuscles: [String]?
    public let category: String?      // attrezzatura (Barbell, Dumbbells, Bodyweight...)
    public let difficulty: String?
    public let force: String?         // Push, Pull, Hold
    public let mechanic: String?      // Compound, Isolation
    public let steps: [String]

    enum CodingKeys: String, CodingKey {
        case id, name, category, difficulty, force, mechanic, steps
        case primaryMuscles = "primary_muscles"
        case secondaryMuscles = "secondary_muscles"
    }
}

/// Sorgente degli esercizi. Cosi' si puo' cambiare fornitore (MuscleWiki, dataset locale, ...)
/// senza toccare il resto dell'app.
public protocol ExerciseProvider: Sendable {
    func exercises(language: String) async throws -> [Exercise]
}
