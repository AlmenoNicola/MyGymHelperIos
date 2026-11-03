import SwiftUI
import SwiftData
import MyGymHelperCore

/// Storico ridotto per le schede (serie fatte, o pianificate se non registrate). Come su Android.
@MainActor
func sessionSummaries(_ sessions: [WorkoutSessionRecord]) -> [SessionSummary] {
    sessions.map { s in
        SessionSummary(exerciseID: s.exerciseID, startedAt: s.startedAt,
                       sets: s.sets.isEmpty ? s.plannedSets : s.sets.count, weightKg: s.weightKg)
    }
}

/// "Ottobre 2026" dal mese "2026-10".
func monthTitle(_ key: String) -> String {
    let parser = DateFormatter(); parser.locale = Locale(identifier: "en_US_POSIX"); parser.dateFormat = "yyyy-MM"
    guard let date = parser.date(from: key) else { return key }
    let out = DateFormatter(); out.setLocalizedDateFormatFromTemplate("LLLLyyyy")
    return out.string(from: date).capitalized(with: Locale.current)
}

/// "3 allenamenti a settimana" (la difficoltà è nella pastiglia DifficultyBadge).
func planFacts(_ plan: PresetPlan) -> String {
    String(format: NSLocalizedString("presets.perWeek %lld", comment: ""), plan.daysPerWeek)
}

/// Difficoltà della scheda ben in evidenza: pastiglia colorata con tacche e "Difficoltà: Principiante".
/// Principiante verde (1 tacca), intermedio arancione (2), esperto rosso (3). Come DifficultyBadge su Android.
struct DifficultyBadge: View {
    let level: String

    private var color: Color {
        switch level {
        case "beginner": return Theme.done
        case "intermediate": return .orange
        default: return .red
        }
    }
    private var steps: Int { level == "beginner" ? 1 : level == "intermediate" ? 2 : 3 }

    var body: some View {
        let name = Bundle.main.localizedString(forKey: "level.\(level)", value: level, table: nil)
        HStack(spacing: 6) {
            // Tacche crescenti tipo "segnale": piene fino al livello della scheda
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(1...3, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(i <= steps ? color : color.opacity(0.25))
                        .frame(width: 4, height: CGFloat(4 + i * 3))
                }
            }
            Text(verbatim: String(format: NSLocalizedString("presets.difficulty %@", comment: ""), name))
                .font(.caption.bold()).lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(color.opacity(0.18), in: Capsule())
        .overlay(Capsule().stroke(color.opacity(0.6), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

/// Schede pronte: la consigliata del mese (Mid e Full), la base total body (per tutti) e le altre schede (Mid e Full).
/// Come PresetPlansScreen su Android.
struct PresetPlansView: View {
    @Environment(SubscriptionManager.self) private var subscriptions
    @Environment(CatalogStore.self) private var catalog
    @Query(sort: \WorkoutSessionRecord.startedAt) private var sessions: [WorkoutSessionRecord]
    private var monthly: MonthlyPlanStore { MonthlyPlanStore.shared }
    private var tier: SubscriptionTier { subscriptions.tier }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ScreenHeader(symbol: "calendar", title: "presets.title", subtitle: "presets.subtitle")
                // Invito alla scelta, sopra l'elenco delle schede
                Text("presets.choose").font(.title3.bold()).lineLimit(1).minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .leading)

                let monthlyOn = FeatureGate.isAvailable(.monthlyPlan, for: tier)
                NavigationLink { PresetPlanView(planID: MonthlyPlanner.id) } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "sparkles").foregroundStyle(Theme.highlight).font(.title3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("presets.monthly").font(.headline)
                                if let p = monthly.plan { Text(verbatim: monthTitle(p.summary.monthKey)).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            Image(systemName: monthlyOn ? "chevron.right" : "lock.fill").foregroundStyle(.secondary)
                        }
                        if let p = monthly.plan { DifficultyBadge(level: p.plan.level) }
                        Text("presets.monthly.summary").font(.footnote).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()
                }
                .buttonStyle(.plain)
                .disabled(!monthlyOn)

                ForEach(PresetPlans.all) { plan in
                    let available = PresetPlans.isAvailable(plan, for: tier)
                    NavigationLink { PresetPlanView(planID: plan.id) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(LocalizedStringKey(plan.titleKey)).font(.headline)
                                    Text(verbatim: planFacts(plan)).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: available ? "chevron.right" : "lock.fill").foregroundStyle(.secondary)
                            }
                            DifficultyBadge(level: plan.level)
                            Text(LocalizedStringKey(plan.summaryKey)).font(.footnote).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassCard()
                    }
                    .buttonStyle(.plain)
                    .disabled(!available)
                }

                if !FeatureGate.isAvailable(.presetPlans, for: tier) {
                    Label("presets.locked", systemImage: "lock.fill").font(.footnote).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(20)
        }
        .appScreen()
        .navigationBarTitleDisplayMode(.inline)
        .task { monthly.refresh(catalog: catalog.all, sessions: sessionSummaries(sessions)) }
    }
}

