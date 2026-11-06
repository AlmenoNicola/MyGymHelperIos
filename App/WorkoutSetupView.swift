import SwiftUI
import SwiftData
import MyGymHelperCore

/// Scheda Allenamento: in alto l'elenco attuale (esercizi con serie, ripetizioni, peso e pausa; quelli svolti in verde,
/// "Reset" in fondo), sotto la scelta degli esercizi: mappa del corpo e lista di tutti gli esercizi, filtrata dai muscoli
/// scelti; in evidenza quelli che li allenano tutti. Toccando un esercizio si impostano i parametri e si aggiunge all'elenco.
struct WorkoutSetupView: View {
    @Environment(SubscriptionManager.self) private var subscriptions
    @Environment(CatalogStore.self) private var catalog
    @AppStorage(ConsentStore.grantedAtKey) private var consentAt = 0.0
    @State private var showLists = false
    /// Riquadro degli esercizi caricati: chiuso all'apertura, resta com'è mentre si entra in un esercizio e si torna.
    @State private var itemsExpanded = false
    @State private var toDelete: WorkoutItem?
    @State private var sessionTarget: SessionTarget?
    @State private var editTarget: EditTarget?

    private var tier: SubscriptionTier { subscriptions.tier }
    private var store: WorkoutListStore { WorkoutListStore.shared }
    private var list: WorkoutListStore.WorkoutList? { store.list(AppSettings.shared.currentListID) }
    private var canChooseLists: Bool { FeatureGate.isAvailable(.savedExerciseLists, for: tier) }
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ScreenHeader(symbol: "bolt.heart.fill", title: "setup.title", subtitle: "setup.subtitle")
                    .tutorialTarget(TutorialTarget.tabWorkout)
                listCard.tutorialTarget(TutorialTarget.workoutList)
                NavigationLink { AddExerciseView() } label: {
                    Label("workout.addExercise", systemImage: "plus.circle.fill").appFont(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent).tint(Theme.accent)
                .tutorialTarget(TutorialTarget.workoutAdd)
                // Schede pronte: card grande come le funzioni principali (prima era un pulsante piccolo)
                NavigationLink { PresetPlansView() } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "calendar").appFont(.title2, weight: .semibold).foregroundStyle(.white)
                            .frame(width: 48, height: 48).background(Theme.accentGradient, in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text("presets.open").appFont(.title3, weight: .bold)
                            Text("presets.subtitle").appFont(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").appFont(.footnote).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard(padding: 18)
                }
                .buttonStyle(.plain)
                .tutorialTarget(TutorialTarget.workoutPresets)
                Button { sessionTarget = SessionTarget(exercise: nil, parameters: WorkoutItem.defaultParameters) } label: {
                    Label("workout.freeCount", systemImage: "timer").lineLimit(1).frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .tutorialTarget(TutorialTarget.workoutFree)
                NavigationLink { HistoryView() } label: {
                    Label("history.open", systemImage: "clock.arrow.circlepath").lineLimit(1).frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .tutorialTarget(TutorialTarget.workoutHistory)
            }
            .padding(20)
        }
        .tutorialScrollFollow()
        .appScreen()
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $sessionTarget) { WorkoutSessionView(target: $0) }
        .navigationDestination(item: $editTarget) { ItemEditorView(exercise: $0.exercise, listID: $0.listID, item: $0.item) }
        .sheet(isPresented: $showLists) { ListPickerSheet() }
        .alert("workout.deleteItem", isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } })) {
            Button("history.delete", role: .destructive) {
                if let item = toDelete, let list { store.deleteItem(item.id, from: list.id) }
                toDelete = nil
            }
            Button("info.cancel", role: .cancel) { toDelete = nil }
        } message: {
            Text(verbatim: toDelete.flatMap { catalog.exercise(id: $0.exerciseID)?.name } ?? "")
        }
        .onAppear { store.reload() }
    }

    // MARK: - Elenco

    /// Intestazione del riquadro degli esercizi caricati: quanti sono, quanti svolti, freccia apri/chiudi.
    private func loadedItemsHeader(_ list: WorkoutListStore.WorkoutList) -> some View {
        let total = list.items.count
        let done = list.items.filter(\.done).count
        return Button {
            withAnimation(.snappy) { itemsExpanded.toggle() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "list.bullet").appFont(.headline).foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("workout.itemsLoaded \(total)").appFont(.subheadline, weight: .bold).lineLimit(1).minimumScaleFactor(0.75)
                    Text("workout.itemsDone \(done) \(total)").appFont(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.down").appFont(.footnote, weight: .semibold).foregroundStyle(.secondary)
                    .rotationEffect(.degrees(itemsExpanded ? 180 : 0))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(padding: 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text(itemsExpanded ? "workout.itemsHide" : "workout.itemsShow"))
    }

    private var listCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("workout.list").appFont(.caption).foregroundStyle(.secondary)
                    if let list { Text(verbatim: list.name).appFont(.title3, weight: .bold).lineLimit(1) }
                    else { Text("workout.todayList").appFont(.title3, weight: .bold).lineLimit(1) }
                }
                Spacer()
                if canChooseLists {
                    Button("workout.changeList") { showLists = true }.buttonStyle(.glass).lineLimit(1)
                }
            }
            if list?.items.isEmpty ?? true {
                Text("workout.emptyList").appFont(.subheadline).foregroundStyle(.secondary)
            }
            if let list {
                // Esercizi già caricati: riquadro chiuso; toccandolo si apre (e si richiude) l'elenco.
                if !list.items.isEmpty {
                    loadedItemsHeader(list)
                    if itemsExpanded {
                        ForEach(Array(list.items.enumerated()), id: \.element.id) { index, item in
                            itemRow(number: index + 1, item: item, list: list)
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                if !list.items.isEmpty {
                    Toggle("workout.autoNext", isOn: Binding(get: { list.autoNext }, set: { store.setAutoNext($0, for: list.id) }))
                        .tint(Theme.accent)
                    if let next = WorkoutListLogic.nextPending(list.items) {
                        Button { start(next, in: list) } label: {
                            Label("workout.startNext \(catalog.exercise(id: next.exerciseID)?.name ?? "")", systemImage: "play.fill")
                                .appFont(.headline).lineLimit(1).frame(maxWidth: .infinity).padding(.vertical, 6)
                        }
                        .buttonStyle(.glassProminent).tint(Theme.accent)
                    } else {
                        Text("workout.allDone").appFont(.subheadline).foregroundStyle(.secondary)
                    }
                    Button { store.reset(list.id) } label: {
                        Label("workout.reset", systemImage: "arrow.counterclockwise").lineLimit(1).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .disabled(!list.items.contains { $0.done })
                    // Totale delle calorie (stima) degli esercizi fatti, dopo Reset
                    if list.items.contains(where: \.done) {
                        CaloriesTotalCard(items: list.items)
                    }
                }
            }
            if consentAt == 0 {
                Text("workout.notSavedNote").appFont(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    /// Riga dell'elenco: tocco = avvia; matita = modifica; cestino = elimina. Svolto = verde.
    private func itemRow(number: Int, item: WorkoutItem, list: WorkoutListStore.WorkoutList) -> some View {
        let exercise = catalog.exercise(id: item.exerciseID)
        return HStack(spacing: 10) {
            Button { start(item, in: list) } label: {
                HStack(spacing: 10) {
                    if item.done {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.done).appFont(.title3)
                    } else {
                        Text(verbatim: "\(number)").appFont(.headline).foregroundStyle(Theme.accent).frame(width: 22)
                    }
                    if let exercise { MuscleThumbnail(exercise: exercise, height: 42) }
                    VStack(alignment: .leading, spacing: 2) {
                        if let exercise { Text(verbatim: exercise.name).appFont(.subheadline, weight: .bold).lineLimit(1) }
                        else { Text("workout.missingExercise").appFont(.subheadline, weight: .bold).lineLimit(1) }
                        Text(verbatim: item.parameters.summaryText).appFont(.caption).foregroundStyle(.secondary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        // Esercizio fatto: calorie bruciate (stima) nelle serie fatte
                        let kcal = CalorieEstimator.display(item.kcal)
                        if item.done && kcal > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "flame.fill").font(.system(size: 14 * AppTextScale))
                                Text("calories.item \(kcal)").font(.system(size: 12 * AppTextScale, weight: .semibold))
                            }
                            .foregroundStyle(Theme.done)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(exercise == nil)
            if let exercise {
                Button { editTarget = EditTarget(exercise: exercise, listID: list.id, item: item) } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .accessibilityLabel(Text("workout.editItem"))
            }
            Button { toDelete = item } label: { Image(systemName: "trash") }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .accessibilityLabel(Text("workout.deleteItem"))
        }
        .tintedCard(item.done ? Theme.done : nil, padding: 14)
    }

    private func start(_ item: WorkoutItem, in list: WorkoutListStore.WorkoutList) {
        guard let exercise = catalog.exercise(id: item.exerciseID) else { return }
        sessionTarget = SessionTarget(exercise: exercise, parameters: item.parameters, listID: list.id, itemID: item.id)
    }
}

/// Aggiunta di esercizi all'elenco attuale: mappa del corpo, tipo, ricerca e lista di tutti gli esercizi, filtrata dai
/// muscoli scelti; in evidenza quelli che li allenano tutti. Toccando un esercizio si impostano i parametri e si
/// aggiunge all'elenco; poi si torna qui per aggiungerne altri. Come AddExerciseScreen su Android.
///
/// Con `alternativeFor` diventa la scelta dell'esercizio alternativo ("Fai esercizio alternativo", come
/// AlternativeExerciseScreen su Android): muscoli principali dell'originale già scelti, l'originale non compare e
/// toccando un esercizio si chiama `onPick` (la sessione lo usa solo questa volta; l'elenco non cambia).
struct AddExerciseView: View {
    @Environment(SubscriptionManager.self) private var subscriptions
    @Environment(CatalogStore.self) private var catalog
    var alternativeFor: CatalogExercise? = nil
    var onPick: ((CatalogExercise) -> Void)? = nil
    @State private var editTarget: EditTarget?
    // Restano tornando dall'editor (la vista resta nella pila di navigazione).
    @State private var side: BodySide = .front
    @State private var selected: Set<MuscleGroup> = []
    @State private var query = ""
    @State private var kind: ExerciseKind?
    /// Filtro "Corpo libero": solo esercizi senza attrezzi.
    @State private var bodyweight = false
    /// Esercizi mostrati (a pagine da 40: il catalogo ne ha quasi 900). Cambiando un filtro si riparte da 40.
    @State private var shown = CatalogFilter.pageSize

    init() {}

    /// Scelta dell'esercizio alternativo a `original`, solo per la sessione in corso.
    init(alternativeFor original: CatalogExercise, onPick: @escaping (CatalogExercise) -> Void) {
        alternativeFor = original
        self.onPick = onPick
        _selected = State(initialValue: WorkoutListLogic.alternativeMuscles(original))
        _side = State(initialValue: WorkoutListLogic.alternativeOnBack(original) ? .back : .front)
    }

    private var tier: SubscriptionTier { subscriptions.tier }
    private var store: WorkoutListStore { WorkoutListStore.shared }
    private var list: WorkoutListStore.WorkoutList? { store.list(AppSettings.shared.currentListID) }
    private var results: [CatalogExercise] {
        let pool = CatalogFilter.byKind(CatalogFilter.bodyweightOnly(equipmentFiltered(catalog.visible(for: tier), tier: tier),
                                                                    on: bodyweight), kind: kind)
        if let alternativeFor {
            return WorkoutListLogic.alternatives(pool, original: alternativeFor, selected: selected, query: query)
        }
        return WorkoutListLogic.browse(pool, selected: selected, query: query)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let alternativeFor {
                    ScreenHeader(symbol: "arrow.left.arrow.right.circle.fill", title: "alternative.title",
                                 subtitle: "alternative.subtitle \(alternativeFor.name)")
                    Text("alternative.note").appFont(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ScreenHeader(symbol: "plus.circle.fill", title: "workout.addTitle",
                                 subtitle: LocalizedStringKey(list?.name ?? String(localized: "workout.todayList")))
                }
                browser
            }
            .padding(20)
        }
        .appScreen()
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $editTarget) { ItemEditorView(exercise: $0.exercise, listID: $0.listID, item: $0.item) }
    }

    // MARK: - Scelta degli esercizi

    @ViewBuilder
    private var browser: some View {
        if AppFlags.homeEquipment { HomeEquipmentCard(tier: tier) }

        VStack(spacing: 14) {
            // Primo filtro: ricerca per nome (anche per "Fai esercizio alternativo")
            ExerciseSearchField(query: $query)
            Picker("", selection: $side) {
                ForEach(BodySide.allCases) { Text($0.titleKey).tag($0) }
            }
            .pickerStyle(.segmented)
            BodyMapView(side: side, selected: $selected).frame(height: 300)
            // Muscoli scelti (anche quelli dell'altro lato) con la X per toglierne uno
            SelectedMuscleChips(selected: $selected)
            KindChips(kind: $kind)
            BodyweightChip(on: $bodyweight)
            EquipmentFilterChip(tier: tier)
            Text(LocalizedStringKey(selected.isEmpty ? "workout.allExercises" : "workout.filtered"))
                .appFont(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            if !selected.isEmpty {
                Button("ex.clear") { selected.removeAll() }.appFont(.footnote)
            }
        }
        .glassCard()
        .onChange(of: selected) { _, _ in shown = CatalogFilter.pageSize }
        .onChange(of: query) { _, _ in shown = CatalogFilter.pageSize }
        .onChange(of: kind) { _, _ in shown = CatalogFilter.pageSize }
        .onChange(of: bodyweight) { _, _ in shown = CatalogFilter.pageSize }
        .onChange(of: AppSettings.shared.equipmentFilter) { _, _ in shown = CatalogFilter.pageSize }
        .onChange(of: AppSettings.shared.ownedEquipment) { _, _ in shown = CatalogFilter.pageSize }

        let items = results
        if selected.count >= 2 && items.contains(where: { WorkoutListLogic.coversAll($0, selected: selected) }) {
            Label("workout.highlightNote", systemImage: "star.fill")
                .appFont(.caption).foregroundStyle(Theme.highlight).frame(maxWidth: .infinity, alignment: .leading)
        }
        if !FeatureGate.isAvailable(.catalogFull, for: tier) {
            Label("ex.freeLimit", systemImage: "lock.fill")
                .appFont(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
        }
        if items.isEmpty {
            Text("ex.none").foregroundStyle(.secondary).glassCard(padding: 16)
        }
        ForEach(items.prefix(shown)) { ex in
            Button {
                if let onPick { onPick(ex) } else { editTarget = EditTarget(exercise: ex, listID: nil, item: nil) }
            } label: {
                BrowseRow(exercise: ex, full: WorkoutListLogic.coversAll(ex, selected: selected),
                          inList: onPick == nil && (list?.exerciseIDs.contains(ex.id) ?? false),
                          symbol: onPick == nil ? "plus.circle.fill" : "arrow.left.arrow.right.circle.fill")
            }
            .buttonStyle(.plain)
        }
        ShowMoreButton(remaining: items.count - shown) { shown += CatalogFilter.pageSize }
    }

}

/// Esercizio da aprire nell'editor: nuovo (item nil) o da modificare.
struct EditTarget: Hashable, Identifiable {
    let id = UUID()
    let exercise: CatalogExercise
    let listID: UUID?
    let item: WorkoutItem?

    static func == (a: EditTarget, b: EditTarget) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Esercizio da aggiungere. `full` = allena tutti i muscoli scelti (in evidenza, ambra tenue);
/// `inList` = già nell'elenco attuale (spunta e sfondo con l'accento del tema).
private struct BrowseRow: View {
    let exercise: CatalogExercise
    let full: Bool
    let inList: Bool
    /// Icona a destra: "+" per aggiungere, frecce per l'esercizio alternativo.
    var symbol = "plus.circle.fill"

    var body: some View {
        HStack(spacing: 10) {
            MuscleThumbnail(exercise: exercise, height: 46)   // muscoli coinvolti in miniatura
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: exercise.name).appFont(.subheadline, weight: .semibold)
                if full {
                    Label("workout.allMuscles", systemImage: "star.fill")
                        .appFont(.caption, weight: .semibold).foregroundStyle(Theme.highlight)
                }
            }
            Spacer()
            if inList {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                    .accessibilityLabel(Text("workout.inList"))
            }
            Image(systemName: symbol).appFont(.title2).foregroundStyle(Theme.accentSoft)
        }
        // Già in elenco: spunta e sfondo tinto con l'accento del tema scelto (ha la precedenza sull'ambra di `full`).
        .tintedCard(inList ? Theme.accent : (full ? Theme.highlight : nil), padding: 10)
    }
}

/// Scelta dell'elenco attuale tra quelli salvati, o creazione di uno nuovo (Pro).
private struct ListPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(ConsentStore.grantedAtKey) private var consentAt = 0.0
    @State private var newName = ""
    private var store: WorkoutListStore { WorkoutListStore.shared }

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: 14) {
                    Text("workout.changeList").appFont(.title3, weight: .bold)
                    ForEach(store.lists) { list in
                        Button {
                            AppSettings.shared.setCurrentList(list.id)
                            dismiss()
                        } label: {
                            HStack {
                                Text(verbatim: list.name).appFont(.headline)
                                Spacer()
                                Text(verbatim: "\(list.items.filter(\.done).count)/\(list.items.count)").foregroundStyle(.secondary)
                            }
                            .tintedCard(list.id == AppSettings.shared.currentListID ? Theme.accent : nil, padding: 16)
                        }
                        .buttonStyle(.plain)
                    }
                    HStack {
                        TextField("lists.newName", text: $newName).textFieldStyle(.plain)
                        Button("lists.create") {
                            let name = newName.trimmingCharacters(in: .whitespaces)
                            let id = store.createList(name: name.isEmpty ? String(localized: "workout.todayList") : name)
                            AppSettings.shared.setCurrentList(id)
                            dismiss()
                        }
                        .buttonStyle(.glassProminent).tint(Theme.accent)
                    }
                    .glassCard(padding: 16)
                    if consentAt == 0 {
                        Text("workout.notSavedNote").appFont(.caption).foregroundStyle(.secondary)
                    }
                    Button("info.cancel") { dismiss() }.buttonStyle(.glass)
                }
                .padding(24)
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Parametri di un esercizio dell'elenco

/// Serie, ripetizioni, pausa e peso di un esercizio, con i consigli (piano Pro: adattivi).
/// item nil = esercizio nuovo (precompilato da scheda e ultima sessione), da aggiungere all'elenco attuale
/// (o ad "Allenamento odierno" se non ce n'e' uno); altrimenti si modifica quello esistente.
struct ItemEditorView: View {
    let exercise: CatalogExercise
    let listID: UUID?
    let item: WorkoutItem?
    /// Aperto da un'altra scheda (Esercizi, schede caricate): dopo l'aggiunta si passa alla scheda Allenamento.
    var switchToWorkout = false
    @Environment(SubscriptionManager.self) private var subscriptions
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \WorkoutSessionRecord.startedAt) private var sessions: [WorkoutSessionRecord]
    @Query(sort: \TrainingPlanRecord.createdAt) private var plans: [TrainingPlanRecord]
    /// Serie dell'esercizio (ripetizioni e peso di ognuna). Free: si usano tutte uguali alla prima.
    /// Righe: ogni riga = N serie uguali (le serie uguali consecutive stanno in una riga sola).
    @State private var groups: [SetGroup] = SetGroup.group(WorkoutItem.defaultParameters.targets)
    @State private var restSeconds = WorkoutItem.defaultParameters.restSeconds
    @State private var prefilled = false
    /// Revisione della scheda ogni due settimane (proposta in attesa e copia per tornare indietro).
    private var review: PlanReviewStore { PlanReviewStore.shared }

    init(exercise: CatalogExercise, listID: UUID? = nil, item: WorkoutItem? = nil, switchToWorkout: Bool = false) {
        self.exercise = exercise
        self.listID = listID
        self.item = item
        self.switchToWorkout = switchToWorkout
    }

    private var tier: SubscriptionTier { subscriptions.tier }
    /// Serie diverse (Pro): una riga per serie. Free: serie tutte uguali.
    private var canVary: Bool { FeatureGate.isAvailable(.variedSets, for: tier) }
    private var shown: [SetTarget] {
        let list = rows
        return canVary ? list : Array(repeating: list[0], count: list.count)
    }
    private var current: WorkoutParameters { WorkoutParameters.of(shown, restSeconds: restSeconds) }
    /// Serie di tutte le righe, nell'ordine.
    private var rows: [SetTarget] {
        let r = SetGroup.expand(groups)
        return r.isEmpty ? WorkoutItem.defaultParameters.targets : r
    }

    private var adaptive: AdaptiveAdvice? {
        guard FeatureGate.isAvailable(.adaptiveCoaching, for: tier) else { return nil }
        return CoachingService.adaptive(exercise: exercise, sessions: sessions, plans: plans,
                                        defaultSets: current.sets, defaultReps: current.reps)
    }

    // Serie uguali (Free): serie, ripetizioni e peso valgono per tutte le serie (una riga sola).
    private var setsBinding: Binding<Int> {
        Binding(get: { shown.count }, set: { n in groups = [SetGroup(count: max(1, n), reps: shown[0].reps, weightKg: shown[0].weightKg)] })
    }
    private var repsBinding: Binding<Int> {
        Binding(get: { shown[0].reps }, set: { r in groups = [SetGroup(count: shown.count, reps: r, weightKg: shown[0].weightKg)] })
    }
    private var weightBinding: Binding<Double> {
        Binding(get: { shown[0].weightKg }, set: { w in groups = [SetGroup(count: shown.count, reps: shown[0].reps, weightKg: w)] })
    }

    // Serie diverse: numero di serie, ripetizioni e peso della riga `i` (indice controllato: le righe si possono eliminare).
    private func countBinding(_ i: Int) -> Binding<Int> {
        Binding(get: { i < groups.count ? groups[i].count : 1 }, set: { if i < groups.count { groups[i].count = $0 } })
    }
    private func repsBinding(_ i: Int) -> Binding<Int> {
        Binding(get: { i < groups.count ? groups[i].reps : 1 }, set: { if i < groups.count { groups[i].reps = $0 } })
    }
    private func weightBinding(_ i: Int) -> Binding<Double> {
        Binding(get: { i < groups.count ? groups[i].weightKg : 0 }, set: { if i < groups.count { groups[i].weightKg = $0 } })
    }

    /// Numero della prima serie della riga `i` (1 = prima serie dell'esercizio).
    private func firstSet(of i: Int) -> Int { groups.prefix(i).reduce(1) { $0 + $1.count } }

    /// "Serie 1–3" o "Serie 4".
    private func rowTitle(_ i: Int) -> String {
        let from = firstSet(of: i), count = i < groups.count ? groups[i].count : 1
        return count > 1 ? String(localized: "sets.range \(from) \(from + count - 1)") : String(localized: "sets.number \(from)")
    }

    private var fixed: CoachingResult? {
        guard FeatureGate.isAvailable(.fixedCoaching, for: tier),
              !FeatureGate.isAvailable(.adaptiveCoaching, for: tier) else { return nil }
        return CoachingService.fixed(exercise: exercise, sessions: sessions)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                HStack(spacing: 14) {
                    Image(systemName: "dumbbell.fill").foregroundStyle(Theme.accent).frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: exercise.name).appFont(.headline)
                        Text(verbatim: exercise.primary.map(\.title).joined(separator: ", ")).appFont(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !exercise.steps.isEmpty {
                        NavigationLink { ExerciseDetailView(exercise: exercise) } label: { Text("ex.how").lineLimit(1) }
                            .buttonStyle(.glass)
                    }
                }
                .glassCard(padding: 16)

                if !exercise.images.isEmpty { ExercisePhotosCard(exercise: exercise) }

                adviceSection

                if canVary {
                    variedSetsCard
                } else {
                    VStack(spacing: 18) {
                        CounterRow(title: "counter.sets", value: setsBinding, range: WorkoutParameters.setsRange)
                        Divider().overlay(Color.primary.opacity(0.15))
                        CounterRow(title: "counter.reps", value: repsBinding, range: WorkoutParameters.repsRange)
                        Divider().overlay(Color.primary.opacity(0.15))
                        CounterRow(title: "counter.rest", value: $restSeconds, range: WorkoutParameters.restRange, step: 15)
                        Divider().overlay(Color.primary.opacity(0.15))
                        WeightRow(title: "setup.weight", value: weightBinding)
                        // Piano Free: le serie diverse sono del Pro.
                        LockedNote(key: "sets.locked")
                    }
                    .glassCard()
                }

                Button(action: save) {
                    Label(LocalizedStringKey(item == nil ? "workout.addItem" : "workout.saveItem"), systemImage: item == nil ? "plus" : "checkmark")
                        .appFont(.title3, weight: .bold).lineLimit(1).frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.accent)
            }
            .padding(20)
        }
        .appScreen()
        .navigationTitle(Text(verbatim: exercise.name))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: prefill)
    }

    /// Una riga per gruppo di serie uguali (numero di serie, ripetizioni e peso, cestino se le righe sono piu' di una).
    /// "Aggiungi serie" aggiunge una riga con una serie (stesse ripetizioni e peso dell'ultima). Al massimo 10 serie in
    /// tutto; la pausa e' unica.
    private var variedSetsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("sets.title").appFont(.headline)
            Text("sets.hint").appFont(.caption).foregroundStyle(.secondary)
            VStack(spacing: 12) {
                ForEach(0..<groups.count, id: \.self) { i in
                    let title = rowTitle(i)
                    // Serie possibili in questa riga: quelle che ha piu' quelle che mancano a 10 in tutto.
                    let maxCount = max(1, countBinding(i).wrappedValue + WorkoutParameters.setsRange.upperBound - rows.count)
                    VStack(spacing: 10) {
                        HStack {
                            Text(verbatim: title).appFont(.subheadline, weight: .bold).foregroundStyle(Theme.accent)
                            Spacer()
                            if groups.count > 1 {
                                Button { withAnimation(.snappy) { _ = groups.remove(at: i) } } label: {
                                    Image(systemName: "trash").foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Text("sets.removeRow \(title)"))
                            }
                        }
                        CounterRow(title: "counter.sets", value: countBinding(i), range: 1...maxCount)
                        CounterRow(title: "counter.reps", value: repsBinding(i), range: WorkoutParameters.repsRange)
                        WeightRow(title: "setup.weight", value: weightBinding(i))
                    }
                    .padding(12)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 18))
                }
            }
            .id(groups.count)      // dopo un'eliminazione le righe ripartono dai valori giusti
            if rows.count < WorkoutParameters.setsRange.upperBound {
                Button { withAnimation(.snappy) { if let last = groups.last { groups.append(SetGroup(count: 1, reps: last.reps, weightKg: last.weightKg)) } } } label: {
                    Label("sets.add", systemImage: "plus").lineLimit(1).frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
            }
            Divider().overlay(Color.primary.opacity(0.15))
            CounterRow(title: "counter.rest", value: $restSeconds, range: WorkoutParameters.restRange, step: 15)
        }
        .glassCard()
    }

    @ViewBuilder
    private var adviceSection: some View {
        // Revisione della scheda ogni due settimane (Pro): la proposta per questo esercizio va in "Consiglio per oggi".
        if adaptive != nil, let pending = review.pending(in: plans), let change = pending.change(for: exercise.id) {
            PlanReviewAdviceCard(review: pending, change: change, working: review.working, onApply: {
                if review.apply(pending, plans: plans) { apply(change.afterParameters) }
            }, onDiscard: { review.discard() })
        } else if let adaptive {
            // Serie diverse: stessa variazione su ogni serie, mantenendo lo schema.
            let proposed = adaptive.parameters(from: current)
            AdviceCard(title: "advice.adaptiveTitle", reasons: adaptive.reasonKeys, parameters: proposed, before: current) { apply(proposed) }
        } else if let fixed {
            AdviceCard(title: "advice.title", reasons: [fixed.reasonKey], parameters: fixed.applied(to: current),
                       details: fixed.advice.map { $0.textKey(bodyweight: current.maxWeightKg == 0) }) {
                apply(fixed.applied(to: current))
            }
        } else if FeatureGate.isAvailable(.fixedCoaching, for: tier) {
            Label("advice.noHistory", systemImage: "sparkles")
                .appFont(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
        } else {
            LockedNote(key: "advice.locked")
        }
        // Scheda aggiornata con "Applica": si puo' tornare alla versione precedente.
        if adaptive != nil, let b = review.backup(in: plans), b.exerciseIDs.contains(exercise.id) {
            PlanReviewUndoCard(appliedAt: b.appliedAt) {
                // Valori di prima di questo esercizio dell'elenco (se c'era), poi si ripristina tutto.
                let old = item.flatMap { i in listID.flatMap { b.listItems[$0] }?.first { $0.id == i.id } }
                review.restore(plans: plans)
                if let old { apply(old.parameters) }
            }
        }
    }

    private func apply(_ p: WorkoutParameters) {
        withAnimation(.snappy) {
            groups = SetGroup.group(p.targets); restSeconds = p.restSeconds
        }
    }

    /// Valori iniziali: quelli dell'esercizio da modificare; per uno nuovo, dalla scheda e dall'ultima sessione
    /// (anche con le serie diverse).
    private func prefill() {
        guard !prefilled else { return }
        prefilled = true
        if let item { groups = SetGroup.group(item.parameters.targets); restSeconds = item.restSeconds; return }
        var p = WorkoutItem.defaultParameters
        if let t = CoachingService.planTarget(for: exercise, plans: plans) {
            p = t.perSet.isEmpty
                ? WorkoutParameters(sets: t.sets ?? p.sets, reps: t.repsMin ?? p.reps, restSeconds: t.restSeconds ?? p.restSeconds,
                                    weightKg: t.weightKg ?? p.weightKg)
                : .of(t.perSet, restSeconds: t.restSeconds ?? p.restSeconds)
        }
        // Scheda aggiornata con la revisione dopo l'ultima sessione: valgono i valori della scheda.
        if let last = sessions.last(where: { $0.exerciseID == exercise.id }),
           !PlanReviewer.prefersPlan(review.state, exerciseID: exercise.id, lastSessionAt: last.startedAt) {
            let rest = last.restSeconds > 0 ? last.restSeconds : p.restSeconds
            p = last.isVaried
                ? .of(last.plannedTargets, restSeconds: rest)
                : WorkoutParameters(sets: last.plannedSets > 0 ? last.plannedSets : p.sets,
                                    reps: last.plannedReps > 0 ? last.plannedReps : p.reps,
                                    restSeconds: rest, weightKg: last.weightKg)
        }
        let c = p.clamped()
        groups = SetGroup.group(c.targets); restSeconds = c.restSeconds
    }

    private func save() {
        let store = WorkoutListStore.shared
        let p = current.clamped()
        if let item, let listID {
            store.updateItem(item.with(p), in: listID)
        } else {
            store.addItem(WorkoutItem(exerciseID: exercise.id).with(p), to: Self.ensureCurrentList())
            AddedNotice.shared.show(exercise.name)     // avviso "aggiunto all'elenco"
        }
        dismiss()
        if switchToWorkout { AppSettings.shared.selectedTab = .workout }
    }

    /// Id dell'elenco in cui aggiungere: quello scelto, se esiste ancora; altrimenti ne crea uno nuovo
    /// ("Allenamento odierno") che diventa quello attuale.
    @MainActor
    static func ensureCurrentList() -> UUID {
        let store = WorkoutListStore.shared
        store.reload()
        if let list = store.list(AppSettings.shared.currentListID) { return list.id }
        let id = store.createList(name: String(localized: "workout.todayList"))
        AppSettings.shared.setCurrentList(id)
        return id
    }
}

