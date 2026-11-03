import SwiftUI
import SwiftData
import MyGymHelperCore

/// Catalogo: mappa del corpo (fronte/retro) e blocchi per scegliere i muscoli, consigli (Mid e Full) ed elenco esercizi.
/// Piano Free: un esercizio per tipologia.
struct ExercisesView: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(SubscriptionManager.self) private var subscriptions
    @Environment(AccountService.self) private var account
    @Query(sort: \WorkoutSessionRecord.startedAt) private var sessions: [WorkoutSessionRecord]
    @State private var side: BodySide = .front
    @State private var selected: Set<MuscleGroup> = []
    @State private var query = ""
    @State private var kind: ExerciseKind?
    /// Filtro "Corpo libero": solo esercizi senza attrezzi.
    @State private var bodyweight = false
    /// Quasi 900 esercizi: se ne mostrano 40 alla volta (si riparte da 40 cambiando i filtri).
    @State private var shown = CatalogFilter.pageSize

    private var tier: SubscriptionTier { subscriptions.tier }
    private var pool: [CatalogExercise] { catalog.visible(for: tier) }

    private var filtered: [CatalogExercise] {
        CatalogFilter.byKind(CatalogFilter.bodyweightOnly(equipmentFiltered(pool, tier: tier), on: bodyweight), kind: kind).filter { ex in
            (selected.isEmpty || !Set(ex.primary).isDisjoint(with: selected))
                && (query.isEmpty || ex.name.localizedCaseInsensitiveContains(query))
        }
    }

    private var recommendations: [Recommendation] {
        guard FeatureGate.isAvailable(.fixedCoaching, for: tier) else { return [] }
        return ExerciseRecommender.recommend(from: pool, targets: selected,
                                             history: CoachingService.historyEntries(from: sessions, catalog: catalog.all),
                                             limit: 3)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                ScreenHeader(symbol: "figure.strengthtraining.traditional", title: "ex.title", subtitle: "ex.subtitle")
                    .tutorialTarget(TutorialTarget.tabExercises)

                HStack(spacing: 12) {
                    NavigationLink { ExerciseListsView() } label: {
                        Label("ex.lists", systemImage: "list.bullet.rectangle").lineLimit(1).frame(maxWidth: .infinity)
                    }
                    NavigationLink { TrainingPlansView() } label: {
                        Label("ex.plans", systemImage: "doc.text.magnifyingglass").lineLimit(1).frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.glass)
                .tutorialTarget(TutorialTarget.exercisesLinks)

                if AppFlags.homeEquipment {
                    HomeEquipmentCard(tier: tier)
                        .tutorialTarget(TutorialTarget.exercisesEquipment)
                }

                VStack(spacing: 14) {
                    Picker("", selection: $side) {
                        ForEach(BodySide.allCases) { Text($0.titleKey).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    BodyMapView(side: side, selected: $selected).frame(height: 300)
                    KindChips(kind: $kind)
                    BodyweightChip(on: $bodyweight)
                    EquipmentFilterChip(tier: tier)
                    if !selected.isEmpty {
                        Button("ex.clear") { selected.removeAll() }.font(.footnote)
                    }
                }
                .glassCard()

                if !recommendations.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("ex.recommended").font(.headline)
                        ForEach(recommendations, id: \.exercise.id) { rec in
                            NavigationLink { ExerciseDetailView(exercise: rec.exercise) } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: rec.exercise.name).font(.subheadline.bold())
                                    Text(LocalizedStringKey(rec.reasonKey)).font(.caption).foregroundStyle(Theme.accentSoft)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()
                }

                TextField("ex.search", text: $query)
                    .textFieldStyle(.plain)
                    .padding(14)
                    .glassEffect(.regular, in: .capsule)

                if !FeatureGate.isAvailable(.catalogFull, for: tier) {
                    Label("ex.freeLimit", systemImage: "lock.fill")
                        .font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                }

                if filtered.isEmpty {
                    Text("ex.none").foregroundStyle(.secondary).glassCard(padding: 16)
                }
                let items = filtered
                ForEach(items.prefix(shown)) { ex in
                    NavigationLink { ExerciseDetailView(exercise: ex) } label: { ExerciseRow(exercise: ex) }
                        .buttonStyle(.plain)
                }
                ShowMoreButton(remaining: items.count - shown) { shown += CatalogFilter.pageSize }
            }
            .padding(20)
        }
        .onChange(of: selected) { _, _ in shown = CatalogFilter.pageSize }
        .onChange(of: query) { _, _ in shown = CatalogFilter.pageSize }
        .onChange(of: kind) { _, _ in shown = CatalogFilter.pageSize }
        .onChange(of: bodyweight) { _, _ in shown = CatalogFilter.pageSize }
        .onChange(of: AppSettings.shared.equipmentFilter) { _, _ in shown = CatalogFilter.pageSize }
        .onChange(of: AppSettings.shared.ownedEquipment) { _, _ in shown = CatalogFilter.pageSize }
        .tutorialScrollFollow()
        .appScreen()
        .toolbar(.hidden, for: .navigationBar)
        .task {
            let account = self.account
            await catalog.refreshRemote(fallbackBase: account.functionsURL, authToken: { await account.bearerToken() })
        }
    }
}

