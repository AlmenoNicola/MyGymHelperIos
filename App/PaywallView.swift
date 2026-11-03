import SwiftUI
import StoreKit
import MyGymHelperCore

/// Indirizzi legali letti da Info.plist (vanno pubblicati su una pagina web prima dell'invio ad Apple).
enum LegalLinks {
    private static func url(_ key: String, fallback: String) -> URL {
        let value = (Bundle.main.object(forInfoDictionaryKey: key) as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        return URL(string: value.isEmpty ? fallback : value) ?? URL(string: fallback)!
    }
    /// Informativa privacy pubblica (obbligatoria per lo store).
    static var privacy: URL { url("MyGymHelperPrivacyURL", fallback: "https://example.com/privacy") }
    /// Condizioni d'uso: di default il contratto di licenza standard di Apple (EULA).
    static var terms: URL { url("MyGymHelperTermsURL", fallback: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/") }
}

/// Schermata degli abbonamenti. Usa la vista ufficiale di StoreKit (`SubscriptionStoreView`), che mostra da sola
/// prezzo, durata, prova gratuita solo a chi ne ha diritto, rinnovo automatico, ripristino e link legali:
/// sono le informazioni che Apple controlla in revisione (linea guida 3.1.2).
struct PaywallView: View {
    @Environment(SubscriptionManager.self) private var subscriptions
    @State private var showManage = false

    var body: some View {
        SubscriptionStoreView(productIDs: ProductID.all) {
            PlansMarketing(tier: subscriptions.tier, renewal: subscriptions.renewalDate,
                           freeLicenseUntil: subscriptions.freeLicenseUntil)
        }
        .subscriptionStoreControlStyle(.prominentPicker)
        .subscriptionStoreButtonLabel(.multiline)
        .storeButton(.hidden, for: .restorePurchases)   // sostituito dal pulsante nella barra, che aggiorna subito il piano
        .storeButton(.visible, for: .policies)
        .subscriptionStorePolicyDestination(url: LegalLinks.privacy, for: .privacyPolicy)
        .subscriptionStorePolicyDestination(url: LegalLinks.terms, for: .termsOfService)
        .inAppPurchaseOptions { _ in await subscriptions.purchaseOptions() }
        .onInAppPurchaseCompletion { _, result in
            // Con un'azione personalizzata la transazione va chiusa qui; gli acquisti "in attesa"
            // (Chiedi di acquistare) arrivano piu' tardi da Transaction.updates.
            if case .success(.success(.verified(let transaction))) = result { await transaction.finish() }
            await subscriptions.refresh()
        }
        .containerBackground(for: .subscriptionStoreFullHeight) { AppBackground() }
        .tint(Theme.accent)
        .navigationBarTitleDisplayMode(.inline)   // il titolo e' gia' nell'intestazione della schermata
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("plans.restore") { Task { await subscriptions.restore() } }
            }
            // "Gestisci" porta all'App Store: non serve se il piano viene solo dalla licenza gratuita.
            if subscriptions.activeProductID != nil || (subscriptions.tier > .free && subscriptions.freeLicenseUntil == nil) {
                ToolbarItem(placement: .primaryAction) {
                    Button("plans.manage") { showManage = true }
                }
            }
        }
        .manageSubscriptionsSheet(isPresented: $showManage)
    }
}

/// Parte descrittiva: piano attuale e confronto tra Free, Mid e Full (solo funzioni gia' disponibili).
private struct PlansMarketing: View {
    let tier: SubscriptionTier
    let renewal: Date?
    /// Ultima scadenza della licenza gratuita, se e' lei a dare il piano attuale.
    var freeLicenseUntil: Date? = nil

    private struct Row: Identifiable {
        let id: String
        let tiers: [Bool]        // free, mid, full
    }

    private let allRows: [Row] = [
        Row(id: "compare.counting", tiers: [true, true, true]),
        Row(id: "compare.bmi", tiers: [true, true, true]),
        Row(id: "compare.catalogBasic", tiers: [true, true, true]),
        Row(id: "compare.catalogFull", tiers: [false, true, true]),
        Row(id: "compare.lists", tiers: [false, true, true]),
        Row(id: "compare.variedSets", tiers: [false, true, true]),
        Row(id: "compare.fixedCoaching", tiers: [false, true, true]),
        Row(id: "compare.nutrition", tiers: [false, true, true]),
        Row(id: "compare.adaptive", tiers: [false, false, true]),
        Row(id: "compare.import", tiers: [false, false, true]),
        Row(id: "compare.homeEquipment", tiers: [false, false, true]),
        Row(id: "compare.meals", tiers: [false, false, true])
    ]

    /// Righe delle funzioni della scheda Nutrizione: nascoste finche' e' disattivata (AppFeatures.nutritionEnabled).
    private static let nutritionRows: Set<String> = ["compare.bmi", "compare.nutrition", "compare.meals"]
    private var rows: [Row] {
        allRows.filter {
            (AppFeatures.nutritionEnabled || !Self.nutritionRows.contains($0.id))
                && (AppFlags.homeEquipment || $0.id != "compare.homeEquipment")
                // Senza importazione delle schede (file o foto) la riga sparisce: niente promesse di funzioni spente.
                && (AppFeatures.planImportEnabled || $0.id != "compare.import")
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            ScreenHeader(symbol: "star.fill", title: "plans.title", subtitle: "plans.subtitle")

            HStack {
                Text("plans.current").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text(tier.titleKey)
                    .font(.headline)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(Theme.accentGradient, in: Capsule())
            }
            if let freeLicenseUntil {
                // Licenza gratuita assegnata a mano: si mostra l'ultimo giorno compreso (la scadenza e' la mezzanotte dopo).
                Text("plans.freeLicense \(freeLicenseUntil.addingTimeInterval(-1).formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            if let renewal {
                Text("plans.renews \(renewal.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            VStack(spacing: 10) {
                HStack {
                    Spacer()
                    ForEach([SubscriptionTier.free, .mid, .full], id: \.self) { t in
                        Text(t.titleKey).font(.caption.bold()).frame(width: 44)
                            .foregroundStyle(t == .full ? Theme.accentSoft : .primary)
                    }
                }
                ForEach(rows) { row in
                    HStack(alignment: .firstTextBaseline) {
                        Text(LocalizedStringKey(row.id)).font(.footnote)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(0..<3, id: \.self) { i in
                            Image(systemName: row.tiers[i] ? "checkmark.circle.fill" : "minus")
                                .foregroundStyle(row.tiers[i] ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.tertiary))
                                .frame(width: 44)
                                .accessibilityLabel(Text(row.tiers[i] ? "compare.included" : "compare.notIncluded"))
                        }
                    }
                }
            }
            .glassCard(padding: 16)

            Text("plans.disclaimer").font(.caption2).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }
}
