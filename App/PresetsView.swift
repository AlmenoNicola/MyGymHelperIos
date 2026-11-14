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

/// "3 allenamenti a settimana" (la difficoltà è nella pastiglia DifficultyBadge); con 1 "1 allenamento a settimana".
func planFacts(_ plan: PresetPlan) -> String {
    if plan.daysPerWeek == 1 { return NSLocalizedString("presets.perWeek.one", comment: "") }
    return String(format: NSLocalizedString("presets.perWeek %lld", comment: ""), plan.daysPerWeek)
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
                .appType(.caption, weight: .bold).lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(color.opacity(0.18), in: Capsule())
        .overlay(Capsule().stroke(color.opacity(0.6), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

/// Chi ha fatto la scheda: l'utente ("Fatta da te") o l'app ("Creata dall'app"). Le schede pronte non hanno etichetta.
enum PlanOrigin { case user, app }

/// Etichetta dell'origine, stessa forma di DifficultyBadge (capsula, sfondo al 18%, bordo al 60%, padding 10/4):
/// icona piccola + testo grassetto su una riga. Utente: colore accento, icona persona, "Fatta da te";
/// app: colore highlight, icona cursori, "Creata dall'app". Come PlanOriginBadge su Android.
struct PlanOriginBadge: View {
    let origin: PlanOrigin

    var body: some View {
        let color = origin == .user ? Theme.accent : Theme.highlight
        HStack(spacing: 4) {
            Image(systemName: origin == .user ? "person.fill" : "slider.horizontal.3")
                .appFont(.footnote).foregroundStyle(color)
            Text(LocalizedStringKey(origin == .user ? "plans.badge.user" : "plans.badge.app"))
                .appType(.caption, weight: .bold).lineLimit(1)
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(color.opacity(0.18), in: Capsule())
        .overlay(Capsule().stroke(color.opacity(0.6), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

/// Etichette della scheda (origine e difficolta') in fila con spazio 8, a capo se non c'e' spazio.
struct PlanBadges: View {
    let origin: PlanOrigin?
    var level: String? = nil

    var body: some View {
        FlowLayout(spacing: 8) {
            if let origin { PlanOriginBadge(origin: origin) }
            if let level { DifficultyBadge(level: level) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Schede pronte come schermata a se': intestazione e l'elenco di tutte le schede (PlansListSection).
/// Dal 6 novembre 2026 l'elenco e' in fondo alla pagina Allenamento; la schermata resta per chi ci arriva da altre parti.
struct PresetPlansView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ScreenHeader(symbol: "calendar", title: "presets.title", subtitle: "presets.subtitle")
                PlansListSection()
            }
            .padding(20)
        }
        .appScreen()
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Elenco di tutte le schede (in fondo ad Allenamento e nella schermata Schede pronte), nell'ordine:
/// titolo "Scegli la tua scheda di esercizi"; le schede scritte dall'utente (Pro con consenso, "Fatta da te");
/// "Crea la tua scheda" con le schede create e la "Consigliata per te" ("Creata dall'app"); le schede pronte.
/// Come PlansListSection su Android.
struct PlansListSection: View {
    /// Target del tutorial sul titolo dell'elenco (se c'e').
    var titleTarget: String? = nil
    /// Titolo "Scegli la tua scheda di esercizi": nella schermata Schede pronte si', nel riquadro
    /// "Le tue schede" di Allenamento no.
    var showTitle = true
    @Environment(SubscriptionManager.self) private var subscriptions
    private var tier: SubscriptionTier { subscriptions.tier }

    var body: some View {
        VStack(spacing: 16) {
            // Invito alla scelta, sopra l'elenco delle schede
            if showTitle {
                let title = Text("presets.choose").appType(.sectionTitle, weight: .bold, uppercase: true).lineLimit(1).minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let titleTarget { title.tutorialTarget(titleTarget) } else { title }
            }

            // Schede scritte a mano dall'utente, dalla piu' recente (la gestione resta in Esercizi > Schede)
            UserPlanCards()

            // "Crea la tua scheda" (scheda su misura) e le schede gia' create, sopra la scheda del mese
            CustomPlansSection(tier: tier)

            // Scheda del mese nascosta per il momento (HiddenForNow.monthlyPlan)
            if HiddenForNow.monthlyPlan { MonthlyPlanCard(tier: tier) }

            PresetPlanCards(tier: tier)
        }
    }
}

/// Parti nascoste per il momento (9 novembre 2026): il codice resta, per riaccenderle basta rimettere true.
enum HiddenForNow {
    /// Card "Consigliata per te" (scheda del mese) nell'elenco delle schede.
    static let monthlyPlan = false
    /// Riquadro "Consigliati per te" in Allenamento > Aggiungi esercizio.
    static let recommendedExercises = false
}

/// Schede pronte ordinate per allenamenti a settimana crescenti; a parità prima le più facili
/// (principiante, intermedio, esperto), poi l'ordine originale (ordinamento stabile con l'indice).
/// Risultato: Full body in 2, Total body base, Principiante, Corpo libero e stretching, Push/Pull/Legs, Upper/Lower.
func presetsByWeek() -> [PresetPlan] {
    func rank(_ level: String) -> Int { level == "beginner" ? 0 : level == "intermediate" ? 1 : 2 }
    return PresetPlans.all.enumerated().sorted { a, b in
        if a.element.daysPerWeek != b.element.daysPerWeek { return a.element.daysPerWeek < b.element.daysPerWeek }
        if rank(a.element.level) != rank(b.element.level) { return rank(a.element.level) < rank(b.element.level) }
        return a.offset < b.offset
    }.map(\.element)
}

/// Card delle schede scritte a mano dall'utente (TrainingPlanRecord, dalla più recente), solo con il piano che le
/// permette e con il consenso; etichetta "Fatta da te". La gestione (inserisci, elimina) resta in Esercizi > Schede.
struct UserPlanCards: View {
    @Environment(SubscriptionManager.self) private var subscriptions
    @Query(sort: \TrainingPlanRecord.createdAt, order: .reverse) private var records: [TrainingPlanRecord]
    @AppStorage(ConsentStore.grantedAtKey) private var consentAt = 0.0

    /// Le schede dell'utente si vedono solo con il piano che le permette e con il consenso.
    static func visible(tier: SubscriptionTier, consentAt: Double) -> Bool {
        FeatureGate.isAvailable(.uploadTrainingAndNutritionPlans, for: tier) && consentAt > 0
    }

    var body: some View {
        if Self.visible(tier: subscriptions.tier, consentAt: consentAt) {
            ForEach(records) { record in
                NavigationLink { TrainingPlanDetailView(record: record) } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Image(systemName: "doc.text").appFont(.title2).foregroundStyle(Theme.accent)
                            Text(verbatim: record.name).appType(.cardTitle, weight: .bold)
                                .lineLimit(1).minimumScaleFactor(0.7)
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }
                        PlanBadges(origin: .user)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Card "Consigliata per te" (scheda del mese, Pro). Per ora nascosta (HiddenForNow.monthlyPlan).
struct MonthlyPlanCard: View {
    let tier: SubscriptionTier
    @Environment(CatalogStore.self) private var catalog
    @Query(sort: \WorkoutSessionRecord.startedAt) private var sessions: [WorkoutSessionRecord]
    private var monthly: MonthlyPlanStore { MonthlyPlanStore.shared }

    var body: some View {
        let monthlyOn = FeatureGate.isAvailable(.monthlyPlan, for: tier)
        NavigationLink { PresetPlanView(planID: MonthlyPlanner.id) } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "sparkles").foregroundStyle(Theme.highlight).appFont(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("presets.monthly").appType(.cardTitle)
                        if let p = monthly.plan { Text(verbatim: monthTitle(p.summary.monthKey)).appType(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    Image(systemName: monthlyOn ? "chevron.right" : "lock.fill").foregroundStyle(.secondary)
                }
                PlanBadges(origin: .app, level: monthly.plan?.plan.level)
                Text("presets.monthly.summary").appType(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
        }
        .buttonStyle(.plain)
        .disabled(!monthlyOn)
        .task { monthly.refresh(catalog: catalog.all, sessions: sessionSummaries(sessions)) }
    }
}

/// Card delle schede pronte (ordinate con presetsByWeek, solo difficoltà) e, nel Free, la nota col lucchetto.
struct PresetPlanCards: View {
    let tier: SubscriptionTier

    var body: some View {
        ForEach(presetsByWeek()) { plan in
            let available = PresetPlans.isAvailable(plan, for: tier)
            NavigationLink { PresetPlanView(planID: plan.id) } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(LocalizedStringKey(plan.titleKey)).appType(.cardTitle)
                            Text(verbatim: planFacts(plan)).appType(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: available ? "chevron.right" : "lock.fill").foregroundStyle(.secondary)
                    }
                    DifficultyBadge(level: plan.level)
                    Text(LocalizedStringKey(plan.summaryKey)).appType(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard()
            }
            .buttonStyle(.plain)
            .disabled(!available)
        }
        if !FeatureGate.isAvailable(.presetPlans, for: tier) {
            Label("presets.locked", systemImage: "lock.fill").appType(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
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
                        // Schede create e consigliata del mese: "Creata dall'app" + difficolta'; pronte: solo difficolta'
                        PlanBadges(origin: custom != nil || planID == MonthlyPlanner.id ? .app : nil, level: plan.level)
                        if let custom {
                            CustomPlanNotesView(record: custom)
                            CustomPlanActions(record: custom)
                        } else if planID == MonthlyPlanner.id { monthlyNotes } else {
                            Text(LocalizedStringKey(plan.summaryKey)).appType(.secondary).foregroundStyle(.secondary)
                        }
                        if plan.id == PresetPlans.freeID {
                            Text("presets.freeNote").appType(.caption).foregroundStyle(.secondary)
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
            Text(LocalizedStringKey(day.titleKey)).appType(.cardTitle)
            ForEach(Array(day.items.enumerated()), id: \.offset) { _, item in
                let ex = catalog.exercise(id: item.exerciseID)
                HStack(spacing: 10) {
                    if let ex { MuscleThumbnail(exercise: ex, height: 48) }
                    VStack(alignment: .leading, spacing: 2) {
                        if let ex { Text(verbatim: ex.name).appType(.secondary, weight: .semibold) }
                        else { Text("workout.missingExercise").appType(.secondary, weight: .semibold) }
                        Text(verbatim: item.parameters.summaryText).appType(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let ex {
                        NavigationLink { ExerciseDetailView(exercise: ex) } label: { Text("presets.how").appType(.caption) }
                    }
                }
            }
            Button {
                let current = store.list(AppSettings.shared.currentListID)
                if !canSaveLists, let current, !current.items.isEmpty { pending = day } else { use(day, plan: plan) }
            } label: {
                Label("presets.use", systemImage: "play.fill").appType(.cardTitle).frame(maxWidth: .infinity).padding(.vertical, 4)
            }
            .buttonStyle(.glassProminent).appType(.button).tint(Theme.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    @ViewBuilder
    private var monthlyNotes: some View {
        let m = monthlyPlan
        let s = m.summary
        Text(verbatim: monthTitle(s.monthKey)).appType(.secondary, weight: .bold)
        if let note = m.aiNote { Text(verbatim: note).appType(.secondary) }
        if s.trainingDays == 0 {
            Text("monthly.noHistory").appType(.secondary).foregroundStyle(.secondary)
        } else {
            Text("monthly.basedOn \(s.trainingDays)").appType(.secondary).foregroundStyle(.secondary)
            if !s.undertrained.isEmpty {
                Text("monthly.undertrained \(s.undertrained.map(\.title).joined(separator: ", "))").appType(.secondary).foregroundStyle(.secondary)
            }
            Text("monthly.mix \(s.keptExercises) \(s.newExercises)").appType(.secondary).foregroundStyle(.secondary)
        }
        if consentAt == 0 { Text("monthly.consent").appType(.caption).foregroundStyle(.secondary) }
        if monthly.isWorking { ProgressView().controlSize(.small) }
        Text(LocalizedStringKey(m.aiNote != nil ? "monthly.ai" : "monthly.rules")).appType(.caption).foregroundStyle(.secondary)
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
