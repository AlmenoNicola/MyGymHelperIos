import SwiftUI
import SwiftData
import MyGymHelperCore

/// Nutrizione: profilo (dati sanitari, solo con consenso), BMI (Free), obiettivi di calorie e macro (Mid+),
/// piano dei pasti per dieta e giorno di allenamento (Full), scheda del nutrizionista (Full), ricerca alimenti (Mid+).
/// Indicazioni generali: non sostituisce un nutrizionista e non considera allergie o patologie.
struct NutritionView: View {
    @Environment(SubscriptionManager.self) private var subscriptions
    @Environment(\.modelContext) private var context
    @Query private var profiles: [HealthProfileRecord]
    @AppStorage(ConsentStore.grantedAtKey) private var consentAt = 0.0
    @State private var showConsent = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ScreenHeader(symbol: "fork.knife", title: "nutrition.title", subtitle: "nutrition.subtitle")
                    .tutorialTarget(TutorialTarget.tabNutrition)
                if consentAt == 0 {
                    VStack(spacing: 14) {
                        Label("consent.locked", systemImage: "lock.fill").font(.callout)
                        Button("consent.open") { showConsent = true }
                            .buttonStyle(.glassProminent).tint(Theme.accent)
                    }
                    .frame(maxWidth: .infinity)
                    .glassCard()
                } else if let profile = profiles.first {
                    NutritionContent(profile: profile, tier: subscriptions.tier)
                } else {
                    ProgressView().onAppear(perform: createProfile)
                }

                Text(LocalizedStringKey(Disclaimer.bodyKey))
                    .font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 8)
            }
            .padding(20)
        }
        .tutorialScrollFollow()
        .appScreen()
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showConsent) { ConsentView { } }
    }

    /// Il profilo si crea solo dopo il consenso (contiene dati sanitari).
    private func createProfile() {
        guard consentAt > 0, profiles.isEmpty else { return }
        context.insert(HealthProfileRecord())
        try? context.save()
    }
}

private struct NutritionContent: View {
    @Bindable var profile: HealthProfileRecord
    let tier: SubscriptionTier
    @Query(sort: \NutritionPlanRecord.createdAt, order: .reverse) private var nutritionPlans: [NutritionPlanRecord]
    @Environment(\.modelContext) private var context
    @State private var trainingDay = false
    @State private var importer = PlanImportModel()
    @State private var editingPlan: NutritionDraft?

    private var sex: BiologicalSex { BiologicalSex(rawValue: profile.sex) ?? .male }
    private var activity: ActivityLevel { ActivityLevel(rawValue: profile.activity) ?? .light }
    /// Obiettivo scelto dall'utente oppure, finche' non ne sceglie uno, quello consigliato dal BMI.
    private var goal: Goal {
        NutritionCalculator.effectiveGoal(chosen: profile.goalChosen, goalRaw: profile.goal,
                                          weightKg: profile.weightKg, heightCm: profile.heightCm)
    }
    /// Calorie per i tre obiettivi (dimagrire, mantenere, aumentare).
    private var allTargets: [Goal: DailyTargets] {
        NutritionCalculator.allTargets(sex: sex, weightKg: profile.weightKg, heightCm: profile.heightCm,
                                       ageYears: profile.age, activity: activity)
    }
    private var diets: Set<DietType> {
        let set = Set(profile.diets.compactMap(DietType.init(rawValue:)))
        return set.isEmpty ? [.omnivore] : set
    }
    private var targets: DailyTargets {
        allTargets[goal] ?? NutritionCalculator.targets(sex: sex, weightKg: profile.weightKg, heightCm: profile.heightCm,
                                                        ageYears: profile.age, activity: activity, goal: goal)
    }

