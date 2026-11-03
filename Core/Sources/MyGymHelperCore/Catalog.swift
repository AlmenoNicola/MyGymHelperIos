import Foundation

public enum Mechanic: String, Codable, Sendable { case compound, isolation }

/// Famiglia di esercizi usata dai filtri dell'app. Le categorie del Free Exercise DB
/// (strength, powerlifting, olympic, strongman, plyometrics, stretching, cardio) si raggruppano in quattro.
public enum ExerciseKind: String, CaseIterable, Identifiable, Sendable {
    case strength, plyometrics, stretching, cardio

    public var id: String { rawValue }
    public var titleKey: String { "kind.\(rawValue)" }

    public static func of(_ category: String) -> ExerciseKind {
        switch category {
        case "plyometrics": return .plyometrics
        case "stretching": return .stretching
        case "cardio": return .cardio
        default: return .strength   // strength, powerlifting, olympic, strongman e le fonti senza categoria
        }
    }
}

/// Esercizio del catalogo dell'app, indipendente dalla fonte (elenco incluso nell'app o API).
public struct CatalogExercise: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let primary: [MuscleGroup]
    public let secondary: [MuscleGroup]
    public let equipment: String
    public let mechanic: Mechanic
    public let steps: [String]
    /// Categoria della fonte (strength, stretching, cardio ...).
    public let category: String
    /// Livello: beginner, intermediate, expert (vuoto se la fonte non lo indica).
    public let level: String
    /// Foto dell'esercizio (posizione iniziale e finale), scaricate solo quando servono.
    public let images: [String]

    public init(id: String, name: String, primary: [MuscleGroup], secondary: [MuscleGroup] = [],
                equipment: String = "", mechanic: Mechanic = .compound, steps: [String] = [],
                category: String = "strength", level: String = "", images: [String] = []) {
        self.id = id; self.name = name; self.primary = primary; self.secondary = secondary
        self.equipment = equipment; self.mechanic = mechanic; self.steps = steps
        self.category = category; self.level = level; self.images = images
    }

    enum CodingKeys: String, CodingKey { case id, name, primary, secondary, equipment, mechanic, steps, category, level, images }

    /// I campi aggiunti dopo (categoria, livello, foto) sono facoltativi: i dati salvati prima restano leggibili.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        primary = try c.decode([MuscleGroup].self, forKey: .primary)
        secondary = try c.decodeIfPresent([MuscleGroup].self, forKey: .secondary) ?? []
        equipment = try c.decodeIfPresent(String.self, forKey: .equipment) ?? ""
        mechanic = try c.decodeIfPresent(Mechanic.self, forKey: .mechanic) ?? .compound
        steps = try c.decodeIfPresent([String].self, forKey: .steps) ?? []
        category = try c.decodeIfPresent(String.self, forKey: .category) ?? "strength"
        level = try c.decodeIfPresent(String.self, forKey: .level) ?? ""
        images = try c.decodeIfPresent([String].self, forKey: .images) ?? []
    }

    public var isLowerBody: Bool { primary.contains { $0.isLowerBody } }
    public var isCompound: Bool { mechanic == .compound }
    public var kind: ExerciseKind { .of(category) }

    /// Esercizio di forza o pliometria: gli unici proposti dai consigli (niente stretching, cardio o foam roller).
    public var isTraining: Bool { (kind == .strength || kind == .plyometrics) && equipment != "foamRoll" }
}

/// Formato dell'elenco di esercizi incluso nell'app: i 25 scritti da noi (id "seed-") e quelli del
/// Free Exercise DB (id "fedb-", pubblico dominio, tradotti in italiano), con testi in piu' lingue.
struct SeedExercise: Decodable {
    let id: String
    let muscles: [String]
    let secondary: [String]?
    let equipment: String
    let mechanic: String
    let names: [String: String]
    let steps: [String: [String]]
    let category: String?
    let level: String?
    let images: [String]?
}

public enum SeedCatalog {
    public static func decode(_ data: Data, language: String) throws -> [CatalogExercise] {
        let seeds = try JSONDecoder().decode([SeedExercise].self, from: data)
        return seeds.compactMap { s in
            let primary = s.muscles.compactMap(MuscleGroup.init(rawValue:))
            guard !primary.isEmpty else { return nil }
            return CatalogExercise(
                id: s.id,
                name: s.names[language] ?? s.names["en"] ?? s.id,
                primary: primary,
                secondary: (s.secondary ?? []).compactMap(MuscleGroup.init(rawValue:)),
                equipment: s.equipment,
                mechanic: s.mechanic == "isolation" ? .isolation : .compound,
                steps: (s.steps[language]).flatMap { $0.isEmpty ? nil : $0 } ?? s.steps["en"] ?? [],
                category: s.category ?? "strength",
                level: s.level ?? "",
                images: s.images ?? [])
        }
    }
}

extension Exercise {
    /// Converte un esercizio dell'API in esercizio del catalogo (scartato se i muscoli non sono riconosciuti).
    public func toCatalog() -> CatalogExercise? {
        let primary = primaryMuscles.compactMap(MuscleGroup.init(apiName:))
        guard !primary.isEmpty else { return nil }
        let secondary = (secondaryMuscles ?? []).compactMap(MuscleGroup.init(apiName:))
        let isIsolation = (mechanic ?? "").lowercased().contains("isolation")
        return CatalogExercise(id: "mw-\(id)", name: name, primary: primary, secondary: secondary,
                               equipment: category ?? "", mechanic: isIsolation ? .isolation : .compound, steps: steps)
    }
}

