import SwiftUI
import AuthenticationServices

/// Account facoltativo: accesso con Apple, Google, Facebook o e-mail (codice a 6 cifre), uscita ed eliminazione dell'account.
/// L'app funziona anche senza account; i dati sanitari non vengono mai caricati.
struct AccountView: View {
    @Environment(AccountService.self) private var account
    /// Pulsante Apple bianco sui fondi scuri, nero su quello chiaro (tema neutro con il telefono in modalita' chiara).
    @Environment(\.colorScheme) private var colorScheme
    @State private var email = ""
    @State private var code = ""
    @State private var codeSent = false
    @State private var nonce = ""
    @State private var confirmDelete = false
    @State private var deleted = false
    @State private var appleConfirm = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                ScreenHeader(symbol: "person.crop.circle.fill", title: "account.title", subtitle: "account.subtitle")

                if account.isSignedIn {
                    signedIn
                } else {
                    signInOptions
                }

                if account.isWorking { ProgressView() }
                if let error = account.lastError {
                    Label { Text(verbatim: error) } icon: { Image(systemName: "exclamationmark.triangle.fill") }
                        .appFont(.footnote).foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if deleted {
                    Label("account.deleted", systemImage: "checkmark.circle.fill")
                        .appFont(.footnote).foregroundStyle(Theme.accentSoft)
                }

                Text("account.privacy").appFont(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(20)
        }
        .appScreen()
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("account.deleteConfirm", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("account.delete", role: .destructive) {
                if account.usesApple {
                    appleConfirm = true          // prima si conferma con Apple (revoca dei token Apple)
                } else {
                    Task { deleted = await account.deleteAccount() }
                }
            }
            Button("info.cancel", role: .cancel) { }
        } message: {
            Text("account.deleteMessage")
        }
    }

    private var signedIn: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("account.signedInAs").appFont(.caption).foregroundStyle(.secondary)
            Text(verbatim: account.email ?? "—").appFont(.headline)
            Button("account.signOut") { Task { await account.signOut() } }
                .buttonStyle(.glass)
            Divider().overlay(Color.primary.opacity(0.15))
            Button("account.delete", role: .destructive) { confirmDelete = true }
                .buttonStyle(.glass)
            Text("account.deleteNote").appFont(.caption).foregroundStyle(.secondary)
            if appleConfirm { appleConfirmation }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    /// Chi e' entrato con Apple conferma con Apple: il codice ottenuto permette al server di revocare
    /// i token Apple (richiesto da Apple quando si elimina l'account). Il codice vale 5 minuti e non viene salvato.
    private var appleConfirmation: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("account.appleConfirm").appFont(.subheadline)
            SignInWithAppleButton(.continue) { request in
                request.requestedScopes = []
            } onCompletion: { result in
                guard case .success(let authorization) = result,
                      let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                      let codeData = credential.authorizationCode,
                      let code = String(data: codeData, encoding: .utf8) else { return }
                Task {
                    deleted = await account.deleteAccount(appleAuthorizationCode: code)
                    appleConfirm = !deleted
                }
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 50)
            .clipShape(Capsule())
            Button("info.cancel") { appleConfirm = false }.appFont(.footnote)
        }
        .padding(.top, 6)
    }

    private var signInOptions: some View {
        VStack(spacing: 14) {
            Text("account.why").appFont(.subheadline).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

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
                Label("account.google", systemImage: "globe").appFont(.headline).frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)

            if account.facebookEnabled {
                Button { Task { await account.signInWithFacebook() } } label: {
                    Label("account.facebook", systemImage: "person.2.fill").appFont(.headline).frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
            }

            if account.emailEnabled {
            VStack(alignment: .leading, spacing: 10) {
                Text("account.emailTitle").appFont(.headline)
                TextField("account.emailField", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                if codeSent {
                    TextField("account.codeField", text: $code)
                        .textContentType(.oneTimeCode)
                        .keyboardType(.numberPad)
                        .padding(12)
                        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                    Button("account.verify") {
                        Task { _ = await account.verifyEmailCode(code.trimmingCharacters(in: .whitespaces), email: cleanEmail) }
                    }
                    .buttonStyle(.glassProminent).tint(Theme.accent)
                    .disabled(code.count < 6)
                    Text("account.codeSent").appFont(.caption).foregroundStyle(.secondary)
                } else {
                    Button("account.sendCode") {
                        Task { codeSent = await account.sendEmailCode(to: cleanEmail) }
                    }
                    .buttonStyle(.glassProminent).tint(Theme.accent)
                    .disabled(!cleanEmail.contains("@"))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
            }
        }
    }

    private var cleanEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
}
