import SwiftUI
import SwiftData
import MyGymHelperCore

/// Cosa avviare: esercizio (nil = conteggio libero), parametri ed eventuale esercizio di un elenco.
/// `replacing`/`replacingParameters`: esercizio originale (e i suoi parametri) quando si fa un esercizio alternativo,
/// solo per questa sessione.
struct SessionTarget: Hashable, Identifiable {
    let id = UUID()
    var exercise: CatalogExercise?
    var parameters: WorkoutParameters
    var listID: UUID? = nil
    var itemID: UUID? = nil
    var replacing: CatalogExercise? = nil
    var replacingParameters: WorkoutParameters? = nil

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
            SessionContent(controller: controller, target: target) { next in
                // Esercizio successivo: si torna alla schermata "Pronto" (la sessione finita si chiude da sola).
                self.controller = nil
                target = next
                position = WorkoutListLogic.suggestedPosition(next.exercise)
                parameters = next.parameters
            }
            .id(target.id)
        } else {
            ReadyView(exercise: target.exercise, position: $position, parameters: $parameters,
                      replacing: target.replacing,
                      onAlternative: target.exercise == nil ? nil : { showAlternative = true },
                      onRestore: target.replacing == nil ? nil : restoreOriginal,
                      onMakePermanent: target.replacing != nil && target.listID != nil && target.itemID != nil ? makePermanent : nil) {
                let settings = AppSettings.shared
                controller = SessionController(position: position, tuning: settings.tuning(for: position),
                                               parameters: parameters.clamped(), exercise: target.exercise,
                                               options: .fromDefaults(), readAloud: settings.explainExercise,
                                               lastSetNotice: { [catalog, listID = target.listID, itemID = target.itemID] in
                    // Prossimo esercizio dell'elenco (o fine della giornata), letto dallo stato attuale dell'elenco.
                    WorkoutListLogic.lastSetNotice(WorkoutListStore.shared.list(listID)?.items, currentItemID: itemID) {
                        catalog.exercise(id: $0)
                    }
                })
            }
            .navigationDestination(isPresented: $showAlternative) {
                if let original = target.replacing ?? target.exercise {
                    AddExerciseView(alternativeFor: original) { picked in useAlternative(picked, instead: original) }
                }
            }
        }
    }

    /// Esercizio alternativo scelto: si torna alla schermata "Pronto" con l'alternativa, solo per questa sessione
    /// (stesse serie, ripetizioni e pausa; senza peso se è a corpo libero). L'elenco non cambia.
    private func useAlternative(_ picked: CatalogExercise, instead original: CatalogExercise) {
        let originalParameters = target.replacingParameters ?? target.parameters
        target = SessionTarget(exercise: picked,
                               parameters: WorkoutListLogic.alternativeParameters(originalParameters, alternative: picked),
                               listID: target.listID, itemID: target.itemID,
                               replacing: original, replacingParameters: originalParameters)
        position = WorkoutListLogic.suggestedPosition(picked)
        parameters = target.parameters
        showAlternative = false
    }

    /// "Sostituisci nell'elenco": l'alternativa diventa definitiva (stessa riga, nuovo esercizio e parametri di adesso);
    /// da qui in poi è l'esercizio dell'elenco, senza più "Al posto di".
    private func makePermanent() {
        guard let exercise = target.exercise, let listID = target.listID, let itemID = target.itemID else { return }
        let store = WorkoutListStore.shared
        if let item = store.list(listID)?.items.first(where: { $0.id == itemID }) {
            store.updateItem(WorkoutListLogic.replaceExercise(item, exerciseID: exercise.id, parameters: parameters), in: listID)
        }
        target = SessionTarget(exercise: exercise, parameters: parameters, listID: listID, itemID: itemID)
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
    /// "Fai esercizio alternativo" (solo con un esercizio).
    var onAlternative: (() -> Void)? = nil
    /// "Torna a …" (solo per un esercizio alternativo).
    var onRestore: (() -> Void)? = nil
    /// "Sostituisci nell'elenco" (solo per l'alternativa di un esercizio dell'elenco), con conferma.
    var onMakePermanent: (() -> Void)? = nil
    var onStart: () -> Void
    @State private var confirmPermanent = false

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
                                .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accentSoft)
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                        Text(verbatim: exercise.primary.map(\.title).joined(separator: ", "))
                            .font(.subheadline).foregroundStyle(.secondary)
                        Text(verbatim: parameters.summaryText).font(.headline)
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
                    .buttonStyle(.glass)
                    .tint(Theme.accent)
                }
                // Alternativa definitiva: l'esercizio dell'elenco viene sostituito (con conferma).
                if replacing != nil, onMakePermanent != nil {
                    Button { confirmPermanent = true } label: {
                        Label("alternative.makePermanent", systemImage: "checkmark")
                            .lineLimit(1).minimumScaleFactor(0.7).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .tint(Theme.accent)
                }
                if let replacing, let onRestore {
                    Button(action: onRestore) {
                        Text("alternative.restore \(replacing.name)").lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .font(.footnote).tint(Theme.accent)
                }
                PositionPicker(selected: $position)
                CalibrationSummary(position: position)
                Label("workout.pocketWarning", systemImage: "iphone.gen3.radiowaves.left.and.right")
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: onStart) {
                    Label("ready.start", systemImage: "play.fill")
                        .font(.title3.bold()).frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.accent)
            }
            .padding(20)
        }
        .appScreen()
        .navigationBarTitleDisplayMode(.inline)
        .alert("alternative.permanentTitle", isPresented: $confirmPermanent) {
            Button("alternative.permanentConfirm") { onMakePermanent?() }
            Button("info.cancel", role: .cancel) {}
        } message: {
            if let replacing, let exercise {
                Text("alternative.permanentBody \(replacing.name) \(exercise.name)")
            }
        }
    }
}

