import SwiftUI
import MyGymHelperCore

// Distretti muscolari coinvolti (per elenco e per esercizio) ed elenchi in cima alla scheda Esercizi.
// Uguale su Android (6 novembre 2026). Le regole sono nel Core (MuscleDistricts in WorkoutLists.swift).

/// Stato aperto/chiuso dei riquadri e degli elenchi, solo in memoria: resta finché l'app è aperta, all'avvio tutto chiuso.
@Observable
@MainActor
final class DistrictsUIState {
    static let shared = DistrictsUIState()
    /// Chiavi dei riquadri "distretti" aperti.
    var open: Set<String> = []
    /// Chiavi degli elenchi aperti in cima a Esercizi ("preset:<zona>" / "list:<id>").
    var openLists: Set<String> = []
    /// Esercizi mostrati per elenco (a pagine da CatalogFilter.pageSize).
    var shown: [String: Int] = [:]
    private init() {}

    func toggle(_ key: String) { if open.contains(key) { open.remove(key) } else { open.insert(key) } }
    func toggleList(_ key: String) { if openLists.contains(key) { openLists.remove(key) } else { openLists.insert(key) } }
    func shownCount(_ key: String) -> Int { shown[key] ?? CatalogFilter.pageSize }
}

/// Riquadro richiudibile "Distretti muscolari": per ogni zona del corpo coinvolta i muscoli principali e secondari
/// e la figura (solo i lati utili). Chiuso all'inizio; niente se gli esercizi non hanno muscoli. Il tocco apre o
/// chiude solo il riquadro.
struct MuscleDistrictsBox: View {
    let title: LocalizedStringKey
    let exercises: [CatalogExercise]
    let stateKey: String
    private var state: DistrictsUIState { DistrictsUIState.shared }

    var body: some View {
        let districts = MuscleDistricts.of(exercises)
        if !districts.isEmpty {
            let isOpen = state.open.contains(stateKey)
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    withAnimation(.snappy) { state.toggle(stateKey) }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "figure.arms.open").appFont(.footnote).foregroundStyle(Theme.accent)
                        Text(title).appFont(.subheadline, weight: .semibold).lineLimit(1).minimumScaleFactor(0.6)
                        Spacer(minLength: 4)
                        Image(systemName: isOpen ? "chevron.up" : "chevron.down").appFont(.footnote).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text(isOpen ? "ex.collapse" : "ex.expand"))

                if isOpen {
                    ForEach(districts, id: \.region) { d in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: d.region.title).appFont(.subheadline, weight: .bold)
                            if !d.primary.isEmpty {
                                legend(AnyShapeStyle(Theme.accentGradient), "ex.primaryMuscles", d.primary)
                            }
                            if !d.secondary.isEmpty {
                                legend(AnyShapeStyle(Theme.accent.opacity(0.45)), "ex.secondaryMuscles", d.secondary)
                            }
                        }
                    }
                    let primary = Set(districts.flatMap(\.primary))
                    let secondary = Set(districts.flatMap(\.secondary))
                    HStack(spacing: 24) {
                        ForEach(figureSides(primary.union(secondary)), id: \.self) { front in
                            VStack(spacing: 4) {
                                MuscleFigure(front: front, highlight: { m in
                                    primary.contains(m) ? .primary : (secondary.contains(m) ? .secondary : .idle)
                                })
                                .frame(height: 160)
                                Text(front ? BodySide.front.titleKey : BodySide.back.titleKey).appFont(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
        }
    }

    /// Riga della legenda, come in ExerciseMusclesCard: pallino colorato, "Principali: …" / "Secondari: …".
    private func legend(_ style: AnyShapeStyle, _ title: LocalizedStringKey, _ muscles: [MuscleGroup]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(style).frame(width: 10, height: 10)
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(title)
                Text(verbatim: ": ")
            }
            .appFont(.footnote, weight: .bold)
            Text(verbatim: muscles.map(\.title).joined(separator: ", ")).appFont(.footnote).foregroundStyle(.secondary)
        }
    }
}