struct ExerciseRow: View {
    let exercise: CatalogExercise

    var body: some View {
        HStack(spacing: 12) {
            MuscleThumbnail(exercise: exercise)         // muscoli coinvolti in miniatura
            // Solo il nome: i muscoli coinvolti si vedono nella miniatura.
            Text(verbatim: exercise.name).font(.headline)
            Spacer()
            Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.secondary)
        }
        .glassCard(padding: 16)
    }
}

struct ExerciseDetailView: View {
    let exercise: CatalogExercise
    @Environment(SubscriptionManager.self) private var subscriptions
    @State private var showLists = false

    private var canSaveLists: Bool { FeatureGate.isAvailable(.savedExerciseLists, for: subscriptions.tier) }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                ScreenHeader(symbol: "dumbbell.fill", title: LocalizedStringKey(exercise.name),
                             subtitle: LocalizedStringKey(exercise.primary.map(\.title).joined(separator: ", ")))

                FlowLayout(spacing: 8) {
                    chip(LocalizedStringKey(exercise.kind.titleKey))
                    chip(exercise.mechanic == .compound ? "mech.compound" : "mech.isolation")
                    if !exercise.equipment.isEmpty { Text(verbatim: equipmentTitle(exercise.equipment)).font(.caption.bold()).padding(.horizontal, 12).padding(.vertical, 6).background(Color.primary.opacity(0.1), in: Capsule()) }
                    if !exercise.level.isEmpty { Text(LocalizedStringKey("level.\(exercise.level)")).font(.caption.bold()).padding(.horizontal, 12).padding(.vertical, 6).background(Color.primary.opacity(0.1), in: Capsule()) }
                    ForEach(exercise.secondary, id: \.self) { m in
                        Text(verbatim: m.title).font(.caption).padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Color.primary.opacity(0.06), in: Capsule())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if !exercise.images.isEmpty { ExercisePhotosCard(exercise: exercise) }
                ExerciseMusclesCard(exercise: exercise)

                if !exercise.steps.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("ex.how").font(.headline)
                        ForEach(Array(exercise.steps.enumerated()), id: \.offset) { i, step in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text("\(i + 1)").font(.headline).foregroundStyle(Theme.accent).frame(width: 22)
                                Text(verbatim: step).font(.callout)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()
                }

                NavigationLink { ItemEditorView(exercise: exercise, switchToWorkout: true) } label: {
                    Label("ex.train", systemImage: "plus.circle.fill").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent).tint(Theme.accent)

                if canSaveLists {
                    Button { showLists = true } label: {
                        Label("ex.addToList", systemImage: "text.badge.plus").lineLimit(1).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                } else {
                    Label("ex.listsLocked", systemImage: "lock.fill").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
        .appScreen()
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showLists) { AddToListSheet(exercise: exercise) }
    }

    private func chip(_ key: LocalizedStringKey) -> some View {
        Text(key).font(.caption.bold()).padding(.horizontal, 12).padding(.vertical, 6)
            .background(Theme.accent.opacity(0.35), in: Capsule())
    }
}

struct AddToListSheet: View {
    let exercise: CatalogExercise
    @Environment(\.dismiss) private var dismiss
    private var store: WorkoutListStore { WorkoutListStore.shared }
    @AppStorage(ConsentStore.grantedAtKey) private var consentAt = 0.0
    @State private var newName = ""

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: 14) {
                    Text("ex.addToList").font(.title3.bold())
                    if consentAt == 0 {
                        Label("lists.needConsent", systemImage: "lock.fill").font(.callout).glassCard()
                    } else {
                        ForEach(store.lists) { list in
                            Button {
                                store.addToList(list.id, exerciseID: exercise.id)
                                dismiss()
                            } label: {
                                HStack {
                                    Text(verbatim: list.name).font(.headline)
                                    Spacer()
                                    if list.exerciseIDs.contains(exercise.id) { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent) }
                                }
                                .glassCard(padding: 16)
                            }
                            .buttonStyle(.plain)
                        }
                        HStack {
                            TextField("lists.newName", text: $newName).textFieldStyle(.plain)
                            Button("lists.create") {
                                let name = newName.trimmingCharacters(in: .whitespaces)
                                guard !name.isEmpty else { return }
                                store.createList(name: name, items: [WorkoutItem(exerciseID: exercise.id)])
                                dismiss()
                            }
                            .buttonStyle(.glassProminent).tint(Theme.accent)
                        }
                        .glassCard(padding: 16)
                    }
                    Button("info.cancel") { dismiss() }.buttonStyle(.glass)
                }
                .padding(24)
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { store.reload() }
    }
}

