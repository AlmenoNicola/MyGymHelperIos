import SwiftUI
import SwiftData
import MyGymHelperCore

// Scheda personalizzata da altezza, peso, sesso, età, obiettivo, esperienza, allenamenti e luogo (solo Pro).
// Uguale su Android: ui/screens/CustomPlans.kt. Le regole sono nel Core (CustomPlans.swift).

/// Testo tradotto da una chiave costruita nel codice.
private func loc(_ key: String) -> String { NSLocalizedString(key, comment: "") }

func goalKey(_ g: Goal) -> String { "custom.goal." + g.rawValue }

func bmiKey(_ c: BMICategory) -> String {
    switch c {
    case .underweight: return "bmi.under"
    case .normal: return "bmi.normal"
    case .overweight: return "bmi.over"
    case .obese: return "bmi.obese"
    }
}

/// "Mantenere · 3 allenamenti a settimana" (con 1: "Mantenere · 1 allenamento a settimana").
func customFacts(_ r: CustomPlanRecord) -> String {
    if r.plan.daysPerWeek == 1 { return String(format: loc("custom.facts.one %@"), loc(goalKey(r.input.goal))) }
    return String(format: loc("custom.facts %@ %lld"), loc(goalKey(r.input.goal)), r.plan.daysPerWeek)
}

/// Peso con al massimo un decimale, nel formato del telefono (75 / 75,5).
private func kgText(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(0...1))) }

/// In cima alle Schede pronte: "Crea la tua scheda" e, sotto, le schede già create dall'utente.
struct CustomPlansSection: View {
    let tier: SubscriptionTier
    private var store: CustomPlanStore { CustomPlanStore.shared }

    var body: some View {
        let available = FeatureGate.isAvailable(.customPlans, for: tier)
        VStack(spacing: 16) {
            CreatePlanCard(tier: tier)
            if available && !store.plans.isEmpty {
                Text("custom.mine").appType(.sectionTitle, weight: .bold).lineLimit(1).minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                CustomPlanCards(tier: tier)
            }
        }
        .task { store.reload() }
    }
}

/// Card "Crea la tua scheda": apre l'editor della scheda su misura (Pro); nel Free con lucchetto e invito ai piani.
/// Usata nella schermata Schede pronte e in Allenamento (sotto la card dell'elenco).
struct CreatePlanCard: View {
    let tier: SubscriptionTier

    var body: some View {
        if FeatureGate.isAvailable(.customPlans, for: tier) {
            NavigationLink { CustomPlanEditorView(editID: nil) } label: { card(available: true) }
                .buttonStyle(.plain)
        } else {
            card(available: false)
        }
    }

    private func card(available: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "slider.horizontal.3").foregroundStyle(Theme.highlight).appFont(.title3)
                Text("custom.create").appType(.cardTitle).lineLimit(1).minimumScaleFactor(0.7)
                Spacer()
                if available { Image(systemName: "chevron.right").foregroundStyle(.secondary) }
            }
            Text("custom.create.summary").appType(.caption).foregroundStyle(.secondary)
            // Free: la card si vede, con l'invito ai piani
            if !available { LockedNote(key: "presets.locked") }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}

/// Card delle schede fatte con "Crea la tua scheda" (solo Pro), senza titolo: nome, obiettivo · allenamenti
/// a settimana ed etichette "Creata dall'app" + difficoltà. Usata nella schermata Schede pronte e in
/// Allenamento nel riquadro "Le mie schede".
struct CustomPlanCards: View {
    let tier: SubscriptionTier
    private var store: CustomPlanStore { CustomPlanStore.shared }