    var body: some View {
        VStack(spacing: 20) {
            ProfileCard(profile: profile).tutorialTarget(TutorialTarget.nutritionProfile)
            BMICard(weightKg: profile.weightKg, heightCm: profile.heightCm)

            if FeatureGate.isAvailable(.generalNutritionAdvice, for: tier) {
                TargetsCard(all: allTargets, selected: goal, profile: profile)
                NavigationLink { FoodSearchView() } label: {
                    Label("food.search.open", systemImage: "magnifyingglass").lineLimit(1).frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
            } else {
                LockedNote(key: "nutrition.targetsLocked").glassCard(padding: 16)
            }

            if FeatureGate.isAvailable(.dietPlans, for: tier) {
                mealPlan
            } else {
                LockedNote(key: "nutrition.mealsLocked").glassCard(padding: 16)
            }

            if FeatureGate.isAvailable(.uploadTrainingAndNutritionPlans, for: tier) {
                nutritionistSection
            }
        }
        .onChange(of: profile.weightKg) { try? context.save() }
        .sheet(item: $importer.nutritionDraft) { draft in NutritionPlanReviewView(draft: draft) }
        .sheet(item: $editingPlan) { draft in NutritionPlanReviewView(draft: draft) }
        .importErrorAlert(importer)
    }

    private var mealPlan: some View {
        let day = DietPlanner.plan(targets: targets, diets: diets, trainingDay: trainingDay)
        return VStack(alignment: .leading, spacing: 14) {
            Text("nutrition.meals").font(.headline)
            Toggle("nutrition.trainingDay", isOn: $trainingDay).tint(Theme.accent)
            Text("nutrition.dayTotal \(day.calories) \(day.proteinG) \(day.carbsG) \(day.fatG)")
                .font(.subheadline).foregroundStyle(.secondary)
            ForEach(day.meals, id: \.nameKey) { meal in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(LocalizedStringKey(meal.nameKey)).font(.subheadline.bold())
                        Spacer()
                        Text(verbatim: "\(meal.calories) kcal").font(.subheadline.monospacedDigit())
                    }
                    Text("nutrition.macros \(meal.proteinG) \(meal.carbsG) \(meal.fatG)")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(verbatim: meal.suggestions.map { Bundle.main.localizedString(forKey: $0, value: $0, table: nil) }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(Theme.accentSoft)
                }
                .padding(.vertical, 4)
            }
            Text("nutrition.noRecipes").font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    @ViewBuilder
    private var nutritionistSection: some View {
        if let record = nutritionPlans.first,
           let plan = try? JSONDecoder().decode(ParsedNutritionPlan.self, from: record.data) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("nutritionist.title").font(.headline)
                    Spacer()
                    Button("plans.detail.edit") { editingPlan = NutritionDraft(plan: plan, sourceText: "") }
                        .buttonStyle(.glass)
                }
                if let kcal = plan.calories {
                    Text(verbatim: "\(kcal) kcal").font(.title3.bold())
                }
                Text(verbatim: [plan.proteinG.map { "P \($0) g" }, plan.carbsG.map { "C \($0) g" }, plan.fatG.map { "G \($0) g" }]
                        .compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline).foregroundStyle(.secondary)
                ForEach(plan.meals) { meal in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: meal.name).font(.subheadline.bold())
                        ForEach(Array(meal.items.enumerated()), id: \.offset) { _, item in
                            Text(verbatim: "• \(item)").font(.caption)
                        }
                    }
                }
                Button("history.delete", role: .destructive) {
                    context.delete(record); try? context.save()
                }
                .font(.footnote)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
        }
        ImportButtons(model: importer, kind: .nutrition)
    }
}

// MARK: - Profilo

private struct ProfileCard: View {
    @Bindable var profile: HealthProfileRecord
    @Environment(\.modelContext) private var context
    @AppStorage(HealthKitService.enabledKey) private var healthEnabled = false
    @State private var healthMessage: LocalizedStringKey?

    /// Legge da Apple Salute l'ultimo peso e l'ultima altezza registrati (solo su richiesta dell'utente).
    private func importFromHealth() async {
        let weight = await HealthKitService.shared.latestWeightKg()
        let height = await HealthKitService.shared.latestHeightCm()
        if let weight { profile.weightKg = min(max((weight * 10).rounded() / 10, 30), 250) }
        if let height { profile.heightCm = min(max(height.rounded(), 120), 230) }
        try? context.save()
        healthMessage = (weight == nil && height == nil) ? "health.noData" : "health.imported"
    }

    private func intBinding(_ keyPath: ReferenceWritableKeyPath<HealthProfileRecord, Double>) -> Binding<Int> {
        Binding(get: { Int(profile[keyPath: keyPath].rounded()) },
                set: { profile[keyPath: keyPath] = Double($0); try? context.save() })
    }