extension WorkoutParameters {
    /// "3 × 10 · 60 kg · 90 s"; serie diverse: "3 serie: 12/10/8 · 40/45/50 kg · 90 s".
    var summaryText: String {
        if isVaried {
            let t = targets
            let weights = t.allSatisfy { $0.weightKg <= 0 } ? String(localized: "setup.bodyweight")
                : t.map { $0.weightKg.kgText.replacingOccurrences(of: " kg", with: "") }.joined(separator: "/") + " kg"
            let reps = t.map { "\($0.reps)" }.joined(separator: "/")
            return String(localized: "sets.count \(t.count)") + ": \(reps) · \(weights) · \(restSeconds) s"
        }
        let weight = weightKg > 0 ? weightKg.kgText : String(localized: "setup.bodyweight")
        return "\(sets) × \(reps) · \(weight) · \(restSeconds) s"
    }
}

extension View {
    /// Card (vetro nel tema originale) con una tinta (verde = svolto, ambra = in evidenza); nil = card normale.
    func tintedCard(_ color: Color?, padding: CGFloat = 16) -> some View {
        self.themedCard(tint: color, padding: padding)
            .overlay {
                RoundedRectangle(cornerRadius: 28).stroke((color ?? .clear).opacity(0.6), lineWidth: 1)
            }
    }
}


