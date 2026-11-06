import Foundation

public enum BodyRegion: String, CaseIterable, Codable, Sendable {
    // I glutei sono una zona a sé da novembre 2026, non più dentro Gambe (uguale su Android).
    case arms, legs, glutes, chest, back, shoulders, core

    public var muscles: [MuscleGroup] { MuscleGroup.allCases.filter { $0.region == self } }
}

/// Gruppi muscolari usati da catalogo, mappa del corpo e consigli.
public enum MuscleGroup: String, CaseIterable, Codable, Sendable, Hashable {
    case chest, shoulders, biceps, triceps, forearms, abs, obliques
    case traps, lats, lowerBack, glutes, quads, hamstrings, calves

    public var region: BodyRegion {
        switch self {
        case .chest: return .chest
        case .shoulders: return .shoulders
        case .biceps, .triceps, .forearms: return .arms
        case .abs, .obliques: return .core
        case .traps, .lats, .lowerBack: return .back
        case .glutes: return .glutes
        case .quads, .hamstrings, .calves: return .legs
        }
    }

    /// Parte bassa del corpo (telefono sulla coscia, incrementi di peso da gambe): gambe e glutei.
    public var isLowerBody: Bool { region == .legs || region == .glutes }

    /// Converte il nome di un muscolo dato da un'API esterna (da verificare con i dati reali di MuscleWiki).
    public init?(apiName: String) {
        let n = apiName.lowercased().replacingOccurrences(of: "-", with: " ").trimmingCharacters(in: .whitespaces)
        let table: [(String, MuscleGroup)] = [
            ("lower back", .lowerBack), ("lumbar", .lowerBack), ("erector", .lowerBack),
            ("shoulder", .shoulders), ("delt", .shoulders),
            ("latissimus", .lats), ("lats", .lats),
            ("trap", .traps), ("rhomboid", .traps), ("middle back", .traps), ("upper back", .traps),
            ("chest", .chest), ("pec", .chest),
            ("bicep", .biceps), ("tricep", .triceps), ("forearm", .forearms),
            ("oblique", .obliques), ("abdom", .abs), ("abs", .abs), ("core", .abs),
            ("quad", .quads), ("hamstring", .hamstrings), ("glute", .glutes),
            ("calf", .calves), ("calves", .calves), ("back", .lats)
        ]
        if n == "lat" { self = .lats; return }
        for (key, group) in table where n.contains(key) { self = group; return }
        return nil
    }
}
