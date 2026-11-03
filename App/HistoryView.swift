import SwiftUI
import SwiftData
import MyGymHelperCore

/// Storico degli allenamenti salvati sul telefono (solo con il consenso ai dati sulla salute).
struct HistoryView: View {
    @Query(sort: \WorkoutSessionRecord.startedAt, order: .reverse) private var sessions: [WorkoutSessionRecord]
    @Environment(\.modelContext) private var context
    @AppStorage(ConsentStore.grantedAtKey) private var consentAt = 0.0

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ScreenHeader(symbol: "clock.arrow.circlepath", title: "history.title", subtitle: "history.subtitle")
                if consentAt == 0 {
                    Text("history.noConsent").font(.callout).glassCard()
                } else if sessions.isEmpty {
                    Text("history.empty").font(.callout).foregroundStyle(.secondary).glassCard()
                } else {
                    ForEach(sessions) { s in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                if s.exerciseName.isEmpty {
                                    Text(SensorPosition.fromLegacy(s.limb).titleKey).font(.headline)
                                } else {
                                    Text(verbatim: s.exerciseName).font(.headline)
                                }
                                HStack(spacing: 8) {
                                    Text(s.startedAt.formatted(date: .abbreviated, time: .shortened))
                                    // Serie diverse: pesi di ogni serie ("40/45/50 kg").
                                    if s.isVaried, s.maxWeightKg > 0 {
                                        Text(verbatim: "· " + s.doneTargets.map { $0.weightKg.kgText.replacingOccurrences(of: " kg", with: "") }
                                            .joined(separator: "/") + " kg")
                                    } else if s.weightKg > 0 { Text(verbatim: "· \(s.weightKg.kgText)") }
                                }
                                .font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("history.sets \(s.sets.count) \(s.plannedSets)").font(.title3.bold())
                        }
                        .glassCard(padding: 18)
                        .contextMenu {
                            Button("history.delete", role: .destructive) { context.delete(s); try? context.save() }
                        }
                    }
                }
            }
            .padding(20)
        }
        .appScreen()
        .navigationBarTitleDisplayMode(.inline)
    }
}