    private var diets: Set<DietType> { Set(profile.diets.compactMap(DietType.init(rawValue:))) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("profile.title").font(.headline)
            Picker("profile.sex", selection: $profile.sex) {
                Text("profile.male").tag("male")
                Text("profile.female").tag("female")
            }
            .pickerStyle(.segmented)
            CounterRow(title: "profile.age", value: Binding(get: { profile.age },
                                                             set: { profile.age = $0; try? context.save() }),
                       range: 18...100)
            // Peso scritto a mano (solo numeri, anche con i decimali) oppure con +/- di 1 kg.
            KgInputRow(title: "bmi.weight",
                       value: Binding(get: { profile.weightKg }, set: { profile.weightKg = $0; try? context.save() }),
                       range: 30...250, minus: { $0 - 1 }, plus: { $0 + 1 })
            CounterRow(title: "bmi.height", value: intBinding(\.heightCm), range: 120...230)
            if healthEnabled {
                Button {
                    Task { await importFromHealth() }
                } label: {
                    Label("health.import", systemImage: "heart.fill").lineLimit(1).frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                if let healthMessage { Text(healthMessage).font(.caption).foregroundStyle(.secondary) }
            }

            Picker("profile.activity", selection: $profile.activity) {
                Text("activity.sedentary").tag(ActivityLevel.sedentary.rawValue)
                Text("activity.light").tag(ActivityLevel.light.rawValue)
                Text("activity.moderate").tag(ActivityLevel.moderate.rawValue)
                Text("activity.high").tag(ActivityLevel.high.rawValue)
                Text("activity.veryHigh").tag(ActivityLevel.veryHigh.rawValue)
            }
            // L'obiettivo (dimagrire / mantenere / aumentare) si sceglie nella scheda del fabbisogno, con le calorie di ciascuno.

            Text("profile.diets").font(.subheadline.bold())
            FlowChips(items: DietType.allCases, isOn: { diets.contains($0) }, title: { diet in LocalizedStringKey("diet." + diet.rawValue as String) }) { toggle($0) }
        }
        .tint(Theme.accent)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .onChange(of: profile.sex) { try? context.save() }
        .onChange(of: profile.activity) { try? context.save() }
    }

    /// Onnivora esclude le altre diete; le altre si possono combinare (es. vegana + senza glutine).
    private func toggle(_ diet: DietType) {
        var set = diets
        if diet == .omnivore {
            set = [.omnivore]
        } else {
            set.remove(.omnivore)
            if set.contains(diet) { set.remove(diet) } else { set.insert(diet) }
            if set.isEmpty { set = [.omnivore] }
        }
        profile.diets = DietType.allCases.filter { set.contains($0) }.map(\.rawValue)
        try? context.save()
    }
}

