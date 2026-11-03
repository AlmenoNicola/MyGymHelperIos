import SwiftUI
import MyGymHelperCore

@main
struct MyGymHelperApp: App {
    @State private var subscriptions = SubscriptionManager()
    @State private var catalog = CatalogStore()
    @State private var account = AccountService()
    @AppStorage(Disclaimer.acceptedDefaultsKey) private var disclaimerAccepted = false
    @AppStorage(ConsentStore.decidedKey) private var consentDecided = false
    @Environment(\.scenePhase) private var scenePhase

    init() {
        ErrorReporter.shared.install()     // prima di tutto: eccezioni non gestite salvate e proposte al riavvio
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(subscriptions)
                .environment(catalog)
                .environment(account)
                .task {
                    // Gli acquisti portano l'id dell'account, se l'utente ha fatto l'accesso (collegamento sul server).
                    let account = self.account
                    subscriptions.accountToken = { account.userID }
                    // Piano anche dal server (licenze gratuite manuali comprese), se l'utente ha fatto l'accesso.
                    subscriptions.serverCheck = { await account.fetchEntitlement() }
                    await subscriptions.start()
                }
                .task { await account.start() }
                // Accesso o uscita dall'account: si rilegge il piano dal server.
                .onChange(of: account.userID) { _, _ in Task { await subscriptions.refreshServer() } }
                // Ritorno da Spotify dopo averla aperta per far partire la musica (SDK App Remote).
                .onOpenURL { url in _ = SpotifyRemote.shared.handle(url: url) }
                .onChange(of: scenePhase) { _, phase in
                    // Rinnovi, scadenze o acquisti fatti altrove: si ricontrolla tornando nell'app.
                    if phase == .active { Task { await subscriptions.refresh() } }
                }
                .modelContainer(PersistenceController.container)
                .fullScreenCover(isPresented: .constant(!disclaimerAccepted || !consentDecided)) {
                    OnboardingFlow()
                }
        }
    }
}