public enum CatalogAccess {
    /// Piano Free: un esercizio per tipologia (gruppo muscolare principale), scelto tra i nostri ("seed-")
    /// e poi in ordine di id; solo esercizi di forza o pliometria. Mid e Full: catalogo completo.
    public static func visible(_ all: [CatalogExercise], tier: SubscriptionTier) -> [CatalogExercise] {
        if FeatureGate.isAvailable(.catalogFull, for: tier) { return all }
        var seen = Set<MuscleGroup>()
        var result: [CatalogExercise] = []
        let ordered = all.filter(\.isTraining).sorted { a, b in
            let sa = a.id.hasPrefix("seed-"), sb = b.id.hasPrefix("seed-")
            return sa != sb ? sa : a.id < b.id
        }
        for exercise in ordered {
            guard let muscle = exercise.primary.first, !seen.contains(muscle) else { continue }
            seen.insert(muscle)
            result.append(exercise)
        }
        return result
    }
}

/// Attrezzi che l'utente ha in casa (solo piano Full, Feature.homeEquipment). Uguale a HomeEquipment in Catalog.kt.
/// Con il filtro attivo restano gli esercizi a corpo libero (o senza attrezzo indicato) e quelli con un attrezzo
/// posseduto; gli esercizi con un attrezzo sconosciuto (nomi liberi delle fonti esterne) si nascondono.
public enum HomeEquipment {
    /// Attrezzi che si possono segnare (nomi del catalogo, tradotti con equipment.<nome>). Il corpo libero non serve segnarlo.
    public static let choices: [String] = [
        "dumbbell", "barbell", "ezBar", "kettlebell", "band", "exerciseBall",
        "medicineBall", "foamRoll", "cable", "machine", "other"
    ]

    /// Esercizi sempre fattibili: corpo libero o senza attrezzo indicato.
    public static let alwaysAvailable: Set<String> = ["bodyweight", ""]

    /// Chiavi delle impostazioni (stesse su Android).
    public static let ownedKey = "equipment.owned"
    public static let filterKey = "equipment.filter"

    public static func isDoable(_ exercise: CatalogExercise, owned: Set<String>) -> Bool {
        alwaysAvailable.contains(exercise.equipment) || owned.contains(exercise.equipment)
    }

    /// Applica il filtro solo se e' acceso (chi lo chiama controlla anche il piano).
    public static func filter(_ list: [CatalogExercise], owned: Set<String>, enabled: Bool) -> [CatalogExercise] {
        enabled ? list.filter { isDoable($0, owned: owned) } : list
    }

    /// Salvataggio: nomi separati da virgola, nell'ordine di `choices`.
    public static func encode(_ owned: Set<String>) -> String {
        choices.filter { owned.contains($0) }.joined(separator: ",")
    }

    /// Lettura: si tengono solo i nomi conosciuti.
    public static func decode(_ raw: String?) -> Set<String> {
        Set((raw ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { choices.contains($0) })
    }
}

/// Filtri ed elenchi a pagine del catalogo (con quasi 900 esercizi non si mostrano tutti insieme).
public enum CatalogFilter {
    /// Esercizi mostrati per volta negli elenchi; "Mostra altri" ne aggiunge altrettanti.
    public static let pageSize = 40

    public static func byKind(_ list: [CatalogExercise], kind: ExerciseKind?) -> [CatalogExercise] {
        guard let kind else { return list }
        return list.filter { $0.kind == kind }
    }

    /// Esercizio a corpo libero: nessun attrezzo (anche le fonti esterne che scrivono "Bodyweight").
    public static func isBodyweight(_ exercise: CatalogExercise) -> Bool {
        exercise.equipment.lowercased() == "bodyweight"
    }

    /// Filtro "Corpo libero": se acceso esclude tutti gli esercizi che usano un attrezzo.
    public static func bodyweightOnly(_ list: [CatalogExercise], on: Bool) -> [CatalogExercise] {
        on ? list.filter(isBodyweight) : list
    }
}

/// Collega il nome di un esercizio di una scheda a un esercizio del catalogo (somiglianza tra parole).
public enum ExerciseMatcher {
    private static let stopwords: Set<String> = ["con", "da", "al", "di", "il", "la", "lo", "the", "with", "a", "e", "and", "on"]

    static func tokens(_ s: String) -> Set<String> {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        let parts = folded.components(separatedBy: CharacterSet.alphanumerics.inverted)
        return Set(parts.filter { $0.count > 1 && !stopwords.contains($0) })
    }

    public static func similarity(_ a: String, _ b: String) -> Double {
        let ta = tokens(a), tb = tokens(b)
        guard !ta.isEmpty, !tb.isEmpty else { return 0 }
        return Double(ta.intersection(tb).count) / Double(ta.union(tb).count)
    }

    public static func bestMatch(for name: String, in catalog: [CatalogExercise], threshold: Double = 0.5) -> CatalogExercise? {
        let scored = catalog.map { ($0, similarity(name, $0.name)) }.filter { $0.1 >= threshold }
        return scored.max(by: { $0.1 < $1.1 })?.0
    }
}
