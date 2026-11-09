import Foundation
import CoreMotion
import Observation
import MyGymHelperCore

/// Legge gravita', accelerazione dell'utente e giroscopio a 50 Hz e conta le ripetizioni con il RepCounter del core:
/// una ripetizione vale solo con andata e ritorno completi dell'arto (come MotionService.kt su Android).
/// L'asse del movimento (su/giu' o sinistra/destra) e' in `config.axis` e si puo' cambiare durante la serie.
/// Richiede NSMotionUsageDescription in Info.plist.
/// Il lavoro sui sensori avviene su una coda seriale; lo stato per la UI viene pubblicato sul thread principale.
@Observable
final class MotionService {
    @ObservationIgnored private let manager = CMMotionManager()
    @ObservationIgnored private let queue: OperationQueue = {
        let q = OperationQueue(); q.maxConcurrentOperationCount = 1; q.qualityOfService = .userInitiated; return q
    }()
    @ObservationIgnored private var config: RepCounterConfig
    @ObservationIgnored private var counter: RepCounter
    /// Ripetizioni contate nella serie prima di un cambio d'asse (il contatore riparte da zero con il nuovo asse).
    @ObservationIgnored private var baseCount = 0
    @ObservationIgnored private var counting = false
    @ObservationIgnored private var lastCount = -1
    @ObservationIgnored private var lastLow = false
    @ObservationIgnored private var lastCalibrated = false
    /// Campioni grezzi (tempo in secondi, gravita', accelerazione dell'utente, in g) sulla coda dei sensori.
    /// Servono alla calibrazione e alla prova del conteggio; si impostano con `setRawSink`.
    @ObservationIgnored private var rawSink: ((Double, Vector3, Vector3) -> Void)?
    /// Chiamato sul thread principale ogni volta che cambia il numero di ripetizioni della serie corrente.
    @ObservationIgnored var onRepCount: (@Sendable (Int) -> Void)?

    private(set) var repCount = 0
    private(set) var isCalibrating = true
    private(set) var lowConfidence = false
    /// Velocita' massima media delle ripetizioni della serie (indice di fatica per i consigli).
    private(set) var averagePeak = 0.0
    private(set) var isAvailable = true

    init(config: RepCounterConfig = RepCounterConfig()) {
        self.config = config
        self.counter = RepCounter(config: config)
        self.isAvailable = manager.isDeviceMotionAvailable
    }

    func start() {
        guard manager.isDeviceMotionAvailable else { isAvailable = false; return }
        guard !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 50.0
        manager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
            guard let self, let m = motion else { return }
            let g = m.gravity, a = m.userAcceleration   // in g; userAcceleration e' gia' senza gravita'
            let r = m.rotationRate                      // rad/s, stesso sistema di riferimento di gravity
            self.handle(t: m.timestamp, gravity: Vector3(g.x, g.y, g.z), linear: Vector3(a.x, a.y, a.z),
                        rotation: Vector3(r.x, r.y, r.z))
        }
    }

    func stop() { manager.stopDeviceMotionUpdates() }

    /// Imposta (o toglie, con nil) chi riceve i campioni grezzi; il cambio avviene sulla coda dei sensori.
    func setRawSink(_ sink: ((Double, Vector3, Vector3) -> Void)?) {
        queue.addOperation { [weak self] in self?.rawSink = sink }
    }

    /// Nuova serie: azzera il conteggio. Segnale e asse si ricalibrano a ogni serie (il telefono puo' essersi spostato).
    func beginSet() {
        queue.addOperation { [weak self] in
            guard let self else { return }
            self.counter = RepCounter(config: self.config)
            self.baseCount = 0
            self.counting = true
            self.lastCount = -1
            self.lastLow = false
            self.lastCalibrated = false
            self.publish(count: 0, low: false, peak: 0, calibrated: false)
        }
    }

    /// Cambia l'asse del movimento (pulsante durante il conteggio): le ripetizioni già contate nella serie restano,
    /// il contatore riparte con il nuovo asse (nuova calibrazione dei primi secondi). Vale anche per le serie dopo.
    func setAxis(_ axis: MovementAxis) {
        queue.addOperation { [weak self] in
            guard let self, self.config.axis != axis else { return }
            self.baseCount += self.counter.count
            self.config.axis = axis
            self.counter = RepCounter(config: self.config)
            self.lastCalibrated = false
            self.publish(count: self.baseCount, low: false, peak: 0, calibrated: false)
        }
    }

    /// Smette di contare (durante la pausa).
    func pauseCounting() {
        queue.addOperation { [weak self] in self?.counting = false }
    }

    private func handle(t: Double, gravity: Vector3, linear: Vector3, rotation: Vector3) {
        rawSink?(t, gravity, linear)       // calibrazione e prova: senza giroscopio, come prima
        guard counting else { return }
        counter.process(t: t, gravity: gravity, linear: linear, rotation: rotation)
        let count = baseCount + counter.count
        let low = counter.signalConfidence < 0.4
        let calibrated = counter.isCalibrated
        guard count != lastCount || low != lastLow || calibrated != lastCalibrated else { return }
        lastCount = count; lastLow = low; lastCalibrated = calibrated
        publish(count: count, low: low, peak: counter.averagePeakSpeed, calibrated: calibrated)
    }

    private func publish(count: Int, low: Bool, peak: Double, calibrated: Bool) {
        let callback = onRepCount
        DispatchQueue.main.async {
            self.repCount = count
            self.lowConfidence = low
            self.averagePeak = peak
            self.isCalibrating = !calibrated
            callback?(count)
        }
    }
}
