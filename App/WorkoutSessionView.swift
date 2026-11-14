import SwiftUI
import SwiftData
import MyGymHelperCore

/// Cosa avviare: esercizio (nil = conteggio libero), parametri ed eventuale esercizio di un elenco.
/// `replacing`/`replacingParameters`: esercizio originale (e i suoi parametri) quando si fa un esercizio alternativo,
/// solo per questa sessione (con "Sostituisci nell'elenco" non c'è: è l'esercizio dell'elenco).
struct SessionTarget: Hashable, Identifiable {
    let id = UUID()
    var exercise: CatalogExercise?
    var parameters: WorkoutParameters
    var listID: UUID? = nil
    var itemID: UUID? = nil
    var replacing: CatalogExercise? = nil
    var replacingParameters: WorkoutParameters? = nil
    /// Asse del movimento scelto per questa sessione (esercizio alternativo); nil = dalla riga o dal catalogo.
    var movement: MovementAxis? = nil

    static func == (a: SessionTarget, b: SessionTarget) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Sessione di un esercizio. Prima la schermata "Pronto" (dove mettere il telefono: si parte solo quando l'utente
/// tocca "Avvia"), poi la spiegazione (sempre, con "Salta"), il conteggio, la pausa e il riepilogo; l'esercizio
/// dell'elenco diventa verde e, se richiesto, si propone il successivo (di nuovo dalla schermata "Pronto").
/// Il controller (sensori, voce) si crea solo al tocco di "Avvia", una volta per esercizio.
struct WorkoutSessionView: View {
    @State private var target: SessionTarget
    @State private var position: SensorPosition
    @State private var parameters: WorkoutParameters
    @State private var controller: SessionController?
    /// Scelta dell'esercizio alternativo aperta.
    @State private var showAlternative = false
    @Environment(CatalogStore.self) private var catalog

    init(target: SessionTarget) {
        _target = State(initialValue: target)
        _position = State(initialValue: WorkoutListLogic.suggestedPosition(target.exercise))
        _parameters = State(initialValue: target.parameters)
    }

    var body: some View {
        if let controller {
            SessionContent(controller: controller, target: target,
                           // Freccia "indietro" durante la spiegazione: si torna a "Pronto" (la sessione si chiude)
                           onBack: { self.controller = nil }) { next in
                // Esercizio successivo: si torna alla schermata "Pronto" (la sessione finita si chiude da sola).
                self.controller = nil
                target = next
                position = WorkoutListLogic.suggestedPosition(next.exercise)
                parameters = next.parameters
            }
            .id(target.id)
        } else {
            ReadyView(exercise: target.exercise, position: $position, parameters: $parameters,
                      replacing: target.replacing, axis: axis,
                      onAlternative: target.exercise == nil ? nil : { showAlternative = true },
                      onRestore: target.replacing == nil ? nil : restoreOriginal) {
                let settings = AppSettings.shared
                controller = SessionController(position: position, tuning: settings.tuning(for: position),
                                               parameters: parameters.clamped(), exercise: target.exercise,
                                               options: .fromDefaults(), readAloud: settings.explainExercise,
                                               axis: axis,
                                               lastSetNotice: { [catalog, listID = target.listID, itemID = target.itemID] in
                    // Prossimo esercizio dell'elenco (o fine della giornata), letto dallo stato attuale dell'elenco.
                    WorkoutListLogic.lastSetNotice(WorkoutListStore.shared.list(listID)?.items, currentItemID: itemID) {
                        catalog.exercise(id: $0)
                    }
                })
            }
            .navigationDestination(isPresented: $showAlternative) {
                if let original = target.replacing ?? target.exercise {
                    // Scelta + parametri (editor); poi solo per questa sessione o definitivo nell'elenco
                    AddExerciseView(alternativeFor: original,
                                    originalParameters: target.replacingParameters ?? target.parameters,
                                    canReplace: target.listID != nil && target.itemID != nil) { picked, p, axis, permanent in
                        if permanent { replaceInList(picked, parameters: p, movement: axis) }
                        else { useAlternative(picked, instead: original, parameters: p, movement: axis) }
                    }
                }
            }
        }
    }

    /// "Solo per questa sessione": si chiudono editor e scelta e si torna a "Pronto" con l'alternativa e i parametri
    /// scelti nell'editor, con "Al posto di" e "Torna a …". L'elenco non cambia.
    private func useAlternative(_ picked: CatalogExercise, instead original: CatalogExercise, parameters chosen: WorkoutParameters,
                                movement: MovementAxis) {
        let originalParameters = target.replacingParameters ?? target.parameters
        target = SessionTarget(exercise: picked, parameters: chosen,
                               listID: target.listID, itemID: target.itemID,
                               replacing: original, replacingParameters: originalParameters, movement: movement)
        position = WorkoutListLogic.suggestedPosition(picked)
        parameters = target.parameters
        showAlternative = false
    }

    /// "Sostituisci nell'elenco" (confermato nell'editor): la riga dell'elenco prende il nuovo esercizio e i parametri
    /// scelti; "Pronto" riparte con l'esercizio dell'elenco (niente "Al posto di", niente "Torna a").
    private func replaceInList(_ picked: CatalogExercise, parameters chosen: WorkoutParameters, movement: MovementAxis) {
        guard let listID = target.listID, let itemID = target.itemID else { return }
        let store = WorkoutListStore.shared
        if let item = store.list(listID)?.items.first(where: { $0.id == itemID }) {
            var replaced = WorkoutListLogic.replaceExercise(item, exerciseID: picked.id, parameters: chosen)
            replaced.movement = MovementRules.override(picked, movement)   // asse sulla riga solo se diverso dal catalogo
            store.updateItem(replaced, in: listID)
        }
        target = SessionTarget(exercise: picked, parameters: chosen, listID: listID, itemID: itemID, movement: movement)
        position = WorkoutListLogic.suggestedPosition(picked)
        parameters = chosen
        showAlternative = false
    }

    /// Asse del movimento da contare: quello scelto per la sessione (esercizio alternativo), altrimenti quello della
    /// riga dell'elenco o del catalogo (la scelta della riga non vale per un esercizio diverso). Conteggio libero: su/giù.
    private var axis: MovementAxis {
        if let m = target.movement { return m }
        let item = WorkoutListStore.shared.list(target.listID)?.items.first { $0.id == target.itemID }
        return MovementRules.forItem(target.exercise, item)
    }

    /// "Torna a …": di nuovo l'esercizio originale dell'elenco.
    private func restoreOriginal() {
        guard let original = target.replacing else { return }
        target = SessionTarget(exercise: original, parameters: target.replacingParameters ?? target.parameters,
                               listID: target.listID, itemID: target.itemID)
        position = WorkoutListLogic.suggestedPosition(original)
        parameters = target.parameters
    }
}

/// "Pronto": esercizio e parametri, dove mettere il telefono, calibrazione; il conteggio parte solo con "Avvia".
private struct ReadyView: View {
    let exercise: CatalogExercise?
    @Binding var position: SensorPosition
    @Binding var parameters: WorkoutParameters
    /// Esercizio dell'elenco sostituito da questo (esercizio alternativo), nil altrimenti.
    var replacing: CatalogExercise? = nil
    /// Asse del movimento che si conterà.
    var axis: MovementAxis = .upDown
    /// "Fai esercizio alternativo" (solo con un esercizio).
    var onAlternative: (() -> Void)? = nil
    /// "Torna a …" (solo per un esercizio alternativo). "Sostituisci nell'elenco" è passato nell'editor dei parametri.
    var onRestore: (() -> Void)? = nil
    var onStart: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let exercise {
                    ScreenHeader(symbol: "play.circle.fill", title: "ready.title", subtitle: LocalizedStringKey(exercise.name))
                } else {
                    ScreenHeader(symbol: "play.circle.fill", title: "ready.title", subtitle: "setup.noExercise")
                }
                VStack(alignment: .leading, spacing: 14) {
                    if let exercise {
                        // Esercizio alternativo: quello dell'elenco che sostituisce, solo per questa sessione.
                        if let replacing {
                            Label("alternative.instead \(replacing.name)", systemImage: "arrow.left.arrow.right")
                                .appType(.secondary, weight: .semibold).foregroundStyle(Theme.accentSoft)
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                        Text(verbatim: exercise.primary.map(\.title).joined(separator: ", "))
                            .appType(.secondary).foregroundStyle(.secondary)
                        Text(verbatim: parameters.summaryText).appType(.cardTitle)
                        Text(verbatim: String(format: NSLocalizedString("movement.counted %@", comment: ""),
                                              NSLocalizedString(axis.titleKey, comment: "")))
                            .appType(.caption).foregroundStyle(.secondary)
                    } else {
                        // Conteggio libero: serie, ripetizioni e pausa si scelgono qui.
                        CounterRow(title: "counter.sets", value: $parameters.sets, range: WorkoutParameters.setsRange)
                        CounterRow(title: "counter.reps", value: $parameters.reps, range: WorkoutParameters.repsRange)
                        CounterRow(title: "counter.rest", value: $parameters.restSeconds, range: WorkoutParameters.restRange, step: 15)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard()

                // Foto della posizione iniziale e finale (come in Android)
                if let exercise, !exercise.images.isEmpty { ExercisePhotosCard(exercise: exercise) }

                // Non si può fare l'esercizio (macchina occupata, attrezzo che manca...): se ne sceglie un altro per questa sessione.
                if let onAlternative {
                    Button(action: onAlternative) {
                        Label("alternative.button", systemImage: "arrow.left.arrow.right")
                            .lineLimit(1).minimumScaleFactor(0.7).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass).appType(.button)
                    .tint(Theme.accent)
                }
                if let replacing, let onRestore {
                    Button(action: onRestore) {
                        Text("alternative.restore \(replacing.name)").lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .appType(.caption).tint(Theme.accent)
                }
                PositionPicker(selected: $position)
                CalibrationSummary(position: position)
                Label("workout.pocketWarning", systemImage: "iphone.gen3.radiowaves.left.and.right")
                    .appType(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: onStart) {
                    Label("ready.start", systemImage: "play.fill")
                        .appType(.cta).frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .buttonStyle(.glassProminent).appType(.button)
                .tint(Theme.accent)
            }
            .padding(20)
        }
        .appScreen()
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SessionContent: View {
    let controller: SessionController
    let target: SessionTarget
    /// Torna alla schermata "Pronto" (solo durante la spiegazione, prima della prima serie).
    var onBack: () -> Void
    var onNext: (SessionTarget) -> Void
    @Environment(CatalogStore.self) private var catalog
    @State private var showStop = false
    @State private var saved = false
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(SubscriptionManager.self) private var subscriptions
    @AppStorage(ConsentStore.grantedAtKey) private var consentAt = 0.0
    private let timer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            switch controller.phase {
            case .notStarted where controller.explaining:
                explanationView
            case .notStarted, .working:
                workingView
            case .resting(let afterSet, let remaining):
                restView(afterSet: afterSet, remaining: remaining)
            case .finished:
                summary
            }
        }
        .padding(20)
        .appScreen()
        .navigationBarBackButtonHidden(controller.phase != .finished)
        // Durante la spiegazione (prima della prima serie) c'e' la freccia "indietro", che riporta a "Pronto"
        // (per esempio per cambiare la posizione del telefono). Nel conteggio e nella pausa resta nascosta:
        // si esce con "Termina allenamento". (9 novembre 2026)
        .toolbar {
            if controller.phase == .notStarted && controller.explaining {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onBack) { Image(systemName: "chevron.backward") }
                        .accessibilityLabel(Text("session.backToReady"))
                }
            }
        }
        .onAppear { controller.start() }
        .onDisappear { controller.end() }
        .onReceive(timer) { _ in controller.tick() }
        .onChange(of: controller.phase) { _, new in if new == .finished { save() } }
        .sheet(isPresented: $showStop) {
            StopSheet(target: controller.targetReps, initial: controller.currentReps) { done in
                controller.stop(doneReps: done)
            }
            .presentationDetents([.medium])
        }
    }

    private var progressBar: some View {
        HStack(spacing: 8) {
            ForEach(1...controller.totalSets, id: \.self) { n in
                Capsule()
                    .fill(n <= controller.records.count ? AnyShapeStyle(Theme.accentGradient)
                          : n == controller.currentSetNumber ? AnyShapeStyle(Theme.accent.opacity(0.55))
                          : AnyShapeStyle(Color.primary.opacity(0.12)))
                    .frame(height: 8)
            }
        }
    }

    private var workingView: some View {
        VStack(spacing: 26) {
            progressBar
            VStack(spacing: 4) {
                if let exercise = controller.exercise {
                    Text(verbatim: exercise.name).appType(.sectionTitle, weight: .bold, uppercase: true)
                }
                Text("session.set \(controller.currentSetNumber) \(controller.totalSets)")
                    .appType(.cardTitle).foregroundStyle(.secondary)
                // Peso della serie in corso (serie diverse: cambia da una serie all'altra).
                let setWeight = controller.currentTarget.weightKg
                if setWeight > 0 {
                    Text(verbatim: setWeight.kgText)
                        // "80 KG": più grande con le serie diverse (cambia da una serie all'altra)
                        .appType(controller.isVaried ? .stat : .metric, uppercase: true).foregroundStyle(Theme.accentSoft)
                }
            }

            RepRing(count: controller.currentReps, target: controller.targetReps)

            if !controller.motion.isAvailable {
                Label("session.noSensor", systemImage: "exclamationmark.triangle.fill")
                    .appType(.secondary).foregroundStyle(.orange).glassCard(padding: 14)
            } else if controller.motion.isCalibrating {
                Label("session.calibrating", systemImage: "waveform.path")
                    .appType(.secondary).glassCard(padding: 14)
            } else if controller.motion.lowConfidence {
                Label("workout.pocketWarning", systemImage: "exclamationmark.triangle.fill")
                    .appType(.secondary).foregroundStyle(.orange).glassCard(padding: 14)
            }

            Spacer(minLength: 0)

            // Asse del movimento: se il conteggio non prende le ripetizioni si passa all'altro (resto della sessione).
            if controller.motion.isAvailable {
                Text(verbatim: String(format: NSLocalizedString("movement.counted %@", comment: ""),
                                      NSLocalizedString(controller.axis.titleKey, comment: "")))
                    .appType(.caption).foregroundStyle(.secondary)
                Button { controller.toggleAxis() } label: {
                    // Passa all'asse successivo: su/giù → sinistra/destra → avanti/indietro → su/giù
                    Label(LocalizedStringKey("movement.switchTo." + controller.axis.other.rawValue),
                          systemImage: controller.axis.other.symbol)
                        .appType(.cardTitle).lineLimit(1).minimumScaleFactor(0.7).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.glass).appType(.button)
            }

            Button { showStop = true } label: {
                Label("session.stopped", systemImage: "hand.raised.fill")
                    .appType(.cardTitle).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.glass).appType(.button).tint(.red)

            // Tutte le ripetizioni della serie fatte (se il conteggio non le ha prese tutte): serie completa, senza scrivere il numero.
            Button { controller.stop(doneReps: controller.targetReps) } label: {
                Label("session.setDone", systemImage: "checkmark.circle.fill")
                    .appType(.cardTitle).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.glass).appType(.button)

            Button("session.end") { controller.endEarly() }
                .appType(.secondary).foregroundStyle(.secondary)
        }
    }

    private func restView(afterSet: Int, remaining: Int) -> some View {
        VStack(spacing: 26) {
            progressBar
            Text("session.rest").appType(.cardTitle).foregroundStyle(.secondary)
            CountdownRing(remaining: remaining, total: controller.restSeconds)
            Text("session.next \(afterSet + 1)").appType(.sectionTitle, weight: .bold)
            // Prossima serie: ripetizioni e peso (con le serie diverse cambiano da una serie all'altra).
            let next = controller.target(afterSet + 1)
            Text(verbatim: String(localized: "session.nextTarget \(next.reps)") + (next.weightKg > 0 ? " · " + next.weightKg.kgText : ""))
                .appType(.cardTitle).foregroundStyle(Theme.accentSoft)
            Spacer(minLength: 0)
            Button { controller.skipRest() } label: {
                Label("session.skipRest", systemImage: "forward.fill")
                    .appType(.cardTitle).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent).appType(.button).tint(Theme.accent)
            if controller.hasExplanation {
                Button { controller.explain() } label: {
                    Label("explain.again", systemImage: "person.wave.2.fill").lineLimit(1).frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass).appType(.button)
            }
            Button("session.end") { controller.endEarly() }
                .appType(.secondary).foregroundStyle(.secondary)
        }
    }

    /// Spiegazione prima della prima serie: passaggi numerati (quello letto e' evidenziato), conto alla rovescia.
    private var explanationView: some View {
        let speaking = VoiceEngine.shared.speakingID
        return VStack(alignment: .leading, spacing: 16) {
            Text("explain.title").appType(.cardTitle).foregroundStyle(.secondary)
            if let exercise = controller.exercise {
                Text(verbatim: exercise.name).appType(.screenTitle, weight: .bold)
                Text(verbatim: exercise.primary.map(\.title).joined(separator: ", ")).appType(.secondary).foregroundStyle(.secondary)
                ScrollView {
                    VStack(spacing: 10) {
                        // Foto della posizione iniziale e finale (se ci sono), sopra i passaggi
                        if !exercise.images.isEmpty {
                            HStack(spacing: 10) {
                                ForEach(Array(exercise.images.prefix(2).enumerated()), id: \.offset) { _, link in
                                    Color.primary.opacity(0.1)
                                        .aspectRatio(4 / 3, contentMode: .fit)
                                        .overlay {
                                            AsyncImage(url: URL(string: link)) { phase in
                                                if let image = phase.image {
                                                    image.resizable().scaledToFill()
                                                } else {
                                                    Image(systemName: "dumbbell.fill").appFont(.title2).foregroundStyle(.secondary)
                                                }
                                            }
                                        }
                                        .clipShape(RoundedRectangle(cornerRadius: 16))
                                        .frame(maxWidth: .infinity)
                                }
                            }
                        }
                        ForEach(Array(exercise.steps.enumerated()), id: \.offset) { i, step in
                            HStack(alignment: .top, spacing: 12) {
                                Text(verbatim: "\(i + 1)").appType(.cardTitle).foregroundStyle(Theme.accent)
                                Text(verbatim: step).frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(14)
                            .background(speaking == "step-\(i)" ? Theme.accent.opacity(0.28) : Color.primary.opacity(0.07),
                                        in: RoundedRectangle(cornerRadius: 18))
                        }
                    }
                }
            }
            if let countdown = controller.startCountdown {
                Text("explain.startsIn \(countdown)").appType(.stat, weight: .bold).frame(maxWidth: .infinity)
            }
            Button { controller.startNow() } label: {
                Label("explain.startNow", systemImage: "play.fill").appType(.cta).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent).appType(.button).tint(Theme.accent)
            Button { controller.explain() } label: {
                Label("explain.again", systemImage: "person.wave.2.fill").lineLimit(1).frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass).appType(.button)
        }
    }

    /// Riepilogo: con un elenco si torna all'elenco o, se richiesto, si propone l'esercizio successivo.
    @ViewBuilder
    private var summary: some View {
        let list = WorkoutListStore.shared.list(target.listID)
        let next = (list?.autoNext ?? false) ? list.flatMap { WorkoutListLogic.nextPending($0.items, after: target.itemID) } : nil
        let nextExercise = next.flatMap { catalog.exercise(id: $0.exerciseID) }
        if let list, let next, let nextExercise {
            SessionSummaryView(controller: controller, tier: subscriptions.tier, saved: saved, doneKey: "workout.backToList",
                               listID: list.id, nextName: nextExercise.name,
                               onNext: { onNext(SessionTarget(exercise: nextExercise, parameters: next.parameters, listID: list.id, itemID: next.id)) }) {
                dismiss()
            }
        } else {
            SessionSummaryView(controller: controller, tier: subscriptions.tier, saved: saved,
                               doneKey: list != nil ? "workout.backToList" : "session.done", listID: list?.id) { dismiss() }
        }
    }

    /// Lo storico contiene dati sulla salute: si salva solo se l'utente ha dato il consenso.
    /// L'esercizio dell'elenco svolto (almeno una serie) diventa verde, anche senza consenso (solo in memoria).
    private func save() {
        if let listID = target.listID, let itemID = target.itemID, !controller.records.isEmpty {
            // Con le calorie stimate delle serie fatte (sostituiscono quelle della volta prima)
            let kcal = CalorieEstimator.exerciseKcal(sets: controller.records, restSeconds: controller.restSeconds,
                                                     isCompound: controller.exercise?.isCompound ?? false,
                                                     bodyWeightKg: ProfileData.bodyWeightKg())
            WorkoutListStore.shared.setDone(itemID, in: listID, kcal: kcal)
        }
        guard !saved, consentAt > 0, !controller.records.isEmpty else { return }
        saved = true
        context.insert(controller.makeRecord())
        try? context.save()
        // Apple Salute: solo se l'utente l'ha collegata (Info) e con il consenso ai dati sanitari.
        let start = controller.startedAt, name = controller.exercise?.name
        // Apple Salute: collegamento nascosto e spento per ora (AppFeatures.healthSyncEnabled)
        if AppFeatures.healthSyncEnabled {
            Task { await HealthKitService.shared.saveWorkoutIfEnabled(start: start, end: Date(), title: name) }
        }
    }
}

/// Anello della pausa: si svuota man mano che il tempo passa.
struct CountdownRing: View {
    let remaining: Int
    let total: Int

    private var progress: Double { total > 0 ? Double(remaining) / Double(total) : 0 }

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.10), lineWidth: 22)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Theme.accentGradient, style: StrokeStyle(lineWidth: 22, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.3), value: progress)
            Text("\(remaining)")
                .appType(.timer)            // Oswald 88, fuori dalla riduzione del 20%
                .contentTransition(.numericText())
        }
        .frame(width: 270, height: 270)
    }
}

/// Foglio per dire "mi sono fermato" e indicare quante ripetizioni sono state fatte.
struct StopSheet: View {
    let target: Int
    var onConfirm: (Int) -> Void
    @State private var reps: Int
    @Environment(\.dismiss) private var dismiss

    init(target: Int, initial: Int, onConfirm: @escaping (Int) -> Void) {
        self.target = target
        self.onConfirm = onConfirm
        _reps = State(initialValue: min(initial, target))
    }

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 22) {
                Text("stop.title").appType(.sectionTitle, weight: .bold)
                CounterRow(title: "counter.reps", value: $reps, range: 0...target).glassCard()
                Button {
                    onConfirm(reps); dismiss()
                } label: {
                    Text("stop.confirm").appType(.cardTitle).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent).appType(.button).tint(Theme.accent)
                Button("info.cancel") { dismiss() }.buttonStyle(.glass).appType(.button)
            }
            .padding(24)
        }
    }
}
