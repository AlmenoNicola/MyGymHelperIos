import Foundation
import Observation
import MyGymHelperCore

/// Catalogo esercizi: parte dall'elenco incluso nell'app (nostri + Free Exercise DB, funziona subito e offline) e, se configurato,
/// aggiunge gli esercizi del backend (API MuscleWiki, con cache di massimo 30 giorni).
/// Il backend si attiva con `MyGymHelperSupabaseURL` (funzione `catalog`) oppure con `MyGymHelperBackendURL`.
@Observable
@MainActor
final class CatalogStore {
    private(set) var all: [CatalogExercise] = []
    private(set) var isRefreshing = false
    private(set) var remoteError = false
    @ObservationIgnored private var didRefresh = false

    let language = Locale.current.language.languageCode?.identifier ?? "en"

    init() { loadSeed() }

    private func loadSeed() {
        guard let url = Bundle.main.url(forResource: "exercises_seed", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let seed = try? SeedCatalog.decode(data, language: language) else { return }
        all = seed
    }

    func visible(for tier: SubscriptionTier) -> [CatalogExercise] { CatalogAccess.visible(all, tier: tier) }

    func exercise(id: String) -> CatalogExercise? { all.first { $0.id == id } }

    /// Scarica (o legge dalla cache) gli esercizi del backend e li aggiunge a quelli inclusi.
    /// `fallbackBase`: indirizzo delle Edge Functions Supabase, usato se `MyGymHelperBackendURL` e' vuoto.
    /// Si scarica al massimo una volta per avvio (la cache su disco vale fino a 30 giorni).
    func refreshRemote(fallbackBase: URL? = nil, authToken: @escaping @Sendable () async -> String?) async {
        let configured = (Bundle.main.object(forInfoDictionaryKey: "MyGymHelperBackendURL") as? String ?? "")
            .trimmingCharacters(in: .whitespaces)
        // Catalogo MuscleWiki spento (AppFlags): resta solo l'elenco incluso nell'app.
        guard AppFlags.muscleWikiCatalog, !isRefreshing, !didRefresh,
              let base = configured.isEmpty ? fallbackBase : URL(string: configured) else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let cache = URL.cachesDirectory.appending(path: "catalog", directoryHint: .isDirectory)
        let provider = CachedExerciseProvider(base: BackendExerciseProvider(baseURL: base, authToken: authToken), directory: cache)
        do {
            let remote = try await provider.exercises(language: language).compactMap { $0.toCatalog() }
            all = all.filter { !$0.id.hasPrefix("mw-") } + remote   // tutto l'elenco incluso nell'app + backend
            remoteError = false
            didRefresh = true
        } catch {
            remoteError = true   // senza rete (o cache scaduta) resta l'elenco incluso nell'app
        }
    }
}
