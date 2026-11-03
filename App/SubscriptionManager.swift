import Foundation
import StoreKit
import Observation
import MyGymHelperCore

/// Identificatori prodotto: da creare in App Store Connect, in UN gruppo di abbonamento.
/// Prezzi: Mid 4,99 €/mese e 49,99 €/anno; Full 9,99 €/mese e 99,99 €/anno.
/// La prova gratuita di 7 giorni va configurata come offerta introduttiva (free trial)
/// sul gruppo: StoreKit la concede una sola volta per gruppo e per utente.
enum ProductID {
    static let midMonthly = "app.mygymhelper.mid.monthly"
    static let midYearly = "app.mygymhelper.mid.yearly"
    static let fullMonthly = "app.mygymhelper.full.monthly"
    static let fullYearly = "app.mygymhelper.full.yearly"
    static let all = [midMonthly, midYearly, fullMonthly, fullYearly]

    static func tier(for id: String) -> SubscriptionTier {
        id.contains(".full.") ? .full : (id.contains(".mid.") ? .mid : .free)
    }
}

extension SubscriptionTier {
    var titleKey: LocalizedStringResource {
        switch self {
        case .free: "tier.free"
        case .mid: "tier.mid"
        case .full: "tier.full"
        }
    }
}

/// Esito della lettura del piano dal server (`AccountService.fetchEntitlement`).
enum ServerCheck {
    /// Nessun account collegato: dal server non arriva nessun piano.
    case signedOut
    /// Piano letto (`.free` se non c'e' nulla di valido); `source` = "manual", "apple", "google".
    case found(tier: SubscriptionTier, until: Date?, source: String?)
    /// Rete o server non raggiungibili: si tiene l'ultimo valore salvato.
    case unavailable
}

/// Stato degli abbonamenti con StoreKit 2. Le transazioni sono firmate e verificate sul telefono;
/// se l'utente ha un account, gli acquisti portano il suo id (`appAccountToken`) per collegarli sul server.
/// Con l'accesso si legge anche il piano dal server (licenza gratuita assegnata a mano con l'SQL di Supabase,
/// o abbonamento fatto su un altro dispositivo): vale il migliore tra App Store e server.
@Observable
@MainActor
final class SubscriptionManager {
    /// Piano attivo per l'app (nelle build di debug puo' essere simulato, vedi `setDebugTier`).
    private(set) var tier: SubscriptionTier = .free
    @ObservationIgnored private var realTier: SubscriptionTier = .free
    private(set) var activeProductID: String?
    private(set) var renewalDate: Date?
    /// Scadenza della licenza gratuita, solo se e' lei a dare il piano attuale; altrimenti nil.
    private(set) var freeLicenseUntil: Date?

    private let cacheTierKey = "entitlement.tier"
    private let cacheDateKey = "entitlement.lastVerified"
    /// Giorni di tolleranza senza rete prima di tornare a Free (le transazioni StoreKit 2 sono comunque firmate).
    private let offlineGraceDays = 14.0
    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private var started = false

    /// Id dell'account (Supabase) da allegare agli acquisti, se l'utente ha fatto l'accesso.
    @ObservationIgnored var accountToken: @MainActor () -> UUID? = { nil }
    /// Lettura del piano dal server (impostata all'avvio con `AccountService.fetchEntitlement`).
    @ObservationIgnored var serverCheck: @MainActor () async -> ServerCheck = { .signedOut }

    private let serverTierKey = "server.tier"
    private let serverUntilKey = "server.until"
    private let serverSourceKey = "server.source"
    private let serverDateKey = "server.verifiedAt"

    func start() async {
        guard !started else { return }
        started = true
        publish(.free)
        restoreCachedTier()
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let t) = result { await t.finish() }
                await self?.refresh()
            }
        }
        // Transazioni concluse mentre l'app era chiusa (per esempio acquisti in attesa di approvazione).
        for await result in Transaction.unfinished {
            if case .verified(let t) = result { await t.finish() }
        }
        await refresh()
    }

    /// Opzioni di acquisto: collega l'acquisto all'account, se presente.
    func purchaseOptions() -> Set<Product.PurchaseOption> {
        guard let token = accountToken() else { return [] }
        return [.appAccountToken(token)]
    }

    func restore() async { try? await AppStore.sync(); await refresh() }

    func refresh() async {
        var best: SubscriptionTier = .free
        var product: String?
        var expiry: Date?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let t) = result, t.revocationDate == nil, !t.isUpgraded else { continue }
            if let exp = t.expirationDate, exp < Date() { continue }
            let level = ProductID.tier(for: t.productID)
            if level > best || (level == best && product == nil) {
                best = level; product = t.productID; expiry = t.expirationDate
            }
        }
        publish(best)
        activeProductID = product
        renewalDate = expiry
        UserDefaults.standard.set(best.rawValue, forKey: cacheTierKey)
        UserDefaults.standard.set(Date(), forKey: cacheDateKey)
        await refreshServer()
    }

    /// Rilegge il piano dal server (all'avvio, all'accesso o all'uscita dall'account, al ritorno nell'app).
    func refreshServer() async {
        let d = UserDefaults.standard
        switch await serverCheck() {
        case .found(let tier, let until, let source):
            d.set(tier.rawValue, forKey: serverTierKey)
            d.set(until, forKey: serverUntilKey)
            d.set(source, forKey: serverSourceKey)
            d.set(Date(), forKey: serverDateKey)
        case .signedOut:
            [serverTierKey, serverUntilKey, serverSourceKey, serverDateKey].forEach { d.removeObject(forKey: $0) }
        case .unavailable:
            break
        }
        publish(realTier)
    }

    /// Piano dal server salvato, se ancora valido (non scaduto e verificato negli ultimi 14 giorni).
    private func serverTierNow() -> SubscriptionTier? {
        let d = UserDefaults.standard
        guard let verified = d.object(forKey: serverDateKey) as? Date,
              Date().timeIntervalSince(verified) < offlineGraceDays * 86400,
              let tier = SubscriptionTier(rawValue: d.integer(forKey: serverTierKey)) else { return nil }
        if let until = d.object(forKey: serverUntilKey) as? Date, until <= Date() { return nil }
        return tier
    }

    private func restoreCachedTier() {
        let d = UserDefaults.standard
        guard let date = d.object(forKey: cacheDateKey) as? Date,
              Date().timeIntervalSince(date) < offlineGraceDays * 86400,
              let tier = SubscriptionTier(rawValue: d.integer(forKey: cacheTierKey)) else { return }
        publish(tier)
    }

    /// Piano da StoreKit unito a quello del server, oppure quello simulato per i test (mai nelle versioni pubblicate).
    private func publish(_ real: SubscriptionTier) {
        realTier = real
        let server = serverTierNow()
        var best = real
        freeLicenseUntil = nil
        if let server, server > real {
            best = server
            if UserDefaults.standard.string(forKey: serverSourceKey) == "manual" {
                freeLicenseUntil = UserDefaults.standard.object(forKey: serverUntilKey) as? Date
            }
        }
        if TestTools.enabled {
            let simulated = AppSettings.shared.debugTier
            if simulated >= 0, let t = SubscriptionTier(rawValue: simulated) { tier = t; return }
        }
        tier = best
    }

    /// Solo build di debug: simula un piano (-1 = usa quello reale).
    func setDebugTier(_ value: Int) {
        guard TestTools.enabled else { return }
        AppSettings.shared.setDebugTier(value)
        publish(realTier)
    }
}