/// Una scheda: descrizione e allenamenti; "Usa questo allenamento" lo mette come elenco attuale.
/// Come PresetPlanScreen su Android.
struct PresetPlanView: View {
    let planID: String
    @Environment(SubscriptionManager.self) private var subscriptions
    @Environment(CatalogStore.self) private var catalog
    @Query(sort: \WorkoutSessionRecord.startedAt) private var sessions: [WorkoutSessionRecord]
    @AppStorage(ConsentStore.grantedAtKey) private var consentAt = 0.0
    @State private var pending: PresetDay?
    private var monthly: MonthlyPlanStore { MonthlyPlanStore.shared }
    private var store: WorkoutListStore { WorkoutListStore.shared }

    private var monthlyPlan: MonthlyPlan {
        monthly.plan ?? MonthlyPlanner.generate(catalog: catalog.all, sessions: sessionSummaries(sessions))
    }
    private var plan: PresetPlan? { planID == MonthlyPlanner.id ? monthlyPlan.plan : PresetPlans.plan(planID) }
    private var canSaveLists: Bool { FeatureGate.isAvailable(.savedExerciseLists, for: subscriptions.tier) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let plan {
                    ScreenHeader(symbol: planID == MonthlyPlanner.id ? "sparkles" : "calendar",
                                 title: LocalizedStringKey(plan.titleKey), subtitle: LocalizedStringKey(planFacts(plan)))
                    VStack(alignment: .leading, spacing: 8) {
                        DifficultyBadge(level: plan.level)
                        if planID == MonthlyPlanner.id { monthlyNotes } else {
                            Text(LocalizedStringKey(plan.summaryKey)).font(.subheadline).foregroundStyle(.secondary)
                        }
                        if plan.id == PresetPlans.freeID {
                            Text("presets.freeNote").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()

                    ForEach(Array(plan.days.enumerated()), id: \.offset) { _, day in
                        dayCard(day, plan: plan)
                    }
                } else {
                    Text("ex.none").foregroundStyle(.secondary).glassCard(padding: 16)
                }
            }
            .padding(20)
        }
        .appScreen()
        .navigationBarTitleDisplayMode(.inline)
        .task { if planID == MonthlyPlanner.id { monthly.refresh(catalog: catalog.all, sessions: sessionSummaries(sessions)) } }
        .alert("presets.replaceTitle", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
            Button("presets.replace", role: .destructive) {
                if let day = pending, let plan { use(day, plan: plan) }
                pending = nil
            }
            Button("info.cancel", role: .cancel) { pending = nil }
        } message: {
            Text("presets.replaceBody")
        }
    }

    private func dayCard(_ day: PresetDay, plan: PresetPlan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedStringKey(day.titleKey)).font(.headline)
            ForEach(Array(day.items.enumerated()), id: \.offset) { _, item in
                let ex = catalog.exercise(id: item.exerciseID)
                HStack(spacing: 10) {
                    if let ex { MuscleThumbnail(exercise: ex, height: 48) }
                    VStack(alignment: .leading, spacing: 2) {
                        if let ex { Text(verbatim: ex.name).font(.subheadline.weight(.semibold)) }
                        else { Text("workout.missingExercise").font(.subheadline.weight(.semibold)) }
                        Text(verbatim: item.parameters.summaryText).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let ex {
                        NavigationLink { ExerciseDetailView(exercise: ex) } label: { Text("presets.how").font(.footnote) }
                    }
                }
            }
            Button {
                let current = store.list(AppSettings.shared.currentListID)
                if !canSaveLists, let current, !current.items.isEmpty { pending = day } else { use(day, plan: plan) }
            } label: {
                Label("presets.use", systemImage: "play.fill").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 4)
            }
            .buttonStyle(.glassProminent).tint(Theme.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    @ViewBuilder
    private var monthlyNotes: some View {
        let m = monthlyPlan
        let s = m.summary
        Text(verbatim: monthTitle(s.monthKey)).font(.subheadline.bold())
        if let note = m.aiNote { Text(verbatim: note).font(.subheadline) }
        if s.trainingDays == 0 {
            Text("monthly.noHistory").font(.subheadline).foregroundStyle(.secondary)
        } else {
            Text("monthly.basedOn \(s.trainingDays)").font(.subheadline).foregroundStyle(.secondary)
            if !s.undertrained.isEmpty {
                Text("monthly.undertrained \(s.undertrained.map(\.title).joined(separator: ", "))").font(.subheadline).foregroundStyle(.secondary)
            }
            Text("monthly.mix \(s.keptExercises) \(s.newExercises)").font(.subheadline).foregroundStyle(.secondary)
        }
        if consentAt == 0 { Text("monthly.consent").font(.caption).foregroundStyle(.secondary) }
        if monthly.isWorking { ProgressView().controlSize(.small) }
        Text(LocalizedStringKey(m.aiNote != nil ? "monthly.ai" : "monthly.rules")).font(.caption).foregroundStyle(.secondary)
    }

    private func use(_ day: PresetDay, plan: PresetPlan) {
        let items = PresetPlans.items(for: day, sessions: sessionSummaries(sessions))
        if canSaveLists {
            // Mid e Full: un elenco per allenamento ("Upper / Lower · Parte alta A"), riusato se c'e' gia'
            let name = NSLocalizedString(plan.titleKey, comment: "") + " · " + NSLocalizedString(day.titleKey, comment: "")
            AppSettings.shared.setCurrentList(store.upsertList(name: name, items: items))
        } else {
            // Free: un solo elenco, quello attuale
            store.replaceItems(items, in: ItemEditorView.ensureCurrentList())
        }
        AppSettings.shared.showWorkoutRoot()
    }
}
