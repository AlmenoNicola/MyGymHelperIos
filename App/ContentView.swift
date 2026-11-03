import SwiftUI
import MyGymHelperCore

/// Schede principali. Il BMI e' nella scheda Nutrizione (disponibile anche nel piano Free).
/// La Nutrizione per ora e' disattivata (AppFeatures.nutritionEnabled): il codice resta, la scheda non si vede.
struct ContentView: View {
    @Bindable private var settings = AppSettings.shared
    @AppStorage(Disclaimer.acceptedDefaultsKey) private var disclaimerAccepted = false
    @AppStorage(ConsentStore.decidedKey) private var consentDecided = false
    private var tutorial: TutorialController { TutorialController.shared }

    var body: some View {
        TabView(selection: $settings.selectedTab) {
            Tab("tab.workout", systemImage: "figure.strengthtraining.traditional", value: .workout) {
                NavigationStack { WorkoutSetupView() }
                    .id(settings.workoutStackID)     // cambia: si torna alla schermata iniziale (scheda pronta usata)
            }
            Tab("tab.exercises", systemImage: "dumbbell.fill", value: .exercises) {
                NavigationStack { ExercisesView() }
            }
            if AppFeatures.nutritionEnabled {
                Tab("tab.nutrition", systemImage: "fork.knife", value: .nutrition) {
                    NavigationStack { NutritionView() }
                }
            }
            // "Area personale": account, piani e abbonamenti, consensi, documenti legali e dati.
            // I Piani non sono piu' una scheda: si aprono dall'Area personale (e dalle note "Disponibile con...").
            Tab("tab.info", systemImage: "person.crop.circle.fill", value: .info) {
                NavigationStack { InfoView() }
            }
        }
        .tint(Theme.accent)
        // Tema neutro: chiaro o scuro come il telefono (nil); originale e scuro: sempre scuro.
        .preferredColorScheme(ThemeStore.shared.preferredScheme)
        // In tutta l'app i testi che non stanno nel loro spazio (righe limitate) rimpiccioliscono fino al 60%
        // invece di essere troncati: utile con le lingue dalle parole lunghe e sugli iPhone piccoli.
        .minimumScaleFactor(0.6)
        // Avviso "Aggiunto all'elenco": in basso, appena sopra la barra delle schede; non blocca i tocchi.
        .overlay(alignment: .bottom) {
            AddedNoticeBanner().padding(.bottom, 64).allowsHitTesting(false)
        }
        // Tutorial sopra a tutto, barra delle schede compresa.
        .overlay { TutorialOverlay() }
        // Finestra "Invia" / "Annulla" per il rapporto di un errore.
        .errorReportAlert()
        // Primo avvio: finiti disclaimer e consenso, il tutorial parte da solo una volta (poi dall'Area personale).
        .onChange(of: disclaimerAccepted && consentDecided, initial: true) { _, ready in
            if ready && TutorialGuide.shouldAutoStart(seenVersion: TutorialController.seenVersion) && !tutorial.isActive {
                tutorial.start()
            }
        }
    }
}
