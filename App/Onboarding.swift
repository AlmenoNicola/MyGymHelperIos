import SwiftUI
import MyGymHelperCore

/// Prima installazione: prima il disclaimer, poi la richiesta di consenso (separata e facoltativa).
struct OnboardingFlow: View {
    @AppStorage(Disclaimer.acceptedDefaultsKey) private var disclaimerAccepted = false

    var body: some View {
        if !disclaimerAccepted {
            DisclaimerView {
                ConsentStore.recordDisclaimerAccepted()
                disclaimerAccepted = true
            }
        } else {
            ConsentView { }
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
                Toggle(isOn: $checked) { Text("consent.check").appFont(.subheadline) }
                    .tint(Theme.accent)
                    .glassCard(padding: 16)
                Button {
                    ConsentStore.grant(); onFinish(); dismiss()
                } label: {
                    Text("consent.accept").appFont(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent).tint(Theme.accent)
                .disabled(!checked)
                Button("consent.later") { ConsentStore.decline(); onFinish(); dismiss() }
                    .buttonStyle(.glass)
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
