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
                .appFont(.caption, weight: .bold).lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(color.opacity(0.18), in: Capsule())
        .overlay(Capsule().stroke(color.opacity(0.6), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

/// Schede pronte: "Crea la tua scheda" con le schede create (Pro), la consigliata del mese (Pro), la base total body
/// (per tutti) e le altre schede (Pro). Come PresetPlansScreen su Android.
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
                Text("presets.choose").appFont(.title3, weight: .bold).lineLimit(1).minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // "Crea la tua scheda" (scheda su misura) e le schede gia' create, sopra la scheda del mese
                CustomPlansSection(tier: tier)

                let monthlyOn = FeatureGate.isAvailable(.monthlyPlan, for: tier)
                NavigationLink { PresetPlanView(planID: MonthlyPlanner.id) } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "sparkles").foregroundStyle(Theme.highlight).appFont(.title3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("presets.monthly").appFont(.headline)
                                if let p = monthly.plan { Text(verbatim: monthTitle(p.summary.monthKey)).appFont(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            Image(systemName: monthlyOn ? "chevron.right" : "lock.fill").foregroundStyle(.secondary)
                        }
                        if let p = monthly.plan { DifficultyBadge(level: p.plan.level) }
                        Text("presets.monthly.summary").appFont(.footnote).foregroundStyle(.secondary)
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
                                    Text(LocalizedStringKey(plan.titleKey)).appFont(.headline)
                                    Text(verbatim: planFacts(plan)).appFont(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: available ? "chevron.right" : "lock.fill").foregroundStyle(.secondary)
                            }
                            DifficultyBadge(level: plan.level)
                            Text(LocalizedStringKey(plan.summaryKey)).appFont(.footnote).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassCard()
                    }
                    .buttonStyle(.plain)
                    .disabled(!available)
                }

                if !FeatureGate.isAvailable(.presetPlans, for: tier) {
                    Label("presets.locked", systemImage: "lock.fill").appFont(.footnote).foregroundStyle(.secondary)
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
/// Anche le schede create con "Crea la tua scheda" (id "custom:<id>"): nome, note e pulsanti della scheda.
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
    /// Scheda creata dall'utente, se l'id e' "custom:<id>".
    private var custom: CustomPlanRecord? { CustomPlanStore.shared.record(planID: planID) }
    private var plan: PresetPlan? {
        if planID == MonthlyPlanner.id { return monthlyPlan.plan }
        if planID.hasPrefix(CustomPlanGenerator.idPrefix) { return custom?.plan }
        return PresetPlans.plan(planID)
    }
    private var canSaveLists: Bool { FeatureGate.isAvailable(.savedExerciseLists, for: subscriptions.tier) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let plan {
                    if let custom {
                        // Scheda creata: il titolo e' il nome scelto dall'utente (testo non da tradurre)
                        ScreenHeader(symbol: "slider.horizontal.3", title: LocalizedStringKey("\(custom.name)"),
                                     subtitle: LocalizedStringKey("\(customFacts(custom))"))
                    } else {
                        ScreenHeader(symbol: planID == MonthlyPlanner.id ? "sparkles" : "calendar",
                                     title: LocalizedStringKey(plan.titleKey), subtitle: LocalizedStringKey(planFacts(plan)))
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        DifficultyBadge(level: plan.level)
                        if let custom {
                            CustomPlanNotesView(record: custom)
                            CustomPlanActions(record: custom)
                        } else if planID == MonthlyPlanner.id { monthlyNotes } else {
                            Text(LocalizedStringKey(plan.summaryKey)).appFont(.subheadline).foregroundStyle(.secondary)
                        }
                        if plan.id == PresetPlans.freeID {
                            Text("presets.freeNote").appFont(.caption).foregroundStyle(.secondary)
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
            Text(LocalizedStringKey(day.titleKey)).appFont(.headline)
            ForEach(Array(day.items.enumerated()), id: \.offset) { _, item in
                let ex = catalog.exercise(id: item.exerciseID)
                HStack(spacing: 10) {
                    if let ex { MuscleThumbnail(exercise: ex, height: 48) }
                    VStack(alignment: .leading, spacing: 2) {
                        if let ex { Text(verbatim: ex.name).appFont(.subheadline, weight: .semibold) }
                        else { Text("workout.missingExercise").appFont(.subheadline, weight: .semibold) }
                        Text(verbatim: item.parameters.summaryText).appFont(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let ex {
                        NavigationLink { ExerciseDetailView(exercise: ex) } label: { Text("presets.how").appFont(.footnote) }
                    }
                }
            }
            Button {
                let current = store.list(AppSettings.shared.currentListID)
                if !canSaveLists, let current, !current.items.isEmpty { pending = day } else { use(day, plan: plan) }
            } label: {
                Label("presets.use", systemImage: "play.fill").appFont(.headline).frame(maxWidth: .infinity).padding(.vertical, 4)
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
        Text(verbatim: monthTitle(s.monthKey)).appFont(.subheadline, weight: .bold)
        if let note = m.aiNote { Text(verbatim: note).appFont(.subheadline) }
        if s.trainingDays == 0 {
            Text("monthly.noHistory").appFont(.subheadline).foregroundStyle(.secondary)
        } else {
            Text("monthly.basedOn \(s.trainingDays)").appFont(.subheadline).foregroundStyle(.secondary)
            if !s.undertrained.isEmpty {
                Text("monthly.undertrained \(s.undertrained.map(\.title).joined(separator: ", "))").appFont(.subheadline).foregroundStyle(.secondary)
            }
            Text("monthly.mix \(s.keptExercises) \(s.newExercises)").appFont(.subheadline).foregroundStyle(.secondary)
        }
        if consentAt == 0 { Text("monthly.consent").appFont(.caption).foregroundStyle(.secondary) }
        if monthly.isWorking { ProgressView().controlSize(.small) }
        Text(LocalizedStringKey(m.aiNote != nil ? "monthly.ai" : "monthly.rules")).appFont(.caption).foregroundStyle(.secondary)
    }

    private func use(_ day: PresetDay, plan: PresetPlan) {
        let items = PresetPlans.items(for: day, sessions: sessionSummaries(sessions))
        if canSaveLists {
            // Pro: un elenco per allenamento ("Upper / Lower · Parte alta A"), riusato se c'e' gia'
            // Schede create: "Nome scheda · Giorno"
            let title = custom?.name ?? NSLocalizedString(plan.titleKey, comment: "")
            let name = title + " · " + NSLocalizedString(day.titleKey, comment: "")
            AppSettings.shared.setCurrentList(store.upsertList(name: name, items: items))
        } else {
            // Free: un solo elenco, quello attuale
            store.replaceItems(items, in: ItemEditorView.ensureCurrentList())
        }
        AppSettings.shared.showWorkoutRoot()
    }
}
