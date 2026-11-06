import SwiftUI
import SwiftData
import MyGymHelperCore

// Scheda Profilo (tra Esercizi e Impostazioni): dati personali con l'avatar, muscoli fronte e retro con la
// percentuale di utilizzo e grafici dell'andamento, tutti legati allo stesso periodo (giorno, settimana, mese, anno,
// totale). Free: dati, avatar e muscoli del giorno; Pro: gli altri periodi e i grafici (Feature.profileStats).
// Le regole sono nel Core (ProfileStats.swift); uguale su Android: ui/screens/Profile.kt.

/// Testo tradotto da una chiave costruita nel codice.
private func loc(_ key: String) -> String { NSLocalizedString(key, comment: "") }

/// Numero con al massimo un decimale, nel formato del telefono (79 / 79,5).
private func num1(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(0...1))) }

/// Percentuale intera; sotto l'1% si scrive "<1%" (così un muscolo usato poco non sembra a zero).
private func percentText(_ p: Double) -> String { p > 0 && p < 1 ? "<1%" : "\(Int(p.rounded()))%" }

struct ProfileView: View {
    @Environment(SubscriptionManager.self) private var subscriptions
    @Environment(CatalogStore.self) private var catalog
    @Environment(\.modelContext) private var context
    @Query private var profiles: [HealthProfileRecord]
    @Query(sort: \WorkoutSessionRecord.startedAt) private var sessions: [WorkoutSessionRecord]
    @Query(sort: \WeightEntryRecord.at) private var weights: [WeightEntryRecord]
    @AppStorage(ConsentStore.grantedAtKey) private var consentAt = 0.0
    @State private var showConsent = false
    @State private var period: StatsPeriod = .day

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ScreenHeader(symbol: "person.fill", title: "profile.tab.title", subtitle: "profile.tab.subtitle")
                    .tutorialTarget(TutorialTarget.tabProfile)
                // Età, peso, sesso e altezza sono dati sulla salute: senza consenso non si salvano (come la Nutrizione).
                if consentAt == 0 {
                    VStack(spacing: 14) {
                        Label("profile.needConsent", systemImage: "lock.fill").font(.callout)
                        Button("consent.open") { showConsent = true }
                            .buttonStyle(.glassProminent).tint(Theme.accent)
                    }
                    .frame(maxWidth: .infinity)
                    .glassCard()
                } else if let profile = profiles.first {
                    PersonalDataCard(profile: profile)
                    stats
                } else {
                    ProgressView().onAppear(perform: createProfile)
                }
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

    /// Storico nel formato del Core (peso di ogni serie: quello della serie o della sessione).
    private var statsSessions: [StatsSession] {
        sessions.map { s in
            StatsSession(startedAt: ProfileStats.millis(s.startedAt), exerciseID: s.exerciseID,
                         sets: s.sets.map { StatsSet(doneReps: $0.doneReps, weightKg: $0.setWeightKg) })
        }
    }

