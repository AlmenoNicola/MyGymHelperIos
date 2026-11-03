import SwiftUI
import MyGymHelperCore

extension SensorPosition: Identifiable {
    var id: String { rawValue }
    var titleKey: LocalizedStringKey { LocalizedStringKey("position." + rawValue) }
    var hintKey: LocalizedStringKey { LocalizedStringKey("position." + rawValue + ".hint") }
    var symbol: String {
        switch self {
        case .armUpper, .armForearm: return "figure.strengthtraining.traditional"
        case .legThigh, .legShin: return "figure.walk"
        case .abs: return "figure.core.training"
        }
    }
}

/// Scelta di dove si fissa il telefono (5 posizioni): ognuna ha la sua calibrazione e sensibilita'.
struct PositionPicker: View {
    @Binding var selected: SensorPosition

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("position.title").font(.headline)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(SensorPosition.allCases) { item in
                    Button { withAnimation(.snappy) { selected = item } } label: {
                        HStack(spacing: 10) {
                            Image(systemName: item.symbol).font(.title3.weight(.semibold))
                            Text(item.titleKey).font(.subheadline.bold()).multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 16)
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(selected == item ? Color.white : Color.secondary)
                        .background {
                            if selected == item {
                                RoundedRectangle(cornerRadius: 22).fill(Theme.accentGradient)
                            } else {
                                RoundedRectangle(cornerRadius: 22).fill(Color.primary.opacity(0.07))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(selected.hintKey).font(.caption).foregroundStyle(.secondary)
        }
        .sensoryFeedback(.selection, trigger: selected)
    }
}

/// Stato della calibrazione della posizione scelta, con il collegamento alla schermata di calibrazione.
struct CalibrationSummary: View {
    let position: SensorPosition
    private var settings: AppSettings { AppSettings.shared }

    var body: some View {
        let tuning = settings.tuning(for: position)
        NavigationLink { CalibrationView(initial: position) } label: {
            HStack(spacing: 14) {
                Image(systemName: "slider.horizontal.3").foregroundStyle(Theme.accent).frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("calib.open").font(.headline)
                    HStack(spacing: 4) {
                        Text(tuning.isCalibrated ? "calib.setupCalibrated" : "calib.setupDefault")
                        if tuning.sensitivity != 1 {
                            Text(verbatim: "·")
                            Text("calib.setupSensitivity \(tuning.sensitivity.formatted(.number.precision(.fractionLength(1))))")
                        }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.secondary)
            }
            .glassCard(padding: 16)
        }
        .buttonStyle(.plain)
    }
}

/// Dati condivisi tra la vista e la coda dei sensori durante la calibrazione (protetti da un lucchetto).
private final class CalibrationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var calibrator: RepCalibrator
    private var stopRequested = false
    private var done = false
    init(targetReps: Int) { calibrator = RepCalibrator(targetReps: targetReps) }

    func requestStop() { lock.lock(); stopRequested = true; lock.unlock() }

    /// Sulla coda dei sensori. Restituisce (ripetizioni, esito se finita).
    func process(t: Double, gravity: Vector3, linear: Vector3) -> (reps: Int, finished: Bool, result: CalibrationResult?)? {
        lock.lock(); defer { lock.unlock() }
        guard !done else { return nil }
        let newRep = calibrator.process(t: t, gravity: gravity, linear: linear)
        if calibrator.isComplete || stopRequested {
            done = true
            return (calibrator.repsDetected, true, calibrator.result())
        }
        return newRep ? (calibrator.repsDetected, false, nil) : nil
    }
}

/// Contatore della prova in diretta (sulla coda dei sensori).
private final class TestBox: @unchecked Sendable {
    private var counter: RepCounter
    private var shown = 0
    init(config: RepCounterConfig) { counter = RepCounter(config: config) }
    func process(t: Double, gravity: Vector3, linear: Vector3) -> Int? {
        counter.process(t: t, gravity: gravity, linear: linear)
        guard counter.count != shown else { return nil }
        shown = counter.count
        return shown
    }
}

/// Calibrazione e sensibilita' del conteggio per ogni posizione del telefono (come Calibration.kt su Android).
/// - Calibrazione: l'utente fa 5 ripetizioni complete; dall'ampiezza misurata si ricavano le soglie (RepCalibrator).
/// - Sensibilita': cursore manuale da 0,5 a 2,0.
/// - Prova: conta le ripetizioni in diretta con le impostazioni correnti.
/// Non si registrano i movimenti: si salvano solo i valori di soglia.
struct CalibrationView: View {
    private enum Mode: Equatable { case idle, countdown, recording, result, testing }
    private struct TestTrigger: Equatable { let mode: Mode; let tuning: PositionTuning; let position: SensorPosition; let key: Int }
    private static let reps = 5
    private static let countdownSeconds = 5

