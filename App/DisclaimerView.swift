import SwiftUI
import MyGymHelperCore

/// Mostrato alla prima installazione, con conferma esplicita.
/// Lo stesso testo va in Informazioni e nella descrizione su App Store.
struct DisclaimerView: View {
    var onAccept: () -> Void
    @State private var understood = false

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 20) {
                ScreenHeader(symbol: "cross.case.fill",
                             title: "disclaimer.title",
                             subtitle: "disclaimer.subtitle")
                ScrollView {
                    LegalDocumentView(name: "disclaimer").glassCard()
                }
                Toggle(isOn: $understood) { Text("disclaimer.check").appFont(.subheadline) }
                    .tint(Theme.accent)
                    .glassCard(padding: 16)
                Button(action: onAccept) {
                    Text("disclaimer.accept").appFont(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.accent)
                .disabled(!understood)
            }
            .padding(20)
        }
        .interactiveDismissDisabled()
    }
}