    @ViewBuilder
    private var stats: some View {
        let pro = FeatureGate.isAvailable(.profileStats, for: subscriptions.tier)
        let zone = TimeZone.current
        let now = ProfileStats.millis(Date())
        let all = statsSessions
        let log = weights.map { WeightEntry(at: ProfileStats.millis($0.at), kg: $0.kg) }
        // Periodo: vale per i muscoli e per i grafici. Nel Free solo "Giorno".
        let shown = pro || period.isFree ? period : .day
        let buckets = ProfileStats.buckets(shown, now: now, zone: zone, firstActivity: ProfileStats.firstActivity(all, log))
        let from = buckets.first?.start ?? now
        let to = buckets.last?.end ?? now
        let shares = ProfileStats.muscleShares(all, catalog: catalog.all, from: from, to: to)

        VStack(alignment: .leading, spacing: 12) {
            Text("profile.muscles.title").font(.headline).lineLimit(1).minimumScaleFactor(0.7)
            PeriodPicker(selected: $period)
            if !pro && !period.isFree { LockedNote(key: "profile.period.locked") }
            Text(verbatim: rangeText(shown, buckets)).font(.caption).foregroundStyle(.secondary)
            MuscleUsage(shares: shares)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .tutorialTarget(TutorialTarget.profileMuscles)

        if !pro {
            VStack(alignment: .leading, spacing: 10) {
                Text("profile.charts.title").font(.headline).lineLimit(1).minimumScaleFactor(0.7)
                LockedNote(key: "profile.charts.locked")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
            .tutorialTarget(TutorialTarget.profileCharts)
        } else {
            let series = ProfileStats.series(all, buckets: buckets, zone: zone)
            let totals = ProfileStats.totals(all, from: from, to: to, zone: zone)
            VStack(alignment: .leading, spacing: 10) {
                Text("profile.charts.title").font(.headline).lineLimit(1).minimumScaleFactor(0.7)
                HStack(spacing: 8) {
                    StatTile(title: "profile.stat.workouts", value: "\(totals.workouts)")
                    StatTile(title: "profile.stat.sets", value: "\(totals.sets)")
                    StatTile(title: "profile.stat.reps", value: "\(totals.reps)")
                    StatTile(title: "profile.stat.volume", value: Int(totals.volumeKg.rounded()).formatted())
                }
                if totals.sessions == 0 { Text("profile.charts.empty").font(.footnote).foregroundStyle(.secondary) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
            .tutorialTarget(TutorialTarget.profileCharts)

            BarChartCard(title: "profile.chart.workouts", buckets: buckets, values: series.map { Double($0.workouts) }) { "\(Int($0.rounded()))" }
            BarChartCard(title: "profile.chart.sets", buckets: buckets, values: series.map { Double($0.sets) }) { "\(Int($0.rounded()))" }
            BarChartCard(title: "profile.chart.volume", buckets: buckets, values: series.map(\.volumeKg)) { Int($0.rounded()).formatted() + " kg" }
            BarChartCard(title: "profile.chart.reps", buckets: buckets, values: series.map { Double($0.reps) }) { "\(Int($0.rounded()))" }
            WeightChartCard(buckets: buckets, weights: ProfileStats.weightSeries(log, buckets: buckets),
                            change: WeightLog.change(log, from: from, to: to))
        }
    }
}

// MARK: - Dati personali

/// Dati personali con l'avatar: sesso, età, altezza e peso (usati anche da "Crea la tua scheda").
/// Ogni modifica si salva subito nel profilo; il peso salva anche la pesata di oggi.
private struct PersonalDataCard: View {
    @Bindable var profile: HealthProfileRecord
    @Environment(\.modelContext) private var context

    var body: some View {
        let sex = BiologicalSex(rawValue: profile.sex) ?? .male
        VStack(alignment: .leading, spacing: 14) {
            Text("profile.data.title").font(.headline).lineLimit(1).minimumScaleFactor(0.7)
            HStack(alignment: .center, spacing: 12) {
                AvatarView(sex: sex, heightCm: profile.heightCm, weightKg: profile.weightKg).frame(height: 190)
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: String(format: loc("profile.data.summary %lld %@ %lld"),
                                          Int(profile.heightCm.rounded()), num1(profile.weightKg), profile.age))
                        .font(.callout.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.6)
                    if let b = BMICalculator.calculate(weightKg: profile.weightKg, heightCm: profile.heightCm) {
                        Text(verbatim: String(format: loc("profile.data.bmi %@ %@"), num1(b.value), loc(bmiKey(b.category))))
                            .font(.subheadline).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.6)
                    }
                    Text("profile.data.note").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Picker("profile.sex", selection: Binding(get: { profile.sex }, set: { profile.sex = $0; try? context.save() })) {
                Text("profile.male").tag("male")
                Text("profile.female").tag("female")
            }
            .pickerStyle(.segmented)
            CounterRow(title: "profile.age", value: Binding(get: { profile.age }, set: { profile.age = $0; try? context.save() }),
                       range: 18...100)
            CounterRow(title: "bmi.height", value: Binding(get: { Int(profile.heightCm.rounded()) },
                                                           set: { profile.heightCm = Double($0); try? context.save() }),
                       range: 120...230)
            // Peso scritto a mano o con +/- di 1 kg; ogni cambio aggiorna anche la pesata di oggi (grafico del peso).
            KgInputRow(title: "bmi.weight", value: Binding(get: { profile.weightKg }, set: { ProfileData.setWeight($0, profile: profile) }),
                       range: 30...250, minus: { $0 - 1 }, plus: { $0 + 1 })
        }
        .tint(Theme.accent)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}

/// Avatar: sagoma deformata con sesso, altezza e BMI (AvatarFigure nel Core), sempre con i piedi in basso.
struct AvatarView: View {
    let sex: BiologicalSex
    let heightCm: Double
    let weightKg: Double

    var body: some View {
        let paths = AvatarFigure.paths(sex: sex, heightCm: heightCm, weightKg: weightKg).map(FigurePaths.path)
        let fill = Gradient(colors: [Theme.accentSoft, Theme.accent])
        GeometryReader { geo in
            let s = geo.size.width / AvatarFigure.width
            Canvas { ctx, _ in
                ctx.scaleBy(x: s, y: s)
                for p in paths {
                    ctx.fill(p, with: .linearGradient(fill, startPoint: .zero,
                                                      endPoint: CGPoint(x: AvatarFigure.width, y: AvatarFigure.height)))
                    ctx.stroke(p, with: .color(Color.primary.opacity(0.35)), lineWidth: 1)
                }
            }
        }
        .aspectRatio(AvatarFigure.width / AvatarFigure.height, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

// MARK: - Muscoli

/// Scelta del periodo: cinque pulsanti sulla stessa riga, testo che si adatta allo spazio.
private struct PeriodPicker: View {
    @Binding var selected: StatsPeriod

    var body: some View {
        HStack(spacing: 3) {
            ForEach(StatsPeriod.allCases, id: \.self) { p in
                let on = p == selected
                Button { selected = p } label: {
                    Text(LocalizedStringKey(p.titleKey))
                        .font(.footnote.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.6)
                        .frame(maxWidth: .infinity).padding(.vertical, 8).padding(.horizontal, 4)
                        .foregroundStyle(on ? Theme.onAccent : Color.primary)
                        .background(on ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color.clear), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Color.primary.opacity(0.08), in: Capsule())
    }
}

/// Figure fronte e retro con i muscoli colorati in base all'uso, e sotto l'elenco con le percentuali.
private struct MuscleUsage: View {
    let shares: [MuscleShare]
    @State private var selected: MuscleGroup?

    private func toggle(_ m: MuscleGroup) { selected = selected == m ? nil : m }

    var body: some View {
        let intensity = ProfileStats.intensities(shares)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Spacer()
                ForEach([true, false], id: \.self) { front in
                    VStack(spacing: 4) {
                        MuscleHeatFigure(front: front, intensity: { intensity[$0] }, selected: selected, onTap: toggle)
                            .frame(height: 230)
                        Text(LocalizedStringKey(front ? "profile.front" : "profile.back")).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            if shares.isEmpty {
                Text("profile.muscles.empty").font(.footnote).foregroundStyle(.secondary)
            } else {
                if let m = selected {
                    let p = shares.first { $0.muscle == m }?.percent ?? 0
                    Text(verbatim: String(format: loc("profile.muscles.selected %@ %@"), m.title, percentText(p)))
                        .font(.subheadline.bold()).lineLimit(1).minimumScaleFactor(0.6)
                }
                ForEach(shares, id: \.muscle) { s in
                    Button { toggle(s.muscle) } label: {
                        HStack(spacing: 8) {
                            Text(verbatim: s.muscle.title)
                                .font(.subheadline.weight(selected == s.muscle ? .bold : .regular))
                                .lineLimit(1).minimumScaleFactor(0.6)
                                .frame(width: 110, alignment: .leading)
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.primary.opacity(0.10))
                                    Capsule().fill(Theme.accent)
                                        .frame(width: geo.size.width * min(max(intensity[s.muscle] ?? 0, 0.02), 1))
                                }
                            }
                            .frame(height: 8)
                            Text(verbatim: percentText(s.percent)).font(.subheadline).monospacedDigit()
                                .frame(width: 52, alignment: .trailing)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Grafici

/// Dato riassuntivo del periodo (numero grande con il nome sotto).
private struct StatTile: View {
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(verbatim: value).font(.title3.bold()).lineLimit(1).minimumScaleFactor(0.5)
            Text(title).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10).padding(.horizontal, 6)
        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
    }
}

/// Etichetta breve sotto la colonna (nil = non scritta, per non sovrapporre i testi).
private func shortLabel(_ b: StatsBucket, index: Int, count: Int) -> String? {
    let cal = Calendar.current
    switch b.kind {
    case .hours: return "\(b.value)"
    case .weekday: return cal.shortStandaloneWeekdaySymbols[b.value % 7]   // value 1 = lunedì; i simboli partono da domenica
    case .dayOfMonth: return b.value == 1 || b.value % 5 == 0 ? "\(b.value)" : nil
    case .month: return count <= 12 || index % 3 == 0 ? cal.veryShortStandaloneMonthSymbols[b.value - 1] : nil
    case .year: return "\(b.value)"
    }
}

/// Etichetta completa della colonna toccata ("mer 4 nov", "novembre 2026", "8:00–12:00").
private func fullLabel(_ b: StatsBucket) -> String {
    let start = Date(timeIntervalSince1970: Double(b.start) / 1000)
    let f = DateFormatter()
    switch b.kind {
    case .hours: return "\(b.value):00–\(b.value + ProfileStats.hoursPerBucket):00"
    case .weekday, .dayOfMonth: f.setLocalizedDateFormatFromTemplate("EEEdMMM"); return f.string(from: start)
    case .month: f.setLocalizedDateFormatFromTemplate("LLLLyyyy"); return f.string(from: start)
    case .year: return "\(b.value)"
    }
}

/// Intervallo del periodo sotto il titolo dei muscoli ("Oggi", "2 nov 2026 – 8 nov 2026", ...).
private func rangeText(_ period: StatsPeriod, _ buckets: [StatsBucket]) -> String {
    if period == .day { return loc("profile.range.today") }
    guard let first = buckets.first, let last = buckets.last else { return "" }
    let f = DateFormatter()
    f.dateStyle = .medium
    f.timeStyle = .none
    let a = Date(timeIntervalSince1970: Double(first.start) / 1000)
    let b = Date(timeIntervalSince1970: Double(last.end - 1) / 1000)
    return "\(f.string(from: a)) – \(f.string(from: b))"
}

/// Etichette sotto le colonne, una per colonna (alcune vuote per non sovrapporre i testi).
private struct AxisLabels: View {
    let buckets: [StatsBucket]
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(buckets.enumerated()), id: \.offset) { i, b in
                Text(verbatim: shortLabel(b, index: i, count: buckets.count) ?? "")
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).fixedSize()
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

/// Indice della colonna nel punto toccato.
private func slotIndex(_ x: CGFloat, width: CGFloat, count: Int) -> Int {
    guard count > 0, width > 0 else { return 0 }
    return min(max(Int(x / (width / CGFloat(count))), 0), count - 1)
}

/// Titolo del grafico a sinistra e, a destra, il totale (o il valore della colonna toccata).
private struct ChartHeader: View {
    let title: LocalizedStringKey
    let right: String?
    var body: some View {
        HStack {
            Text(title).font(.subheadline.bold()).lineLimit(1).minimumScaleFactor(0.6)
            Spacer(minLength: 8)
            if let right {
                Text(verbatim: right).font(.footnote).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.6)
            }
        }
    }
}

/// Grafico a colonne di una sola misura (un solo asse, partenza da zero). Toccando una colonna se ne legge il valore
/// sopra il grafico (ritoccando si torna al totale); senza tocco si legge il totale del periodo.
private struct BarChartCard: View {
    let title: LocalizedStringKey
    let buckets: [StatsBucket]
    let values: [Double]
    let format: (Double) -> String
    @State private var selected: Int?

    var body: some View {
        let maxValue = values.max() ?? 0
        let sel = selected.flatMap { $0 < buckets.count && $0 < values.count ? $0 : nil }
        VStack(alignment: .leading, spacing: 8) {
            ChartHeader(title: title, right: sel.map { "\(fullLabel(buckets[$0])): \(format(values[$0]))" }
                        ?? String(format: loc("profile.chart.total %@"), format(values.reduce(0, +))))
            ZStack(alignment: .topLeading) {
                GeometryReader { geo in
                    let w = geo.size.width, h = geo.size.height
                    let slot = buckets.isEmpty ? w : w / CGFloat(buckets.count)
                    let barW = min(slot * 0.6, 18)
                    Canvas { ctx, _ in
                        let grid = Color.primary.opacity(0.12)
                        // Linea di base e linea del massimo (leggere, dietro le colonne).
                        ctx.fill(Path(CGRect(x: 0, y: h - 1, width: w, height: 1)), with: .color(grid))
                        if maxValue > 0 { ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: 1)), with: .color(grid)) }
                        guard maxValue > 0 else { return }
                        for (i, v) in values.enumerated() where v > 0 {
                            let bh = max(CGFloat(v / maxValue) * h, 3)
                            let x = CGFloat(i) * slot + (slot - barW) / 2
                            let alpha = sel == nil || sel == i ? 1.0 : 0.4
                            // Colonna con gli angoli in alto arrotondati, appoggiata alla base.
                            let rect = CGRect(x: x, y: h - bh, width: barW, height: bh)
                            let shape = UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4).path(in: rect)
                            ctx.fill(shape, with: .color(Theme.accent.opacity(alpha)))
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { p in
                        let i = slotIndex(p.x, width: w, count: buckets.count)
                        selected = selected == i ? nil : i
                    }
                }
                if maxValue > 0 {
                    Text(verbatim: format(maxValue)).font(.system(size: 10)).foregroundStyle(.secondary).padding(2)
                }
            }
            .frame(height: 140)
            AxisLabels(buckets: buckets)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .onChange(of: buckets) { selected = nil }
    }
}

/// Andamento del peso corporeo: punti dove c'è una pesata, uniti da una linea. Asse dal minimo al massimo del periodo.
private struct WeightChartCard: View {
    let buckets: [StatsBucket]
    let weights: [Double?]
    let change: Double?
    @State private var selected: Int?

    var body: some View {
        let points: [(Int, Double)] = weights.enumerated().compactMap { i, w in w.map { (i, $0) } }
        let sel = selected.flatMap { $0 < weights.count && weights[$0] != nil ? $0 : nil }
        let right: String? = {
            if let i = sel, let w = weights[i] { return "\(fullLabel(buckets[i])): \(num1(w)) kg" }
            if let change { return String(format: loc("profile.chart.weightChange %@"), (change > 0 ? "+" : "") + num1(change)) }
            return nil
        }()
        VStack(alignment: .leading, spacing: 8) {
            ChartHeader(title: "profile.chart.weight", right: right)
            if points.isEmpty {
                Text("profile.chart.weightEmpty").font(.footnote).foregroundStyle(.secondary)
            } else {
                let lo = points.map(\.1).min() ?? 0, hi = points.map(\.1).max() ?? 0
                let pad = max((hi - lo) * 0.15, 0.5)
                let yMin = lo - pad, yMax = hi + pad
                ZStack(alignment: .topLeading) {
                    GeometryReader { geo in
                        let w = geo.size.width, h = geo.size.height
                        let slot = buckets.isEmpty ? w : w / CGFloat(buckets.count)
                        let pos: (Int, Double) -> CGPoint = { i, v in
                            CGPoint(x: CGFloat(i) * slot + slot / 2, y: h * CGFloat(1 - (v - yMin) / (yMax - yMin)))
                        }
                        Canvas { ctx, _ in
                            ctx.fill(Path(CGRect(x: 0, y: h - 1, width: w, height: 1)), with: .color(Color.primary.opacity(0.12)))
                            if points.count > 1 {
                                var line = Path()
                                line.move(to: pos(points[0].0, points[0].1))
                                for p in points.dropFirst() { line.addLine(to: pos(p.0, p.1)) }
                                ctx.stroke(line, with: .color(Theme.accent), lineWidth: 2)
                            }
                            for (i, v) in points {
                                let c = pos(i, v)
                                let r: CGFloat = sel == i ? 6 : 4
                                // Anello del colore di fondo: il punto si stacca dalla linea.
                                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r - 2, y: c.y - r - 2, width: 2 * (r + 2), height: 2 * (r + 2))),
                                         with: .color(Theme.bgTop))
                                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(Theme.accent))
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { p in
                            let i = slotIndex(p.x, width: w, count: buckets.count)
                            selected = selected == i || weights[i] == nil ? nil : i
                        }
                    }
                    VStack(alignment: .leading) {
                        Text(verbatim: "\(num1(hi)) kg")
                        Spacer()
                        Text(verbatim: "\(num1(lo)) kg")
                    }
                    .font(.system(size: 10)).foregroundStyle(.secondary).padding(2)
                    .allowsHitTesting(false)
                }
                .frame(height: 140)
                AxisLabels(buckets: buckets)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .onChange(of: buckets) { selected = nil }
    }
}