private struct SessionContent: View {
    let controller: SessionController
    let target: SessionTarget
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
                    Text(verbatim: exercise.name).font(.title3.bold())
                }
                Text("session.set \(controller.currentSetNumber) \(controller.totalSets)")
                    .font(.headline).foregroundStyle(.secondary)
                // Peso della serie in corso (serie diverse: cambia da una serie all'altra).
                let setWeight = controller.currentTarget.weightKg
                if setWeight > 0 {
                    Text(verbatim: setWeight.kgText)
                        .font(controller.isVaried ? .title3.bold() : .subheadline).foregroundStyle(Theme.accentSoft)
                }
            }

            RepRing(count: controller.currentReps, target: controller.targetReps)

            if !controller.motion.isAvailable {
                Label("session.noSensor", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline).foregroundStyle(.orange).glassCard(padding: 14)
            } else if controller.motion.isCalibrating {
                Label("session.calibrating", systemImage: "waveform.path")
                    .font(.subheadline).glassCard(padding: 14)
            } else if controller.motion.lowConfidence {
                Label("workout.pocketWarning", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline).foregroundStyle(.orange).glassCard(padding: 14)
            }

            Spacer(minLength: 0)

            Button { showStop = true } label: {
                Label("session.stopped", systemImage: "hand.raised.fill")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.glass).tint(.red)

            // Tutte le ripetizioni della serie fatte (se il conteggio non le ha prese tutte): serie completa, senza scrivere il numero.
            Button { controller.stop(doneReps: controller.targetReps) } label: {
                Label("session.setDone", systemImage: "checkmark.circle.fill")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.glass)

            Button("session.end") { controller.endEarly() }
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private func restView(afterSet: Int, remaining: Int) -> some View {
        VStack(spacing: 26) {
            progressBar
            Text("session.rest").font(.headline).foregroundStyle(.secondary)
            CountdownRing(remaining: remaining, total: controller.restSeconds)
            Text("session.next \(afterSet + 1)").font(.title3.bold())
            // Prossima serie: ripetizioni e peso (con le serie diverse cambiano da una serie all'altra).
            let next = controller.target(afterSet + 1)
            Text(verbatim: String(localized: "session.nextTarget \(next.reps)") + (next.weightKg > 0 ? " · " + next.weightKg.kgText : ""))
                .font(.headline).foregroundStyle(Theme.accentSoft)
            Spacer(minLength: 0)
            Button { controller.skipRest() } label: {
                Label("session.skipRest", systemImage: "forward.fill")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent).tint(Theme.accent)
            if controller.hasExplanation {
                Button { controller.explain() } label: {
                    Label("explain.again", systemImage: "person.wave.2.fill").lineLimit(1).frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
            }
            Button("session.end") { controller.endEarly() }
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    /// Spiegazione prima della prima serie: passaggi numerati (quello letto e' evidenziato), conto alla rovescia.
    private var explanationView: some View {
        let speaking = VoiceEngine.shared.speakingID
        return VStack(alignment: .leading, spacing: 16) {
            Text("explain.title").font(.headline).foregroundStyle(.secondary)
            if let exercise = controller.exercise {
                Text(verbatim: exercise.name).font(.title.bold())
                Text(verbatim: exercise.primary.map(\.title).joined(separator: ", ")).font(.subheadline).foregroundStyle(.secondary)
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
                                                    Image(systemName: "dumbbell.fill").font(.title2).foregroundStyle(.secondary)
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
                                Text(verbatim: "\(i + 1)").font(.headline).foregroundStyle(Theme.accent)
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
                Text("explain.startsIn \(countdown)").font(.title2.bold()).frame(maxWidth: .infinity)
            }
            Button { controller.startNow() } label: {
                Label("explain.startNow", systemImage: "play.fill").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent).tint(Theme.accent)
            Button { controller.explain() } label: {
                Label("explain.again", systemImage: "person.wave.2.fill").lineLimit(1).frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
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
        Task { await HealthKitService.shared.saveWorkoutIfEnabled(start: start, end: Date(), title: name) }
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
                .font(.system(size: 92, weight: .heavy, design: .rounded).monospacedDigit())
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
                Text("stop.title").font(.title3.bold())
                CounterRow(title: "counter.reps", value: $reps, range: 0...target).glassCard()
                Button {
                    onConfirm(reps); dismiss()
                } label: {
                    Text("stop.confirm").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent).tint(Theme.accent)
                Button("info.cancel") { dismiss() }.buttonStyle(.glass)
            }
            .padding(24)
        }
    }
}