// MARK: - Avviso "Aggiunto all'elenco"

/// Avviso breve mostrato ogni volta che si aggiunge un esercizio all'elenco, da qualunque scheda.
/// Lo disegna `AddedNoticeBanner` (in ContentView, sopra la barra delle schede) e sparisce da solo dopo qualche secondo.
@MainActor @Observable
final class AddedNotice {
    static let shared = AddedNotice()
    /// Nome dell'esercizio appena aggiunto; nil = nessun avviso.
    private(set) var exerciseName: String?
    /// Cresce a ogni avviso: aggiungendo due esercizi di fila il conto alla rovescia riparte.
    private var serial = 0

    func show(_ name: String) {
        serial += 1
        let mine = serial
        withAnimation(.snappy) { exerciseName = name }
        AccessibilityNotification.Announcement(String(localized: "workout.added \(name)")).post()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            if mine == serial { withAnimation(.easeOut) { exerciseName = nil } }
        }
    }
}

/// Pillola dell'avviso, nel colore d'accento del tema scelto.
struct AddedNoticeBanner: View {
    private var notice: AddedNotice { AddedNotice.shared }

    var body: some View {
        if let name = notice.exerciseName {
            Label {
                Text("workout.added \(name)").appFont(.subheadline, weight: .semibold).lineLimit(1).minimumScaleFactor(0.7)
            } icon: {
                Image(systemName: "checkmark.circle.fill")
            }
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, 18).padding(.vertical, 12)
            .background(Theme.accent, in: Capsule())
            .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
            .padding(.horizontal, 16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .accessibilityHidden(true)     // il testo lo legge già l'annuncio di VoiceOver
        }
    }
}