    @State private var position: SensorPosition
    @State private var motion = MotionService()
    @State private var sensorsOn = false
    @State private var mode: Mode = .idle
    @State private var countdown = Self.countdownSeconds
    @State private var progress = 0
    @State private var result: CalibrationResult?
    @State private var justSaved = false
    @State private var testCount = 0
    @State private var testKey = 0
    @State private var box: CalibrationBox?
    @State private var sensitivity = 1.0
    private var settings: AppSettings { AppSettings.shared }

    init(initial: SensorPosition? = nil) { _position = State(initialValue: initial ?? .armUpper) }

    private var tuning: PositionTuning { settings.tuning(for: position) }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                ScreenHeader(symbol: "slider.horizontal.3", title: "calib.title", subtitle: "calib.subtitle")

                VStack(alignment: .leading, spacing: 8) {
                    Picker("position.title", selection: $position) {
                        ForEach(SensorPosition.allCases) { Text($0.titleKey).tag($0) }
                    }
                    .pickerStyle(.menu)
                    Text(position.hintKey).font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard()

                if !motion.isAvailable {
                    Text("calib.noSensor").font(.footnote).foregroundStyle(.orange)
                }

                calibrationCard

                if mode == .idle || mode == .testing {
                    sensitivityCard
                    testCard
                }

                Text("calib.footnote").font(.caption2).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(20)
        }
        .appScreen()
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true   // i sensori si fermano se lo schermo si spegne
            sensitivity = tuning.sensitivity
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            motion.setRawSink(nil); motion.stop(); sensorsOn = false
        }
        .onChange(of: position) { _, _ in
            idle(); justSaved = false; result = nil; sensitivity = tuning.sensitivity
        }
        .task(id: mode) {
            guard mode == .countdown else { return }
            while countdown > 0 {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled || mode != .countdown { return }
                countdown -= 1
            }
            beginRecording()
        }
        .task(id: TestTrigger(mode: mode, tuning: tuning, position: position, key: testKey)) {
            guard mode == .testing else { return }
            testCount = 0
            let test = TestBox(config: tuning.config())
            motion.setRawSink { t, g, l in
                if let n = test.process(t: t, gravity: g, linear: l) { DispatchQueue.main.async { testCount = n } }
            }
        }
    }

    // MARK: - Calibrazione

    @ViewBuilder
    private var calibrationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch mode {
            case .countdown:
                Text("calib.getReady \(countdown)").font(.title3.bold())
                Button("calib.cancel") { idle() }.buttonStyle(.glass)
            case .recording:
                Text("calib.doReps \(Self.reps)").font(.title3.bold())
                Text("calib.progress \(progress) \(Self.reps)").font(.title.bold()).foregroundStyle(Theme.accentSoft)
                Button("calib.finishNow") { box?.requestStop() }.buttonStyle(.glass)
                Button("calib.cancel") { idle() }.buttonStyle(.glass)
            case .result:
                if let r = result {
                    Text("calib.resultTitle").font(.headline)
                    Text(r.signal == .tilt ? "calib.resultSignalTilt" : "calib.resultSignalMove").font(.subheadline).foregroundStyle(.secondary)
                    Text("calib.resultReps \(r.reps)").font(.subheadline).foregroundStyle(.secondary)
                    Text(r.isReliable ? "calib.resultRegular" : "calib.resultIrregular").font(.subheadline).foregroundStyle(.secondary)
                    Button("calib.save") {
                        settings.setTuning(r.toTuning(sensitivity: tuning.sensitivity, now: Date().timeIntervalSince1970), for: position)
                        justSaved = true; result = nil; idle()
                    }
                    .buttonStyle(.glassProminent).tint(Theme.accent)
                } else {
                    Text("calib.needMore").font(.subheadline).foregroundStyle(.secondary)
                }
                Button("calib.redo") { startCountdown() }.buttonStyle(.glass)
                Button("calib.cancel") { idle() }.buttonStyle(.glass)
            case .idle, .testing:
                if tuning.isCalibrated {
                    Text("calib.statusDone \(Date(timeIntervalSince1970: tuning.calibratedAt).formatted(date: .abbreviated, time: .omitted))")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    Text("calib.statusNone").font(.subheadline).foregroundStyle(.secondary)
                }
                if justSaved { Text("calib.saved").font(.subheadline.bold()).foregroundStyle(Theme.accentSoft) }
                Text("calib.intro \(Self.reps)").font(.caption).foregroundStyle(.secondary)
                Button(tuning.isCalibrated ? "calib.redo" : "calib.start") { justSaved = false; startCountdown() }
                    .buttonStyle(.glassProminent).tint(Theme.accent)
                    .disabled(!motion.isAvailable)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: - Sensibilita' e prova

    private var sensitivityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("calib.sensitivityTitle").font(.headline)
            HStack {
                Slider(value: $sensitivity, in: PositionTuning.minSensitivity...PositionTuning.maxSensitivity, step: 0.1) { editing in
                    if !editing {
                        var t = tuning; t.sensitivity = sensitivity
                        settings.setTuning(t, for: position)
                    }
                }
                Text(verbatim: "×" + sensitivity.formatted(.number.precision(.fractionLength(1)))).monospacedDigit()
            }
            .tint(Theme.accent)
            HStack {
                Text("calib.less"); Spacer(); Text("calib.more")
            }
            .font(.caption).foregroundStyle(.secondary)
            Text("calib.sensitivityNote").font(.caption).foregroundStyle(.secondary)
            Button("calib.reset") {
                settings.resetTuning(for: position); sensitivity = 1; justSaved = false
            }
            .buttonStyle(.glass)
            .disabled(tuning.isDefault)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var testCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("calib.testTitle").font(.headline)
            Text("calib.testNote").font(.caption).foregroundStyle(.secondary)
            if mode == .testing {
                Text("calib.testCount").font(.footnote).foregroundStyle(.secondary)
                Text("\(testCount)")
                    .font(.system(size: 64, weight: .heavy, design: .rounded).monospacedDigit())
                    .frame(maxWidth: .infinity)
                    .contentTransition(.numericText())
                HStack {
                    Button("calib.testReset") { testKey += 1 }.buttonStyle(.glass)
                    Button("calib.testStop") { idle() }.buttonStyle(.glass)
                }
            } else {
                Button("calib.testStart") { sensors(true); mode = .testing }
                    .buttonStyle(.glassProminent).tint(Theme.accent)
                    .disabled(!motion.isAvailable)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: - Azioni

    private func sensors(_ on: Bool) {
        guard on != sensorsOn else { return }
        sensorsOn = on
        if on { motion.start() } else { motion.setRawSink(nil); motion.stop() }
    }

    private func idle() { motion.setRawSink(nil); sensors(false); mode = .idle }

    private func startCountdown() {
        motion.setRawSink(nil)
        countdown = Self.countdownSeconds
        sensors(true)
        mode = .countdown
    }

    private func beginRecording() {
        let b = CalibrationBox(targetReps: Self.reps)
        box = b
        progress = 0
        motion.setRawSink { t, g, l in
            guard let update = b.process(t: t, gravity: g, linear: l) else { return }
            DispatchQueue.main.async {
                progress = update.reps
                if update.finished { result = update.result; idle(); mode = .result }
            }
        }
        mode = .recording
    }
}
