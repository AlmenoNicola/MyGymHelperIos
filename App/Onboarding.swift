import SwiftUI
import AuthenticationServices
import MyGymHelperCore

/// Prima installazione: prima il disclaimer, poi la richiesta di consenso (separata e facoltativa), poi l'accesso
/// con Apple o Google (obbligatorio dal 9 novembre 2026).
struct OnboardingFlow: View {
    @AppStorage(Disclaimer.acceptedDefaultsKey) private var disclaimerAccepted = false
    @AppStorage(ConsentStore.decidedKey) private var consentDecided = false
    @Environment(AccountService.self) private var account

    var body: some View {
        if !disclaimerAccepted {
            DisclaimerView {
                ConsentStore.recordDisclaimerAccepted()
                disclaimerAccepted = true
            }
        } else if !consentDecided {
            ConsentView { }
        } else if !account.sessionKnown {
            // Sessione salvata ancora in lettura: si aspetta prima di chiedere l'accesso
            ZStack { AppBackground(); ProgressView() }
        } else {
            LoginGateView()
        }
    }
}

/// Accesso obbligatorio (9 novembre 2026): dopo disclaimer e consenso, senza account Apple o Google non si entra.
/// Il primo accesso crea anche l'account; la sessione resta salvata, quindi si chiede solo la prima volta.
struct LoginGateView: View {
    @Environment(AccountService.self) private var account
    /// Pulsante Apple bianco sui fondi scuri, nero su quello chiaro (come in AccountView).
    @Environment(\.colorScheme) private var colorScheme
    @State private var nonce = ""

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 20) {
                ScreenHeader(symbol: "person.crop.circle.fill", title: "gate.title", subtitle: "gate.subtitle")
                ScrollView {
                    VStack(spacing: 12) {
                        Text("gate.body").appType(.secondary).frame(maxWidth: .infinity, alignment: .leading).glassCard()
                        if let error = account.lastError { Text(error).appType(.caption).foregroundStyle(.orange) }
                    }
                }
                if account.isWorking { ProgressView() }
                SignInWithAppleButton(.signIn) { request in
                    nonce = AccountService.makeNonce()
                    request.requestedScopes = [.email]
                    request.nonce = AccountService.sha256(nonce)
                } onCompletion: { result in
                    guard case .success(let authorization) = result,
                          let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                          let tokenData = credential.identityToken,
                          let idToken = String(data: tokenData, encoding: .utf8) else { return }
                    let raw = nonce
                    Task { await account.signInWithApple(idToken: idToken, rawNonce: raw) }
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 50)
                .clipShape(Capsule())
                Button { Task { await account.signInWithGoogle() } } label: {
                    Label("account.google", systemImage: "globe").appType(.button).frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
            }
            .padding(20)
        }
    }
}

/// Consenso esplicito e separato per i dati sulla salute: casella NON preselezionata,
/// si puo' proseguire anche senza (le funzioni che non usano dati sanitari restano disponibili).
struct ConsentView: View {
    var onFinish: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var checked = false

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 20) {
                ScreenHeader(symbol: "heart.text.square.fill", title: "consent.title", subtitle: "consent.subtitle")
                ScrollView {
                    VStack(spacing: 16) {
                        LegalDocumentView(name: "consent", showsTitle: false).glassCard()
                        privacyDisclosure
                    }
                }
                Toggle(isOn: $checked) { Text("consent.check").appType(.secondary) }
                    .tint(Theme.accent)
                    .glassCard(padding: 16)
                Button {
                    ConsentStore.grant(); onFinish(); dismiss()
                } label: {
                    Text("consent.accept").appType(.cardTitle).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent).appType(.button).tint(Theme.accent)
                .disabled(!checked)
                Button("consent.later") { ConsentStore.decline(); onFinish(); dismiss() }
                    .buttonStyle(.glass).appType(.button)
            }
            .padding(20)
        }
        .interactiveDismissDisabled()
    }

    /// Collegamento all'informativa completa, leggibile prima di decidere.
    private var privacyDisclosure: some View {
        DisclosureGroup("info.privacy") {
            LegalDocumentView(name: "privacy", showsTitle: false).padding(.top, 8)
        }
        .tint(Theme.accent)
        .glassCard(padding: 16)
    }
}