/// Elenchi preimpostati (uguali per tutti) ed elenchi salvati dall'utente.
struct ExerciseListsView: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(SubscriptionManager.self) private var subscriptions
    @AppStorage(ConsentStore.grantedAtKey) private var consentAt = 0.0
    @State private var showNew = false
    private var store: WorkoutListStore { WorkoutListStore.shared }
    @State private var newName = ""

    private var pool: [CatalogExercise] { catalog.visible(for: subscriptions.tier) }
    private var canSave: Bool { FeatureGate.isAvailable(.savedExerciseLists, for: subscriptions.tier) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ScreenHeader(symbol: "list.bullet.rectangle", title: "lists.title", subtitle: "lists.subtitle")

                Text("lists.presets").font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                ForEach(BodyRegion.allCases, id: \.self) { region in
                    let items = pool.filter { ex in ex.primary.contains { $0.region == region } }
                    if !items.isEmpty {
                        NavigationLink { ExerciseCollectionView(title: region.title, exercises: items) } label: {
                            HStack {
                                Label(region.title, systemImage: region.symbol).font(.headline)
                                Spacer()
                                Text("\(items.count)").foregroundStyle(.secondary)
                            }
                            .glassCard(padding: 16)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text("lists.mine").font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                if !canSave {
                    Label("ex.listsLocked", systemImage: "lock.fill").font(.footnote).foregroundStyle(.secondary)
                } else if consentAt == 0 {
                    Label("lists.needConsent", systemImage: "lock.fill").font(.footnote).foregroundStyle(.secondary)
                } else {
                    ForEach(store.lists) { list in
                        NavigationLink {
                            ExerciseCollectionView(title: list.name, exercises: list.exerciseIDs.compactMap { catalog.exercise(id: $0) })
                        } label: {
                            HStack {
                                Text(verbatim: list.name).font(.headline)
                                Spacer()
                                Text("\(list.exerciseIDs.count)").foregroundStyle(.secondary)
                            }
                            .glassCard(padding: 16)
                        }
                        .buttonStyle(.plain)
                        .contextMenu { Button("history.delete", role: .destructive) { store.deleteList(list.id) } }
                    }
                    Button { showNew = true } label: { Label("lists.new", systemImage: "plus").lineLimit(1).frame(maxWidth: .infinity) }
                        .buttonStyle(.glass)
                }
            }
            .padding(20)
        }
        .appScreen()
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { store.reload() }
        .alert("lists.new", isPresented: $showNew) {
            TextField("lists.newName", text: $newName)
            Button("lists.create") {
                let name = newName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { store.createList(name: name) }
                newName = ""
            }
            Button("info.cancel", role: .cancel) { newName = "" }
        }
    }
}

struct ExerciseCollectionView: View {
    let title: String
    let exercises: [CatalogExercise]
    @State private var kind: ExerciseKind?
    @State private var shown = CatalogFilter.pageSize