/// Pulsanti a capsula che vanno a capo.
struct FlowChips<Item: Hashable>: View {
    let items: [Item]
    let isOn: (Item) -> Bool
    let title: (Item) -> LocalizedStringKey
    let action: (Item) -> Void

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items, id: \.self) { item in
                let on = isOn(item)
                Button { action(item) } label: {
                    Text(title(item)).font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .foregroundStyle(on ? Color.white : Color.primary)
                        .background(on ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Color.primary.opacity(0.10)), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

/// Layout semplice che dispone gli elementi in righe, andando a capo quando non c'e' spazio.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - BMI e obiettivi

private struct BMICard: View {
    let weightKg: Double
    let heightCm: Double

    private var result: BMIResult? { BMICalculator.calculate(weightKg: weightKg, heightCm: heightCm) }

    private func categoryKey(_ c: BMICategory) -> LocalizedStringKey {
        switch c {
        case .underweight: "bmi.under"
        case .normal: "bmi.normal"
        case .overweight: "bmi.over"
        case .obese: "bmi.obese"
        }
    }

    var body: some View {
        if let r = result {
            VStack(spacing: 12) {
                Text(verbatim: "BMI").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Text(r.value, format: .number.precision(.fractionLength(1)))
                    .font(.system(size: 64, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.accentGradient)
                    .contentTransition(.numericText())
                Text(categoryKey(r.category)).font(.headline)
                Gauge(value: min(max(r.value, 15), 40), in: 15...40) { EmptyView() }
                    .gaugeStyle(.linearCapacity)
                    .tint(Theme.accentGradient)
                Text("bmi.adultsOnly").font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .glassCard()
            .animation(.snappy, value: r.value)
        }
    }
}

/// Fabbisogno giornaliero: le calorie per dimagrire, mantenere e aumentare, una accanto all'altra. L'opzione consigliata
/// dal BMI (sottopeso -> aumentare, normopeso -> mantenere, sovrappeso/obesita' -> dimagrire) e' segnata e, finche'
/// l'utente non ne tocca un'altra, e' quella selezionata. Sotto, i macronutrienti dell'opzione selezionata.
private struct TargetsCard: View {
    let all: [Goal: DailyTargets]
    let selected: Goal
    @Bindable var profile: HealthProfileRecord
    @Environment(\.modelContext) private var context

    private var bmi: BMIResult? { BMICalculator.calculate(weightKg: profile.weightKg, heightCm: profile.heightCm) }
    private var recommended: Goal? { bmi.map { NutritionCalculator.recommendedGoal($0.category) } }

    private func categoryKey(_ c: BMICategory) -> String {
        switch c {
        case .underweight: "bmi.under"
        case .normal: "bmi.normal"
        case .overweight: "bmi.over"
        case .obese: "bmi.obese"
        }
    }

    private func choose(_ goal: Goal, chosen: Bool) {
        profile.goal = goal.rawValue
        profile.goalChosen = chosen
        try? context.save()
    }

    var body: some View {
        let t = all[selected]
        VStack(alignment: .leading, spacing: 12) {
            Text("nutrition.targets").font(.headline)
            HStack(spacing: 8) {
                ForEach([Goal.lose, .maintain, .gain], id: \.self) { g in
                    option(g)
                }
            }
            if let bmi, let recommended {
                Text("nutrition.recommendedFor \(String(localized: String.LocalizationValue(categoryKey(bmi.category))))")
                    .font(.caption).foregroundStyle(.secondary)
                if profile.goalChosen && selected != recommended {
                    Button("nutrition.useRecommended") { choose(recommended, chosen: false) }
                        .font(.subheadline).tint(Theme.accent)
                }
            }
            if let t {
                HStack(spacing: 12) {
                    macro("nutrition.protein", t.proteinGrams)
                    macro("nutrition.carbs", t.carbsGrams)
                    macro("nutrition.fat", t.fatGrams)
                }
            }
            Text("nutrition.indicative").font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .animation(.snappy, value: selected)
    }

    /// Una delle tre opzioni: nome dell'obiettivo, calorie al giorno, eventuale "Consigliato".
    private func option(_ g: Goal) -> some View {
        let isSelected = g == selected
        return Button { choose(g, chosen: true) } label: {
            VStack(spacing: 2) {
                Text(LocalizedStringKey("goal." + g.rawValue)).font(.subheadline.weight(.semibold))
                Text(verbatim: "\(all[g]?.calories ?? 0)")
                    .font(.system(size: 26, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(isSelected ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(.primary))
                Text("nutrition.perDay").font(.caption2).foregroundStyle(.secondary)
                Text(g == recommended ? LocalizedStringKey("nutrition.recommended") : LocalizedStringKey(" "))
                    .font(.caption2.bold()).foregroundStyle(Theme.accentSoft)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10).padding(.horizontal, 4)
            .background(isSelected ? Theme.accent.opacity(0.18) : Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16)
                .stroke(isSelected ? Theme.accent : Color.primary.opacity(0.13), lineWidth: isSelected ? 2 : 1))
        }
        .buttonStyle(.plain)
    }

    private func macro(_ title: LocalizedStringKey, _ grams: Int) -> some View {
        VStack(spacing: 4) {
            Text(verbatim: "\(grams) g").font(.title3.bold().monospacedDigit())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Scheda del nutrizionista (revisione)

struct NutritionPlanReviewView: View {
    @State var draft: NutritionDraft
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var existing: [NutritionPlanRecord]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("plans.review.check", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote).foregroundStyle(.orange)
                    field("nutrition.calories", value: $draft.plan.calories)
                    field("nutrition.protein", value: $draft.plan.proteinG)
                    field("nutrition.carbs", value: $draft.plan.carbsG)
                    field("nutrition.fat", value: $draft.plan.fatG)
                }
                ForEach($draft.plan.meals) { $meal in
                    Section {
                        TextField("nutritionist.mealName", text: $meal.name).font(.headline)
                        TextField("nutritionist.items", text: Binding(
                            get: { meal.items.joined(separator: "\n") },
                            set: { meal.items = $0.components(separatedBy: .newlines) }
                        ), axis: .vertical)
                        .lineLimit(2...10)
                        Button(role: .destructive) {
                            let id = meal.id
                            DispatchQueue.main.async { draft.plan.meals.removeAll { $0.id == id } }
                        } label: { Label("nutritionist.deleteMeal", systemImage: "trash") }
                    }
                }
                Section {
                    Button { draft.plan.meals.append(ParsedMeal(name: "", items: [])) } label: {
                        Label("nutritionist.addMeal", systemImage: "plus")
                    }
                }
                if !draft.sourceText.isEmpty {
                    Section {
                        DisclosureGroup("plans.review.source") {
                            Text(verbatim: draft.sourceText).font(.caption.monospaced()).textSelection(.enabled)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background { AppBackground() }
            .navigationTitle(Text("nutritionist.reviewTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("info.cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("plans.review.save", action: save) }
            }
        }
        .interactiveDismissDisabled()
    }

    private func field(_ title: LocalizedStringKey, value: Binding<Int?>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("—", value: value, format: .number).keyboardType(.numberPad)
                .multilineTextAlignment(.trailing).frame(maxWidth: 120)
        }
    }

    /// Si tiene una sola scheda del nutrizionista: la nuova sostituisce la precedente.
    private func save() {
        var plan = draft.plan
        plan.meals = plan.meals.compactMap { meal in
            var m = meal
            m.items = m.items.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            m.name = m.name.trimmingCharacters(in: .whitespaces)
            return (m.name.isEmpty && m.items.isEmpty) ? nil : m
        }
        guard let data = try? JSONEncoder().encode(plan) else { return }
        for old in existing { context.delete(old) }
        context.insert(NutritionPlanRecord(data: data))
        try? context.save()
        dismiss()
    }
}
