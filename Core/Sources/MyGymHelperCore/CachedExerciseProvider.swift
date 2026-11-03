import Foundation

/// Mette in cache su disco il catalogo di un altro provider.
/// Per MuscleWiki i metadati (testo) si possono tenere in cache al massimo 30 giorni:
/// oltre questo limite il catalogo va riscaricato. Immagini e video non vanno mai salvati.
public struct CachedExerciseProvider: ExerciseProvider {
    public static let metadataMaxAge: TimeInterval = 30 * 24 * 3600

    private struct Entry: Codable {
        let savedAt: Date
        let exercises: [Exercise]
    }

    private let base: ExerciseProvider
    private let directory: URL
    private let maxAge: TimeInterval

    public init(base: ExerciseProvider, directory: URL, maxAge: TimeInterval = CachedExerciseProvider.metadataMaxAge) {
        self.base = base
        self.directory = directory
        self.maxAge = min(maxAge, CachedExerciseProvider.metadataMaxAge)
    }

    public func exercises(language: String) async throws -> [Exercise] {
        let file = directory.appendingPathComponent("catalog-\(language).json")
        if let data = try? Data(contentsOf: file),
           let entry = try? JSONDecoder().decode(Entry.self, from: data),
           Date().timeIntervalSince(entry.savedAt) < maxAge {
            return entry.exercises
        }
        do {
            let fresh = try await base.exercises(language: language)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if let data = try? JSONEncoder().encode(Entry(savedAt: Date(), exercises: fresh)) {
                try? data.write(to: file, options: .atomic)
            }
            return fresh
        } catch {
            // Senza rete NON si usa un catalogo scaduto (oltre 30 giorni): si propaga l'errore.
            throw error
        }
    }
}

/// Legge il catalogo dal TUO backend (per esempio una funzione Supabase) che parla con MuscleWiki.
/// La chiave API non deve mai stare nell'app. Il backend assembla e tiene in cache il catalogo,
/// cosi' si risparmiano le chiamate del piano MuscleWiki.
public struct BackendExerciseProvider: ExerciseProvider {
    public let baseURL: URL
    public let session: URLSession
    public let authToken: @Sendable () async -> String?

    public init(baseURL: URL, session: URLSession = .shared, authToken: @escaping @Sendable () async -> String? = { nil }) {
        self.baseURL = baseURL; self.session = session; self.authToken = authToken
    }

    public func exercises(language: String) async throws -> [Exercise] {
        var comps = URLComponents(url: baseURL.appendingPathComponent("catalog"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "lang", value: language)]
        var request = URLRequest(url: comps.url!)
        if let token = await authToken() { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode([Exercise].self, from: data)
    }
}
