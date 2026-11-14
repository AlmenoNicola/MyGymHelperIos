import SwiftUI
import MyGymHelperCore

// Distretti muscolari coinvolti (per elenco e per esercizio), usati in Allenamento > "Esercizi caricati".
// Uguale su Android (6 novembre 2026). Le regole sono nel Core (MuscleDistricts in WorkoutLists.swift).
// "Le mie schede" in cima alla scheda Esercizi è stata tolta il 9 novembre 2026.

/// Stato aperto/chiuso dei riquadri, solo in memoria: resta finché l'app è aperta, all'avvio tutto chiuso.
@Observable
@MainActor
final class DistrictsUIState {
    static let shared = DistrictsUIState()
    /// Chiavi dei riquadri "distretti" aperti.
    var open: Set<String> = []
    private init() {}

    func toggle(_ key: String) { if open.contains(key) { open.remove(key) } else { open.insert(key) } }
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
                        Text(title).appType(.secondary, weight: .semibold).lineLimit(1).minimumScaleFactor(0.6)
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
                            Text(verbatim: d.region.title).appType(.secondary, weight: .bold)
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
                                Text(front ? BodySide.front.titleKey : BodySide.back.titleKey).appType(.caption).foregroundStyle(.secondary)
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
            .appType(.caption, weight: .bold)
            Text(verbatim: muscles.map(\.title).joined(separator: ", ")).appType(.caption).foregroundStyle(.secondary)
        }
    }
}
