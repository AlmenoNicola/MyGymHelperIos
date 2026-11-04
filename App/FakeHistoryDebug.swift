import SwiftUI
import SwiftData
import MyGymHelperCore

/// Strumenti di test anche fuori dalle build di debug: vedi `TestTools`.
enum TestTools {
    /// Build di debug (Xcode) o AppFlags.testTools acceso (da spegnere prima della pubblicazione).
    static var enabled: Bool {
        #if DEBUG
        return true
        #else
        return AppFlags.testTools
        #endif
    }
}

/// Strumenti di test: cronologia finta per provare la revisione della scheda ogni due settimane (piano Pro).
/// Crea sessioni degli esercizi della scheda attiva negli ultimi 12 giorni, sposta indietro le date delle schede
/// e azzera la revisione: la domanda compare alla prossima fine allenamento di un esercizio della scheda.
/// Gli id delle sessioni finte si ricordano in UserDefaults per poterle togliere. Come FakeHistoryCard su Android.
@MainActor
enum FakeHistoryDebug {
    private static let idsKey = "debug.fakeSessionIDs"
    private static var context: ModelContext { PersistenceController.container.mainContext }

    /// Sessioni create; -1 senza consenso, 0 se non c'e' una scheda con esercizi del catalogo.
    static func add(_ kind: FakeHistoryKind, catalog: [CatalogExercise], now: Date = Date()) -> Int {
        guard UserDefaults.standard.double(forKey: ConsentStore.grantedAtKey) > 0 else { return -1 }
        let plans = (try? context.fetch(FetchDescriptor<TrainingPlanRecord>())) ?? []
        guard let active = PlanReviewStore.activePlan(plans) else { return 0 }
        let entries = active.plan.allEntries.compactMap { e in PlanAI.exercise(for: e, in: catalog).map { (e, $0) } }
        let fake = FakePlanHistory.sessions(entries, kind: kind, now: now)
        guard !fake.isEmpty else { return 0 }
        _ = remove()
        var ids: [String] = []
        for f in fake {
            let ex = catalog.first { $0.id == f.exerciseID }
            let s = WorkoutSessionRecord(startedAt: f.startedAt, endedAt: f.startedAt.addingTimeInterval(300),
                                         limb: WorkoutListLogic.suggestedPosition(ex).rawValue, plannedSets: f.sets.count,
                                         plannedReps: f.sets[0].plannedReps, restSeconds: f.restSeconds,
                                         exerciseID: f.exerciseID, exerciseName: f.exerciseName, weightKg: f.weightKg)
            for set in f.sets {
                s.sets.append(SetLogRecord(number: set.number, plannedReps: set.plannedReps, doneReps: set.doneReps,
                                           stoppedEarly: set.stoppedEarly, durationSeconds: Double(set.doneReps) * 2.5,
                                           averagePeak: set.averagePeak, lowConfidence: false, weightKg: set.weightKg))
            }
            context.insert(s)
            ids.append(s.id.uuidString)
        }
        let shift = FakePlanHistory.planShift(activeCreatedAt: active.record.createdAt, now: now)
        if shift != 0 { for p in plans { p.createdAt = p.createdAt.addingTimeInterval(shift) } }
        try? context.save()
        UserDefaults.standard.set(ids, forKey: idsKey)
        PlanReviewStore.shared.resetForTests()
        return fake.count
    }

    /// Toglie le sessioni finte (le date delle schede restano spostate). Restituisce quante ne ha tolte.
    static func remove() -> Int {
        let ids = Set(UserDefaults.standard.stringArray(forKey: idsKey) ?? [])
        guard !ids.isEmpty else { return 0 }
        let sessions = (try? context.fetch(FetchDescriptor<WorkoutSessionRecord>())) ?? []
        var n = 0
        for s in sessions where ids.contains(s.id.uuidString) { context.delete(s); n += 1 }
        try? context.save()
        UserDefaults.standard.removeObject(forKey: idsKey)
        return n
    }
}

/// Riquadro di test nell'Area personale e nel dettaglio della scheda.
struct FakeHistoryCard: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(SubscriptionManager.self) private var subscriptions
    @State private var result: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("debug.fakeHistory.title").font(.headline).foregroundStyle(.orange)
            Text("debug.fakeHistory.note").font(.caption).foregroundStyle(.secondary)
            if subscriptions.tier != .full {
                Button { subscriptions.setDebugTier(SubscriptionTier.full.rawValue) } label: {
                    Text("debug.fakeHistory.full").frame(maxWidth: .infinity)
                }.buttonStyle(.glass)
            }
            Button { add(.easy) } label: { Text("debug.fakeHistory.easy").frame(maxWidth: .infinity) }.buttonStyle(.glass)
            Button { add(.hard) } label: { Text("debug.fakeHistory.hard").frame(maxWidth: .infinity) }.buttonStyle(.glass)
            Button(role: .destructive) {
                result = String(localized: "debug.fakeHistory.removed \(FakeHistoryDebug.remove())")
            } label: { Text("debug.fakeHistory.remove").frame(maxWidth: .infinity) }.buttonStyle(.glass)
            if let result { Text(verbatim: result).font(.footnote).foregroundStyle(Theme.accent) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func add(_ kind: FakeHistoryKind) {
        let n = FakeHistoryDebug.add(kind, catalog: catalog.all)
        result = n < 0 ? String(localized: "debug.fakeHistory.noConsent")
            : n == 0 ? String(localized: "debug.fakeHistory.noPlan")
            : String(localized: "debug.fakeHistory.created \(n)")
    }
}
