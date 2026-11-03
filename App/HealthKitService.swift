import Foundation
import HealthKit

/// Collegamento facoltativo con Apple Salute (solo iPhone, tutto sul dispositivo):
/// - lettura di peso e altezza, solo quando l'utente preme "Importa da Salute";
/// - scrittura degli allenamenti di forza completati, se il collegamento e' attivo.
/// Richiede il consenso ai dati sanitari, l'entitlement HealthKit e i testi NSHealth*UsageDescription.
@MainActor
final class HealthKitService {
    static let shared = HealthKitService()
    private init() {}
    /// Interruttore dell'utente (sezione Info).
    nonisolated static let enabledKey = "health.sync.enabled"

    private let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    var isEnabled: Bool {
        isAvailable && UserDefaults.standard.bool(forKey: Self.enabledKey)
            && UserDefaults.standard.double(forKey: ConsentStore.grantedAtKey) > 0
    }

    private var readTypes: Set<HKObjectType> { [HKQuantityType(.bodyMass), HKQuantityType(.height)] }
    private var shareTypes: Set<HKSampleType> { [HKObjectType.workoutType()] }

    /// Mostra la richiesta di Apple (una volta; poi si cambia da Impostazioni > Salute).
    func requestAuthorization() async -> Bool {
        guard isAvailable else { return false }
        do {
            try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
            return true
        } catch {
            return false
        }
    }

    private func latest(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(identifier))],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1)
        guard let sample = try? await descriptor.result(for: store).first else { return nil }
        return sample.quantity.doubleValue(for: unit)
    }

    /// Ultimo peso registrato in Salute (kg). Nil se manca o se l'utente non ha concesso la lettura
    /// (per privacy Apple non dice se la lettura e' stata negata: in quel caso semplicemente non arrivano dati).
    func latestWeightKg() async -> Double? {
        guard isEnabled else { return nil }
        return await latest(.bodyMass, unit: .gramUnit(with: .kilo))
    }

    func latestHeightCm() async -> Double? {
        guard isEnabled else { return nil }
        return await latest(.height, unit: .meterUnit(with: .centi))
    }

    /// Salva un allenamento di forza in Salute, se il collegamento e' attivo e la scrittura e' autorizzata.
    func saveWorkoutIfEnabled(start: Date, end: Date, title: String?) async {
        guard isEnabled, end > start,
              store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else { return }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        do {
            try await builder.beginCollection(at: start)
            try await builder.endCollection(at: end)
            if let title, !title.isEmpty {
                try await builder.addMetadata(["MyGymHelperExercise": title])
            }
            _ = try await builder.finishWorkout()
        } catch {
            // Salute non disponibile o permesso revocato: l'allenamento resta comunque nello storico dell'app.
        }
    }
}
