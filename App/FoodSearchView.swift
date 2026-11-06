import SwiftUI
import MyGymHelperCore

/// Ricerca alimenti su Open Food Facts (valori per 100 g). Si inviano solo le parole cercate, nessun dato sanitario.
/// Dati ODbL: l'attribuzione resta sempre visibile.
struct FoodSearchView: View {
    @State private var query = ""
    @State private var results: [FoodProduct] = []
    @State private var state: SearchState = .idle
    @State private var task: Task<Void, Never>?

    enum SearchState { case idle, loading, done, failed }

    private let language = Locale.current.language.languageCode?.identifier ?? "en"

    /// Open Food Facts chiede uno User-Agent con nome dell'app, versione e un contatto.
    /// Il contatto si imposta in Info.plist con la chiave `MyGymHelperContactEmail`.
    static var userAgent: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "1.0"
        let contact = info["MyGymHelperContactEmail"] as? String ?? AppContact.email
        return "MyGymHelper/\(version) (iOS; \(contact))"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ScreenHeader(symbol: "magnifyingglass", title: "food.search.title", subtitle: "food.search.subtitle")

                HStack {
                    TextField("food.search.placeholder", text: $query)
                        .textFieldStyle(.plain)
                        .submitLabel(.search)
                        .onSubmit(search)
                    Button(action: search) { Image(systemName: "arrow.right.circle.fill").appFont(.title2) }
                        .disabled(query.trimmingCharacters(in: .whitespaces).count < 2)
                }
                .padding(14)
                .glassEffect(.regular, in: .capsule)

                switch state {
                case .idle:
                    EmptyView()
                case .loading:
                    ProgressView().padding()
                case .failed:
                    Label("food.search.error", systemImage: "wifi.exclamationmark")
                        .appFont(.callout).foregroundStyle(.secondary).glassCard(padding: 16)
                case .done:
                    if results.isEmpty {
                        Text("food.search.none").foregroundStyle(.secondary).glassCard(padding: 16)
                    }
                    ForEach(results) { product in
                        FoodRow(product: product)
                    }
                }

                VStack(spacing: 4) {
                    Text("food.attribution").appFont(.caption2).foregroundStyle(.secondary)
                    Link(destination: URL(string: "https://world.openfoodfacts.org")!) {
                        Text(verbatim: "openfoodfacts.org").appFont(.caption2, weight: .bold)
                    }
                }
                .padding(.top, 8)
            }
            .padding(20)
        }
        .appScreen()
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { task?.cancel() }
    }

    private func search() {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard text.count >= 2 else { return }
        task?.cancel()
        state = .loading
        let client = FoodFactsClient(userAgent: Self.userAgent)
        let lang = language
        task = Task {
            do {
                let found = try await client.search(text, language: lang)
                guard !Task.isCancelled else { return }
                results = found
                state = .done
            } catch {
                guard !Task.isCancelled else { return }
                state = .failed
            }
        }
    }
}

private struct FoodRow: View {
    let product: FoodProduct

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: product.name).appFont(.headline)
                    if let brand = product.brand { Text(verbatim: brand).appFont(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                if let kcal = product.kcal100g {
                    Text(verbatim: "\(Int(kcal.rounded())) kcal").appFont(.subheadline, weight: .bold, monospacedDigit: true)
                }
            }
            HStack(spacing: 12) {
                value("nutrition.protein", product.protein100g)
                value("nutrition.carbs", product.carbs100g)
                value("nutrition.fat", product.fat100g)
            }
            Text("food.per100g").appFont(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(padding: 16)
    }

    private func value(_ title: LocalizedStringKey, _ grams: Double?) -> some View {
        HStack(spacing: 4) {
            Text(title).foregroundStyle(.secondary)
            Text(verbatim: grams.map { "\($0.formatted(.number.precision(.fractionLength(0...1)))) g" } ?? "—")
        }
        .appFont(.caption)
    }
}