    var body: some View {
        let items = CatalogFilter.byKind(exercises, kind: kind)
        ScrollView {
            VStack(spacing: 12) {
                if exercises.count > CatalogFilter.pageSize { KindChips(kind: $kind) }
                if items.isEmpty { Text("ex.none").foregroundStyle(.secondary).glassCard(padding: 16) }
                ForEach(items.prefix(shown)) { ex in
                    NavigationLink { ExerciseDetailView(exercise: ex) } label: { ExerciseRow(exercise: ex) }
                        .buttonStyle(.plain)
                }
                ShowMoreButton(remaining: items.count - shown) { shown += CatalogFilter.pageSize }
            }
            .padding(20)
        }
        .onChange(of: kind) { _, _ in shown = CatalogFilter.pageSize }
        .appScreen()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Immagine dei muscoli coinvolti: la figura anatomica con i muscoli principali (arancio pieno) e secondari
/// (arancio tenue). Si mostrano solo i lati (fronte, retro) dove si vede almeno un muscolo dell'esercizio.
/// Stessa scheda dell'app Android (ExerciseMusclesCard in Exercises.kt).
struct ExerciseMusclesCard: View {
    let exercise: CatalogExercise

    private var primary: Set<MuscleGroup> { Set(exercise.primary) }
    private var secondary: Set<MuscleGroup> { Set(exercise.secondary).subtracting(primary) }
    private var sides: [Bool] { figureSides(primary.union(secondary)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ex.musclesWorked").font(.headline)
            HStack(spacing: 24) {
                ForEach(sides, id: \.self) { front in
                    VStack(spacing: 6) {
                        MuscleFigure(front: front, highlight: { m in
                            primary.contains(m) ? .primary : (secondary.contains(m) ? .secondary : .idle)
                        })
                        .frame(height: 250)
                        Text(front ? BodySide.front.titleKey : BodySide.back.titleKey).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            legend(AnyShapeStyle(Theme.accentGradient), "ex.primaryMuscles", exercise.primary)
            if !secondary.isEmpty {
                legend(AnyShapeStyle(Theme.accent.opacity(0.45)), "ex.secondaryMuscles",
                       exercise.secondary.filter { secondary.contains($0) })
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .accessibilityElement(children: .combine)
    }

    private func legend(_ style: AnyShapeStyle, _ title: LocalizedStringKey, _ muscles: [MuscleGroup]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(style).frame(width: 12, height: 12)
            // Titolo e due punti affiancati senza spazio (il "+" tra Text è deprecato da iOS 26)
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(title)
                Text(verbatim: ": ")
            }
            .font(.footnote.bold())
            Text(verbatim: muscles.map(\.title).joined(separator: ", ")).font(.footnote).foregroundStyle(.secondary)
        }
    }
}

/// Filtro per tipo di esercizio: Tutti, Forza, Pliometria, Stretching, Cardio (come KindChips su Android).
struct KindChips: View {
    @Binding var kind: ExerciseKind?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                chip("kind.all", on: kind == nil) { kind = nil }
                ForEach(ExerciseKind.allCases) { k in
                    chip(LocalizedStringKey(k.titleKey), on: kind == k) { kind = (kind == k) ? nil : k }
                }
            }
        }
    }

    private func chip(_ title: LocalizedStringKey, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14).padding(.vertical, 9)
                .foregroundStyle(on ? Color.white : Color.primary)
                .background(on ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Color.primary.opacity(0.10)), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Filtro "Corpo libero" (per tutti i piani): acceso, esclude tutti gli esercizi che usano un attrezzo.
/// Come BodyweightChip su Android.
struct BodyweightChip: View {
    @Binding var on: Bool

    var body: some View {
        Button { on.toggle() } label: {
            Text("ex.bodyweight")
                .font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .foregroundStyle(on ? Color.white : Color.primary)
                .background(on ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Color.primary.opacity(0.10)), in: Capsule())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

// MARK: - Attrezzi in casa (solo piano Full)
// Si possono spegnere con AppFlags.homeEquipment = false.

/// Esercizi filtrati per gli attrezzi in casa: solo se la funzione e' accesa, il filtro e' attivo e il piano e' Full.
@MainActor
func equipmentFiltered(_ list: [CatalogExercise], tier: SubscriptionTier) -> [CatalogExercise] {
    let settings = AppSettings.shared
    return HomeEquipment.filter(list, owned: settings.ownedEquipment,
                                enabled: AppFlags.homeEquipment && settings.equipmentFilter
                                    && FeatureGate.isAvailable(.homeEquipment, for: tier))
}

/// Riquadro "Attrezzi in casa", sopra i filtri degli esercizi (schede Esercizi e Aggiungi esercizio).
/// Piano Full: mostra gli attrezzi segnati e apre l'elenco per aggiungerli o toglierli. Altri piani: invito ai piani.
/// Come HomeEquipmentCard su Android.
struct HomeEquipmentCard: View {
    let tier: SubscriptionTier
    @State private var editing = false
    private var settings: AppSettings { AppSettings.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("equipment.home.title", systemImage: "house.fill")
                .font(.headline).lineLimit(1).minimumScaleFactor(0.6)
            if !FeatureGate.isAvailable(.homeEquipment, for: tier) {
                LockedNote(key: "equipment.home.locked")
            } else {
                let owned = HomeEquipment.choices.filter { settings.ownedEquipment.contains($0) }
                if owned.isEmpty {
                    Text("equipment.home.none").font(.footnote).foregroundStyle(.secondary)
                } else {
                    FlowLayout(spacing: 8) {
                        ForEach(owned, id: \.self) { name in
                            Text(verbatim: equipmentTitle(name)).font(.caption.bold())
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(Theme.accent.opacity(0.35), in: Capsule())
                        }
                    }
                }
                Button { editing = true } label: {
                    Label("equipment.home.edit", systemImage: "pencil").lineLimit(1).minimumScaleFactor(0.7).frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .sheet(isPresented: $editing) { HomeEquipmentSheet() }
    }
}

/// Elenco di tutti gli attrezzi: un tocco aggiunge o toglie l'attrezzo da quelli che si hanno in casa.
private struct HomeEquipmentSheet: View {
    @Environment(\.dismiss) private var dismiss
    private var settings: AppSettings { AppSettings.shared }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(HomeEquipment.choices, id: \.self) { name in
                        let on = settings.ownedEquipment.contains(name)
                        Button { settings.toggleOwnedEquipment(name) } label: {
                            HStack {
                                Text(verbatim: equipmentTitle(name)).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: on ? "checkmark.circle.fill" : "plus.circle")
                                    .foregroundStyle(on ? Theme.accent : .secondary)
                            }
                        }
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                } footer: {
                    Text("equipment.home.bodyweightNote")
                }
            }
            .navigationTitle("equipment.home.sheetTitle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("equipment.home.done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Filtro "Solo i miei attrezzi" accanto agli altri filtri: compare solo con il piano Full (come EquipmentFilterChip su Android).
struct EquipmentFilterChip: View {
    let tier: SubscriptionTier
    private var settings: AppSettings { AppSettings.shared }

    var body: some View {
        if AppFlags.homeEquipment && FeatureGate.isAvailable(.homeEquipment, for: tier) {
            let on = settings.equipmentFilter
            Button { settings.setEquipmentFilter(!on) } label: {
                Label("equipment.home.filter", systemImage: "house")
                    .font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .foregroundStyle(on ? Color.white : Color.primary)
                    .background(on ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Color.primary.opacity(0.10)), in: Capsule())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(on ? .isSelected : [])
        }
    }
}

/// Pulsante "Mostra altri" sotto gli elenchi lunghi (gli esercizi si mostrano a pagine).
struct ShowMoreButton: View {
    let remaining: Int
    let action: () -> Void

    var body: some View {
        if remaining > 0 {
            Button(action: action) {
                Label("ex.showMore \(remaining)", systemImage: "chevron.down").lineLimit(1).frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
        }
    }
}

/// Attrezzo tradotto (chiave equipment.<nome>); per le fonti esterne con nomi liberi si mostra il testo così com'è.
func equipmentTitle(_ raw: String) -> String {
    Bundle.main.localizedString(forKey: "equipment.\(raw)", value: raw.capitalized, table: nil)
}

/// Foto dell'esercizio (posizione iniziale e finale, dal Free Exercise DB), scaricate solo quando si apre la scheda.
/// Stessa scheda dell'app Android (ExercisePhotosCard in Exercises.kt).
struct ExercisePhotosCard: View {
    let exercise: CatalogExercise

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ex.photos").font(.headline)
            HStack(spacing: 10) {
                ForEach(Array(exercise.images.prefix(2).enumerated()), id: \.offset) { i, link in
                    VStack(spacing: 6) {
                        Color.primary.opacity(0.1)
                            .aspectRatio(4 / 3, contentMode: .fit)
                            .overlay {
                                AsyncImage(url: URL(string: link)) { phase in
                                    if let image = phase.image {
                                        image.resizable().scaledToFill()
                                    } else {
                                        Image(systemName: "dumbbell.fill").font(.title2).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        Text(LocalizedStringKey(i == 0 ? "ex.photoStart" : "ex.photoEnd")).font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Text("ex.photosCredit").font(.system(size: 8.8)).foregroundStyle(.secondary) // 20% più piccola di .caption2 (11 pt)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}