    var body: some View {
        if FeatureGate.isAvailable(.customPlans, for: tier) {
            ForEach(store.plans) { r in
                NavigationLink { PresetPlanView(planID: r.plan.id) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(verbatim: r.name).appType(.cardTitle).lineLimit(1).minimumScaleFactor(0.7)
                                Text(verbatim: customFacts(r)).appType(.caption).foregroundStyle(.secondary)
                                    .lineLimit(1).minimumScaleFactor(0.7)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }
                        PlanBadges(origin: .app, level: r.plan.level)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Perché la scheda è fatta così: dati inseriti, BMI, calorie indicative e regole speciali (età, impatto).
struct CustomPlanNotesView: View {
    let record: CustomPlanRecord

    var body: some View {
        let i = record.input
        let n = CustomPlanGenerator.notes(i)
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: String(format: loc("custom.note.person %@ %lld %lld %@"),
                                  loc(i.sex == .female ? "profile.female" : "profile.male"),
                                  i.age, Int(i.heightCm.rounded()), kgText(i.weightKg)))
                .appType(.secondary).foregroundStyle(.secondary)
            Text(verbatim: String(format: loc("custom.note.goal %@ %@ %@"), loc(goalKey(i.goal)),
                                  loc("custom.exp." + i.experience.rawValue), loc("custom.place." + i.place.rawValue)))
                .appType(.secondary).foregroundStyle(.secondary)
            if let bmi = n.bmi {
                Text(verbatim: String(format: loc("custom.note.bmi %@ %@"), kgText(bmi.value), loc(bmiKey(bmi.category))))
                    .appType(.secondary).foregroundStyle(.secondary)
            }
            Text(verbatim: String(format: loc("custom.note.kcal %lld"), n.dailyCalories))
                .appType(.secondary).foregroundStyle(.secondary)
            if n.lowImpact { Text("custom.note.lowImpact").appType(.caption).foregroundStyle(.secondary) }
            if n.gentleLoads { Text("custom.note.gentle").appType(.caption).foregroundStyle(.secondary) }
            // Principiante con 5 o più allenamenti: invito a riposare
            if n.manyDaysBeginner { Text("custom.note.manyDays").appType(.caption).foregroundStyle(.secondary) }
            Text("custom.note.rules").appType(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Pulsanti della scheda creata: rinomina, cambia i dati (rifà la scheda), elimina.
struct CustomPlanActions: View {
    let record: CustomPlanRecord
    @Environment(\.dismiss) private var dismiss
    @State private var renaming = false
    @State private var newName = ""
    @State private var deleting = false
    private var store: CustomPlanStore { CustomPlanStore.shared }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button { newName = record.name; renaming = true } label: {
                    Label("custom.rename", systemImage: "pencil").lineLimit(1).minimumScaleFactor(0.7).frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass).appType(.button)
                NavigationLink { CustomPlanEditorView(editID: record.id) } label: {
                    Label("custom.redo", systemImage: "slider.horizontal.3").lineLimit(1).minimumScaleFactor(0.7).frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass).appType(.button)
            }
            Button(role: .destructive) { deleting = true } label: {
                Label("custom.delete", systemImage: "trash").lineLimit(1).minimumScaleFactor(0.7).frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass).appType(.button).tint(.red)
        }
        .alert("custom.rename", isPresented: $renaming) {
            TextField("custom.name", text: $newName)
            Button("custom.save") {
                let name = String(newName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
                if !name.isEmpty { store.rename(record.id, to: name) }
            }
            .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("info.cancel", role: .cancel) { }
        }
        .alert("custom.deleteTitle", isPresented: $deleting) {
            Button("custom.delete", role: .destructive) {
                store.delete(record.id)
                dismiss()
            }
            Button("info.cancel", role: .cancel) { }
        } message: {
            Text("custom.deleteBody")
        }
    }
}

/// Modulo dei dati: nuova scheda (`editID` = nil) o scheda da rifare con dati nuovi (stesso id, nome e data).
/// I valori di partenza arrivano dal profilo (o dalla scheda da rifare); i dati del corpo aggiornano anche il profilo.
/// Creata una scheda nuova, al posto del modulo si apre il suo dettaglio (come su Android: indietro torna alle schede).
struct CustomPlanEditorView: View {
    let editID: String?
    @Environment(SubscriptionManager.self) private var subscriptions
    @Environment(CatalogStore.self) private var catalog
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [HealthProfileRecord]
    @AppStorage(ConsentStore.grantedAtKey) private var consentAt = 0.0
    @State private var input: CustomPlanInput?
    @State private var name = ""
    @State private var showConsent = false
    @State private var createdPlanID: String?
    private var store: CustomPlanStore { CustomPlanStore.shared }

    private var editing: CustomPlanRecord? { editID.flatMap { store.record(id: $0) } }

    var body: some View {
        if let createdPlanID {
            PresetPlanView(planID: createdPlanID)
        } else {
            ScrollView {
                VStack(spacing: 16) {
                    ScreenHeader(symbol: "slider.horizontal.3",
                                 title: editing != nil ? "custom.editor.redo" : "custom.editor.title",
                                 subtitle: "custom.editor.subtitle")
                    if !FeatureGate.isAvailable(.customPlans, for: subscriptions.tier) {
                        LockedNote(key: "presets.locked").glassCard(padding: 16)
                    } else if consentAt == 0 {
                        // Senza consenso ai dati sulla salute niente scheda (eta', altezza e peso sono dati sanitari)
                        VStack(spacing: 14) {
                            Label("consent.locked", systemImage: "lock.fill").appType(.body)
                            Button("consent.open") { showConsent = true }
                                .buttonStyle(.glassProminent).appType(.button).tint(Theme.accent)
                        }
                        .frame(maxWidth: .infinity)
                        .glassCard()
                    } else if input != nil {
                        form
                    } else {
                        ProgressView()
                    }
                }
                .padding(20)
            }
            .appScreen()
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showConsent) { ConsentView { } }
            .onAppear(perform: start)
        }
    }

    /// Valori di partenza: dalla scheda da rifare oppure dal profilo e dagli attrezzi in casa.
    private func start() {
        guard input == nil else { return }
        store.reload()
        if let editing {
            input = editing.input
            name = editing.name
        } else {
            let p = profiles.first.map {
                HealthProfile(sex: $0.sex, age: $0.age, heightCm: $0.heightCm, weightKg: $0.weightKg,
                              goal: $0.goal, goalChosen: $0.goalChosen)
            }
            input = CustomPlanInput.fromProfile(p, owned: AppSettings.shared.ownedEquipment)
            name = CustomPlanGenerator.suggestedName(loc("custom.defaultName"), existing: store.plans)
        }
    }

    /// Binding a un campo dei dati inseriti.
    private func field<T>(_ keyPath: WritableKeyPath<CustomPlanInput, T>, _ fallback: T) -> Binding<T> {
        Binding(get: { input?[keyPath: keyPath] ?? fallback }, set: { input?[keyPath: keyPath] = $0 })
    }

    @ViewBuilder
    private var form: some View {
        let current = input ?? CustomPlanInput()
        let limitReached = editing == nil && store.plans.count >= CustomPlanGenerator.maxPlans

        VStack(alignment: .leading, spacing: 16) {
            Text("custom.section.body").appType(.cardTitle)
            Picker("profile.sex", selection: field(\.sex, .male)) {
                Text("profile.male").tag(BiologicalSex.male)
                Text("profile.female").tag(BiologicalSex.female)
            }
            .pickerStyle(.segmented)
            CounterRow(title: "profile.age", value: field(\.age, 30), range: 18...100)
            CounterRow(title: "bmi.height", value: Binding(get: { Int(current.heightCm.rounded()) },
                                                           set: { input?.heightCm = Double($0) }), range: 120...230)
            // Peso scritto a mano (solo numeri) oppure con +/- di 1 kg, come nel profilo.
            KgInputRow(title: "bmi.weight", value: field(\.weightKg, 70), range: 30...250, minus: { $0 - 1 }, plus: { $0 + 1 })
        }
        .tint(Theme.accent)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()

        VStack(alignment: .leading, spacing: 12) {
            Text("custom.section.training").appType(.cardTitle)
            Text("custom.goal").appType(.secondary, weight: .bold)
            Picker("custom.goal", selection: field(\.goal, .maintain)) {
                ForEach([Goal.lose, .maintain, .gain], id: \.self) { g in Text(LocalizedStringKey(goalKey(g))).tag(g) }
            }
            .pickerStyle(.segmented)
            if let bmi = current.bmi {
                Text(verbatim: String(format: loc("custom.goal.recommended %@"),
                                      loc(goalKey(NutritionCalculator.recommendedGoal(bmi.category)))))
                    .appType(.caption).foregroundStyle(.secondary)
            }
            Text("custom.experience").appType(.secondary, weight: .bold)
            Picker("custom.experience", selection: field(\.experience, .beginner)) {
                ForEach(Experience.allCases, id: \.self) { e in Text(LocalizedStringKey("custom.exp." + e.rawValue)).tag(e) }
            }
            .pickerStyle(.segmented)
            Text("custom.days").appType(.secondary, weight: .bold)
            // Da 1 a 7 allenamenti a settimana (con 7 uno è di stretching)
            Picker("custom.days", selection: field(\.daysPerWeek, 3)) {
                ForEach(CustomPlanInput.minDays...CustomPlanInput.maxDays, id: \.self) { d in
                    Text(verbatim: "\(d)").tag(d)
                }
            }
            .pickerStyle(.segmented)
            if let input, CustomPlanGenerator.isManyDaysBeginner(input) {
                Text("custom.note.manyDays").appType(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("custom.place").appType(.secondary, weight: .bold)
            Picker("custom.place", selection: field(\.place, .gym)) {
                ForEach(TrainingPlace.allCases, id: \.self) { p in Text(LocalizedStringKey("custom.place." + p.rawValue)).tag(p) }
            }
            .pickerStyle(.segmented)
            if current.place == .home {
                Text("custom.place.homeNote").appType(.caption).foregroundStyle(.secondary)
                FlowChips(items: HomeEquipment.choices, isOn: { current.ownedEquipment.contains($0) },
                          title: { LocalizedStringKey("equipment." + $0) }) { eq in
                    if current.ownedEquipment.contains(eq) { input?.ownedEquipment.remove(eq) } else { input?.ownedEquipment.insert(eq) }
                }
            }
        }
        .tint(Theme.accent)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()

        VStack(alignment: .leading, spacing: 12) {
            Text("custom.name").appType(.secondary, weight: .bold)
            TextField("custom.name", text: $name)
                .textFieldStyle(.plain)
                .padding(14)
                .glassEffect(.regular, in: .capsule)
                .onChange(of: name) { _, v in if v.count > 60 { name = String(v.prefix(60)) } }
            if limitReached {
                Text(verbatim: String(format: loc("custom.limit %lld"), CustomPlanGenerator.maxPlans))
                    .appType(.caption).foregroundStyle(.secondary)
            }
            Button(action: create) {
                Label(editing != nil ? "custom.regenerate" : "custom.generate", systemImage: "slider.horizontal.3")
                    .appType(.cta).lineLimit(1).minimumScaleFactor(0.7).frame(maxWidth: .infinity).padding(.vertical, 4)
            }
            .buttonStyle(.glassProminent).appType(.button).tint(Theme.accent)
            .disabled(limitReached || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || catalog.all.isEmpty)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func create() {
        guard let raw = input else { return }
        let i = raw.clamped()
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let id = editing?.id ?? UUID().uuidString.lowercased()
        // Con lo stesso id la scheda rifatta resta la stessa scheda (stesso nome nella lista); il seed cambia
        // con la data, così anche con dati uguali si possono avere esercizi diversi.
        let seed = id + String(now)
        let plan = CustomPlanGenerator.generate(i, catalog: catalog.all, seed: seed, planID: CustomPlanGenerator.idPrefix + id)
        let wasNew = editing == nil
        store.save(CustomPlanRecord(id: id, name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                    createdAt: editing?.createdAt ?? now, input: i, plan: plan))
        // I dati del corpo valgono anche per il profilo (BMI, fabbisogno): una sola persona per telefono.
        // L'obiettivo del profilo non cambia.
        let profile: HealthProfileRecord
        if let existing = profiles.first { profile = existing } else { profile = HealthProfileRecord(); context.insert(profile) }
        let oldWeight = profiles.first?.weightKg
        profile.sex = i.sex.rawValue
        profile.age = i.age
        profile.heightCm = i.heightCm
        profile.weightKg = i.weightKg
        try? context.save()
        // Peso diverso da quello del profilo: si salva anche la pesata di oggi (grafico del peso nel Profilo)
        if oldWeight != i.weightKg { ProfileData.setWeight(i.weightKg, profile: profile) }
        if wasNew { createdPlanID = plan.id } else { dismiss() }
    }
}
