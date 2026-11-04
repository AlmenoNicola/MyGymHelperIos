import SwiftUI
import SwiftData
import MyGymHelperCore

/// Riepilogo di fine allenamento. Pro: consigli a regole fisse e consiglio adattivo per la prossima volta
/// (calcolato con lo storico dell'esercizio, la sessione appena finita e la scheda caricata).
struct SessionSummaryView: View {
    let controller: SessionController
    let tier: SubscriptionTier
    let saved: Bool
    /// Testo del pulsante finale ("Fine" o "Torna all'elenco").
    var doneKey: LocalizedStringKey = "session.done"
    /// Esercizio successivo dell'elenco da proporre (nil = nessuno).
    var nextName: String? = nil
    var onNext: (() -> Void)? = nil
    var onDone: () -> Void

    @Query(sort: \WorkoutSessionRecord.startedAt) private var sessions: [WorkoutSessionRecord]
    @Query(sort: \TrainingPlanRecord.createdAt) private var plans: [TrainingPlanRecord]
    @Environment(CatalogStore.self) private var catalog
    /// Domanda della revisione: nil = da decidere, true = risposto, false = "Non ora".
    @State private var reviewAnswered: Bool?
    @State private var reviewDue: Bool?
    private var review: PlanReviewStore { PlanReviewStore.shared }

    private var records: [SetRecord] { controller.records }

    private var current: WorkoutParameters { controller.parameters }

    /// Regole fisse: con l'esercizio si usano multiarticolare/gambe reali; senza, si deduce dall'arto scelto.
    private var fixed: CoachingResult? {
        guard FeatureGate.isAvailable(.fixedCoaching, for: tier), !records.isEmpty else { return nil }
        let compound = controller.exercise?.isCompound ?? false
        let lower = controller.exercise?.isLowerBody ?? controller.position.isLowerBody
        return FixedCoaching.advise(sets: records.map(\.outcome), isCompound: compound, isLowerBody: lower)
    }

    private var adaptive: AdaptiveAdvice? {
        guard FeatureGate.isAvailable(.adaptiveCoaching, for: tier), !records.isEmpty,
              let exercise = controller.exercise else { return nil }
        // La sessione appena salvata e' gia' nello storico: si esclude e si aggiunge quella in memoria.
        let past = sessions.filter { abs($0.startedAt.timeIntervalSince(controller.startedAt)) > 1 }
        let history = CoachingService.samples(for: exercise.id, from: past) + [controller.sample()]
        return AdaptiveCoach.advise(history: history, isCompound: exercise.isCompound,
                                    defaultSets: controller.totalSets, defaultReps: controller.targets[0].reps,
                                    plan: CoachingService.planTarget(for: exercise, plans: plans))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                ScreenHeader(symbol: "flag.checkered", title: "summary.title", subtitle: "summary.subtitle")

                VStack(spacing: 14) {
                    if let exercise = controller.exercise {
                        HStack {
                            Text(verbatim: exercise.name).font(.title3.bold())
                            Spacer()
                            if !controller.isVaried && controller.weightKg > 0 { Text(verbatim: controller.weightKg.kgText).foregroundStyle(.secondary) }
                        }
                    }
                    ForEach(records, id: \.number) { r in
                        HStack {
                            Text("session.setResult \(r.number) \(r.doneReps) \(r.plannedReps)").font(.headline)
                            Spacer()
                            // Serie diverse: il peso di ogni serie.
                            if controller.isVaried, controller.target(r.number).weightKg > 0 {
                                Text(verbatim: controller.target(r.number).weightKg.kgText).font(.subheadline).foregroundStyle(.secondary)
                            }
                            if r.stoppedEarly {
                                Text("session.stoppedTag").font(.caption.bold())
                                    .padding(.horizontal, 10).padding(.vertical, 4)
                                    .background(.red.opacity(0.35), in: Capsule())
                            } else {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                            }
                        }
                    }
                    if records.isEmpty { Text("summary.empty").foregroundStyle(.secondary) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard()

                if let adaptive {
                    AdviceCard(title: "advice.nextTime", reasons: adaptive.reasonKeys,
                               parameters: adaptive.parameters(from: current), before: current)
                } else if let fixed {
                    AdviceCard(title: "advice.title", reasons: [fixed.reasonKey], parameters: fixed.applied(to: current),
                               details: fixed.advice.map { $0.textKey(bodyweight: current.maxWeightKg == 0) })
                } else if !records.isEmpty {
                    LockedNote(key: "advice.locked").glassCard(padding: 16)
                }

                if FeatureGate.isAvailable(.adaptiveCoaching, for: tier), controller.exercise == nil, !records.isEmpty {
                    Label("advice.chooseExercise", systemImage: "info.circle")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                // Revisione della scheda ogni due settimane (Pro): la domanda compare a fine allenamento.
                if saved, !records.isEmpty, let exercise = controller.exercise,
                   FeatureGate.isAvailable(.adaptiveCoaching, for: tier) {
                    if reviewAnswered == true {
                        PlanReviewAnsweredNote(working: review.working, hasProposal: review.state.pending != nil)
                    } else if reviewAnswered == nil, reviewDue == true, let active = PlanReviewStore.activePlan(plans) {
                        PlanReviewQuestionCard(planName: active.record.name, onAnswer: { f in
                            reviewAnswered = true
                            review.start(f, plans: plans, sessions: sessions, catalog: catalog.all)
                        }, onLater: { reviewAnswered = false })
                    }
                    Color.clear.frame(height: 0).onAppear {
                        if reviewDue == nil {
                            reviewDue = review.shouldAsk(plans: plans, sessions: sessions, catalog: catalog.all, exerciseID: exercise.id)
                        }
                    }
                }

                if !saved {
                    Label("session.notSaved", systemImage: "info.circle")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                if let nextName, let onNext {
                    // Si propone il prossimo esercizio: parte solo quando l'utente lo avvia dalla schermata "Pronto".
                    Button(action: onNext) {
                        Label("workout.nextExercise \(nextName)", systemImage: "forward.fill")
                            .font(.headline).lineLimit(1).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent).tint(Theme.accent)
                    Button(action: onDone) {
                        Text(doneKey).lineLimit(1).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                } else {
                    Button(action: onDone) {
                        Text(doneKey).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent).tint(Theme.accent)
                }
            }
        }
    }
}
