import Foundation
import SwiftData

/// Registro locale del consenso al trattamento dei dati sulla salute.
/// Salva data e versione dei testi accettati: e' la prova della scelta, tenuta sul telefono.
enum ConsentStore {
    static let grantedAtKey = "consent.health.grantedAt"      // secondi dal 1970; 0 = non concesso
    static let versionKey = "consent.health.version"
    static let decidedKey = "consent.health.decided"          // l'utente ha risposto (si' o non ora)
    static let disclaimerAtKey = "disclaimer.acceptedAt"
    static let disclaimerVersionKey = "disclaimer.acceptedVersion"

    static func recordDisclaimerAccepted() {
        let d = UserDefaults.standard
        d.set(Date().timeIntervalSince1970, forKey: disclaimerAtKey)
        d.set(LegalDocument.version, forKey: disclaimerVersionKey)
    }

    static func grant() {
        let d = UserDefaults.standard
        d.set(Date().timeIntervalSince1970, forKey: grantedAtKey)
        d.set(LegalDocument.version, forKey: versionKey)
        d.set(true, forKey: decidedKey)
    }

    static func decline() { UserDefaults.standard.set(true, forKey: decidedKey) }

    /// Revoca: azzera il consenso e cancella i dati sulla salute salvati sul telefono.
    @MainActor
    static func revoke() {
        let d = UserDefaults.standard
        d.set(0.0, forKey: grantedAtKey)
        d.removeObject(forKey: versionKey)
        d.set(false, forKey: HealthKitService.enabledKey)   // senza consenso niente scambio con Apple Salute
        LocalData.deleteHealthData()
    }
}

@MainActor
enum LocalData {
    /// Cancella tutti i dati sulla salute salvati: storico, profilo e pesate, elenchi, schede di allenamento (anche quelle
    /// create con "Crea la tua scheda") e dell'alimentazione. Vale per "Cancella dati", revoca del consenso ed "Elimina tutto".
    /// Usa il contesto principale, lo stesso letto dalle schermate (@Query), cosi' le liste si aggiornano subito.
    static func deleteHealthData() {
        let context = PersistenceController.container.mainContext
        try? context.delete(model: WorkoutSessionRecord.self)   // le serie collegate si cancellano a cascata
        try? context.delete(model: SetLogRecord.self)
        try? context.delete(model: ExerciseListRecord.self)
        try? context.delete(model: TrainingPlanRecord.self)
        try? context.delete(model: NutritionPlanRecord.self)
        try? context.delete(model: HealthProfileRecord.self)
        try? context.delete(model: CustomPlanEntity.self)       // schede create con "Crea la tua scheda"
        try? context.delete(model: WeightEntryRecord.self)      // pesate del Profilo (grafico del peso)
        try? context.save()
        WorkoutListStore.shared.clear()
        MonthlyPlanStore.shared.clear()      // scheda del mese rivista dall'AI (ricavata dallo storico)
        PlanReviewStore.shared.clear()       // revisione della scheda ogni due settimane (proposta e copia di prima)
        CustomPlanStore.shared.clear()       // schede create con "Crea la tua scheda"
    }

    /// Elimina tutti i dati locali dell'app (impostazioni incluse): al riavvio ricompaiono disclaimer e consenso.
    static func deleteAll() {
        deleteHealthData()
        SpotifyService.shared.logout()       // anche il collegamento a Spotify (token nel Portachiavi)
        if let id = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: id)
        }
        AppSettings.shared.reload()          // voce, musica e calibrazioni tornano ai valori predefiniti
        ThemeStore.shared.reload()           // e il tema torna quello predefinito (neutro)
        ProfilePhotoStore.shared.delete()    // anche la foto profilo
        VoiceEngine.shared.applyVoice()
    }
}