/// In cima alla scheda Esercizi: tutti gli elenchi, pronti (per zona del corpo) e dell'utente, chiusi all'avvio.
/// Toccando un elenco si apre con i distretti muscolari dell'elenco e i suoi esercizi (a pagine da 40).
struct ExerciseListsSection: View {
    let pool: [CatalogExercise]
    let showMine: Bool
    @Environment(CatalogStore.self) private var catalog
    private var store: WorkoutListStore { WorkoutListStore.shared }
    private var state: DistrictsUIState { DistrictsUIState.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("ex.lists").appFont(.title3, weight: .bold)
                Text("ex.listsHint").appFont(.footnote).foregroundStyle(.secondary)
            }
            // Elenchi pronti: stessa regola della schermata Elenchi (muscolo principale nella zona)
            let presets: [(BodyRegion, [CatalogExercise])] = BodyRegion.allCases.compactMap { region in
                let items = pool.filter { ex in ex.primary.contains { $0.region == region } }
                return items.isEmpty ? nil : (region, items)
            }
            if !presets.isEmpty {
                Text("lists.presets").appFont(.headline)
                ForEach(presets, id: \.0) { region, items in
                    listCard(key: "preset:\(region.rawValue)", title: region.title,
                             entries: items.map { ($0, nil) })
                }
            }
            // I miei elenchi: solo con il piano che li permette e il consenso (l'invito ai piani resta in Elenchi)
            if showMine && !store.lists.isEmpty {
                Text("lists.mine").appFont(.headline).padding(.top, 4)
                ForEach(store.lists.sorted { $0.createdAt < $1.createdAt }) { list in
                    listCard(key: "list:\(list.id.uuidString)", title: list.name,
                             entries: list.items.compactMap { item in catalog.exercise(id: item.exerciseID).map { ($0, item.parameters) } })
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { store.reload() }
    }

    /// Card di un elenco: chiusa, con nome e numero di esercizi; aperta, i distretti e gli esercizi.
    private func listCard(key: String, title: String, entries: [(CatalogExercise, WorkoutParameters?)]) -> some View {
        let isOpen = state.openLists.contains(key)
        let shown = state.shownCount(key)
        return VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.snappy) { state.toggleList(key) }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "list.bullet").foregroundStyle(Theme.accent)
                    Text(verbatim: title).appFont(.headline).lineLimit(1).minimumScaleFactor(0.6)
                    Spacer(minLength: 4)
                    Text(verbatim: "\(entries.count)").appFont(.subheadline).foregroundStyle(.secondary)
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down").appFont(.footnote).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text(isOpen ? "ex.collapse" : "ex.expand"))

            if isOpen {
                if entries.isEmpty {
                    Text("ex.listEmpty").appFont(.footnote).foregroundStyle(.secondary)
                } else {
                    MuscleDistrictsBox(title: "ex.listDistricts", exercises: entries.map(\.0), stateKey: "\(key)/all")
                    ForEach(Array(entries.prefix(shown).enumerated()), id: \.offset) { index, entry in
                        exerciseRow(entry.0, parameters: entry.1, stateKey: "\(key)/\(index)")
                    }
                    ShowMoreButton(remaining: entries.count - shown) {
                        state.shown[key] = shown + CatalogFilter.pageSize
                    }
                }
            }
        }
        .glassCard(padding: 14)
    }

    /// Esercizio dell'elenco: tocco sulla riga = scheda dell'esercizio; sotto i distretti dell'esercizio.
    private func exerciseRow(_ ex: CatalogExercise, parameters: WorkoutParameters?, stateKey: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            NavigationLink { ExerciseDetailView(exercise: ex) } label: {
                HStack(spacing: 10) {
                    MuscleThumbnail(exercise: ex, height: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: ex.name).appFont(.subheadline, weight: .bold).lineLimit(1).minimumScaleFactor(0.6)
                        // Solo nei miei elenchi: serie, ripetizioni, peso e pausa
                        if let parameters {
                            Text(verbatim: parameters.summaryText).appFont(.caption).foregroundStyle(.secondary)
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").appFont(.footnote).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            MuscleDistrictsBox(title: "ex.districts", exercises: [ex], stateKey: stateKey)
        }
        .padding(10)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 20))
    }
}
