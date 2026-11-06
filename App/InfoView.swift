import SwiftUI
import MessageUI
import MyGymHelperCore

/// Informazioni: account, Apple Salute, documenti legali, consenso, fonti dei dati e cancellazione dei dati locali.
struct InfoView: View {
    @Environment(AccountService.self) private var account
    @Environment(SubscriptionManager.self) private var subscriptions
    @AppStorage(ConsentStore.grantedAtKey) private var consentAt = 0.0
    @AppStorage(HealthKitService.enabledKey) private var healthEnabled = false
    @AppStorage(Disclaimer.acceptedDefaultsKey) private var disclaimerAccepted = false
    @AppStorage(ConsentStore.decidedKey) private var consentDecided = false
    @State private var showConsent = false
    @State private var confirmDelete = false
    @State private var showSuggestMail = false     // Mail di sistema con il suggerimento
    @State private var suggestNoMail = false       // nessuna app di posta: si mostra l'indirizzo
    @Environment(\.openURL) private var openURL

    private var granted: Bool { consentAt > 0 }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                ProfileHeader()     // con la foto profilo (si cambia toccandola)
                    .tutorialTarget(TutorialTarget.tabInfo)

                #if DEBUG
                // Solo nella versione di sviluppo: spiega perche' l'account non compare (Supabase non collegato).
                if !account.isConfigured {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("account.title").appFont(.headline)
                        Text("account.notConfigured").appFont(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()
                }
                #endif
                if account.isConfigured {
                    NavigationLink { AccountView() } label: {
                        HStack(spacing: 14) {
                            if ProfilePhotoStore.shared.photo != nil {
                                ProfileAvatar(size: 30)
                            } else {
                                Image(systemName: "person.crop.circle.fill").appFont(.title2).foregroundStyle(Theme.accent)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("account.title").appFont(.headline)
                                if let email = account.email {
                                    Text(verbatim: email).appFont(.caption).foregroundStyle(.secondary)
                                } else {
                                    Text(account.isSignedIn ? "account.signedIn" : "account.optional")
                                        .appFont(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right").appFont(.footnote).foregroundStyle(.secondary)
                        }
                        .glassCard(padding: 16)
                    }
                    .buttonStyle(.plain)
                }

                // Piani e abbonamenti: sempre la seconda voce. Dopo l'account se c'e', altrimenti dopo l'aspetto (sotto).
                if account.isConfigured { plansRow }

                // Tema grafico: neutro del telefono (predefinito), originale o scuro. Si applica subito a tutta l'app.
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 14) {
                        Image(systemName: "circle.lefthalf.filled").appFont(.title2).foregroundStyle(Theme.accent)
                        Text("appearance.title").appFont(.headline).lineLimit(1)
                    }
                    Picker("appearance.title", selection: Binding(get: { ThemeStore.shared.appearance },
                                                                 set: { ThemeStore.shared.appearance = $0 })) {
                        ForEach(AppAppearance.allCases, id: \.self) { a in
                            Text(LocalizedStringKey(a.titleKey)).tag(a)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text("appearance.note").appFont(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard(padding: 16)
                .tutorialTarget(TutorialTarget.infoAppearance)

                if !account.isConfigured { plansRow }

                // Tutorial dell'app: si puo' rivedere quando si vuole (al primo avvio parte da solo).
                Button { TutorialController.shared.start() } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "graduationcap.fill").appFont(.title2).foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("info.tutorial").appFont(.headline).lineLimit(1)
                            Text("info.tutorialNote").appFont(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "play.circle.fill").appFont(.title3).foregroundStyle(Theme.accentSoft)
                    }
                    .glassCard(padding: 16)
                }
                .buttonStyle(.plain)
                .tutorialTarget(TutorialTarget.infoTutorial)

                VStack(spacing: 0) {
                    NavigationLink { LegalScreen(name: "disclaimer", title: "info.disclaimer") } label: { row("info.disclaimer", "cross.case.fill") }
                    Divider().overlay(Color.primary.opacity(0.15))
                    NavigationLink { LegalScreen(name: "privacy", title: "info.privacy") } label: { row("info.privacy", "lock.shield.fill") }
                    Divider().overlay(Color.primary.opacity(0.15))
                    Link(destination: LegalLinks.terms) { row("info.terms", "doc.plaintext.fill") }
                }
                .buttonStyle(.plain)
                .glassCard(padding: 16)

                VStack(alignment: .leading, spacing: 12) {
                    Text("info.consentStatus").appFont(.headline)
                    if granted {
                        Text("info.granted \(Date(timeIntervalSince1970: consentAt).formatted(date: .abbreviated, time: .omitted))")
                            .appFont(.subheadline).foregroundStyle(.secondary)
                        Button("info.revoke", role: .destructive) {
                            ConsentStore.revoke(); consentAt = 0; healthEnabled = false
                        }
                        .buttonStyle(.glass)
                    } else {
                        Text("info.notGranted").appFont(.subheadline).foregroundStyle(.secondary)
                        Button("info.grant") { showConsent = true }
                            .buttonStyle(.glassProminent).tint(Theme.accent)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard()

                healthCard

                VStack(spacing: 0) {
                    // Voce e musica: comprende anche gli avvisi (voce, suono, vibrazione), prima nella scheda Allenamento.
                    NavigationLink { AudioSettingsView() } label: { row("audio.title", "person.wave.2.fill") }
                        .tutorialTarget(TutorialTarget.infoAudio)
                    Divider().overlay(Color.primary.opacity(0.15))
                    NavigationLink { CalibrationView() } label: { row("calib.open", "slider.horizontal.3") }
                }
                .buttonStyle(.plain)
                .glassCard(padding: 16)

                // Build di debug (Xcode) o strumenti di test accesi (AppFlags.testTools, da spegnere prima della
                // pubblicazione): piano simulato per provare il Pro senza acquisti e cronologia finta.
                if TestTools.enabled {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("debug.title").appFont(.headline).foregroundStyle(.orange)
                        Picker("debug.title", selection: Binding(get: { AppSettings.shared.debugTier },
                                                                set: { subscriptions.setDebugTier($0) })) {
                            Text("debug.real").tag(-1)
                            Text(verbatim: "Free").tag(0)
                            Text(verbatim: "Pro").tag(2)
                        }
                        .pickerStyle(.segmented)
                        Text("debug.note \(String(localized: subscriptions.tier.titleKey))").appFont(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()

                    // Cronologia finta per provare la revisione della scheda ogni due settimane.
                    FakeHistoryCard()
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("info.sources").appFont(.headline)
                    Text("info.sourcesExercises").appFont(.footnote).foregroundStyle(.secondary)
                    Text("food.attribution").appFont(.footnote).foregroundStyle(.secondary)
                    Text("info.sourcesLocal").appFont(.footnote).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard()

                Button("info.delete", role: .destructive) { confirmDelete = true }
                    .buttonStyle(.glass)

                // Ultima voce: suggerire funzioni nuove o cosa manca. Si apre la mail verso AppContact.email.
                suggestRow

                Text(verbatim: "MyGymHelper \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")
                    .appFont(.caption2).foregroundStyle(.tertiary)
            }
            .padding(20)
        }
        .tutorialScrollFollow()
        .appScreen()
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showConsent) { ConsentView { } }
        .sheet(isPresented: $showSuggestMail) {
            let info = ErrorReporter.info(time: Date())
            MailComposeView(to: Suggestion.email, subject: Suggestion.subject(info: info),
                            body: Suggestion.body(intro: String(localized: "suggest.intro"), info: info))
        }
        .confirmationDialog("info.deleteConfirm", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("info.delete", role: .destructive) {
                LocalData.deleteAll()
                // Aggiorna subito lo stato in memoria: ricompaiono disclaimer e consenso senza riavviare.
                consentAt = 0; healthEnabled = false
                consentDecided = false; disclaimerAccepted = false
            }
            Button("info.cancel", role: .cancel) { }
        }
    }

    /// "Suggerisci una funzione": con Mail configurata si apre la mail gia' compilata, altrimenti un link mailto.
    /// Se non c'e' nessuna app di posta si mostra l'indirizzo a cui scrivere. Come SuggestRow su Android.
    private var suggestRow: some View {
        Button {
            suggestNoMail = false
            if MFMailComposeViewController.canSendMail() { showSuggestMail = true; return }
            let info = ErrorReporter.info(time: Date())
            var c = URLComponents(); c.scheme = "mailto"; c.path = Suggestion.email
            c.queryItems = [URLQueryItem(name: "subject", value: Suggestion.subject(info: info)),
                            URLQueryItem(name: "body", value: Suggestion.body(intro: String(localized: "suggest.intro"), info: info))]
            if let url = c.url { openURL(url) { accepted in if !accepted { suggestNoMail = true } } } else { suggestNoMail = true }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 14) {
                    Image(systemName: "lightbulb.fill").appFont(.title2).foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("info.suggest").appFont(.headline).lineLimit(1)
                        Text("info.suggestNote").appFont(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").appFont(.footnote).foregroundStyle(.secondary)
                }
                if suggestNoMail {
                    Text("suggest.noMail \(Suggestion.email)").appFont(.footnote).foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(padding: 16)
        }
        .buttonStyle(.plain)
        .tutorialTarget(TutorialTarget.infoSuggest)
    }

    /// Voce "Piani e abbonamenti" (prima era una scheda della barra): piano attuale, apre il confronto.
    private var plansRow: some View {
        NavigationLink { PaywallView() } label: {
            HStack(spacing: 14) {
                Image(systemName: "star.fill").appFont(.title2).foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("info.plans").appFont(.headline).lineLimit(1)
                    Text("info.plansNote \(String(localized: subscriptions.tier.titleKey))")
                        .appFont(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").appFont(.footnote).foregroundStyle(.secondary)
            }
            .glassCard(padding: 16)
        }
        .buttonStyle(.plain)
        .tutorialTarget(TutorialTarget.infoPlans)
    }

    /// Apple Salute: facoltativo, solo con il consenso ai dati sanitari.
    private var healthCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: Binding(
                get: { healthEnabled && granted },
                set: { on in
                    if on {
                        Task { @MainActor in
                            healthEnabled = await HealthKitService.shared.requestAuthorization()
                        }
                    } else {
                        healthEnabled = false
                    }
                })) {
                Label("health.title", systemImage: "heart.fill")
            }
            .tint(Theme.accent)
            .disabled(!granted || !HealthKitService.shared.isAvailable)
            Text(granted ? "health.note" : "health.needConsent").appFont(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func row(_ title: LocalizedStringKey, _ symbol: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).foregroundStyle(Theme.accent).frame(width: 28)
            Text(title).appFont(.headline)
            Spacer()
            Image(systemName: "chevron.right").appFont(.footnote).foregroundStyle(.secondary)
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}
