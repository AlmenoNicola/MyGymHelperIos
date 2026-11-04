import Foundation
import Observation
import SwiftData
import MyGymHelperCore

/// Storico degli allenamenti. Contiene dati sulla salute: si salva solo con il consenso
/// e l'archivio e' escluso dai backup (iCloud) per mantenere i dati solo sul telefono.
@Model
final class WorkoutSessionRecord {
    var id: UUID = UUID()
    var startedAt: Date = Date()
    var endedAt: Date?
    var limb: String = "arm"
    var plannedSets: Int = 0
    var plannedReps: Int = 0
    var restSeconds: Int = 0
    var exerciseID: String = ""
    var exerciseName: String = ""
    var weightKg: Double = 0
    @Relationship(deleteRule: .cascade, inverse: \SetLogRecord.session) var sets: [SetLogRecord] = []

    init(startedAt: Date, endedAt: Date?, limb: String, plannedSets: Int, plannedReps: Int, restSeconds: Int,
         exerciseID: String = "", exerciseName: String = "", weightKg: Double = 0) {
        self.exerciseID = exerciseID
        self.exerciseName = exerciseName
        self.weightKg = weightKg
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.limb = limb
        self.plannedSets = plannedSets
        self.plannedReps = plannedReps
        self.restSeconds = restSeconds
    }
}

@Model
final class SetLogRecord {
    var number: Int = 0
    var plannedReps: Int = 0
    var doneReps: Int = 0
    var stoppedEarly: Bool = false
    var durationSeconds: Double = 0
    var averagePeak: Double = 0        // proxy della velocita' del movimento
    var lowConfidence: Bool = false    // segnale poco affidabile (per esempio telefono in tasca)
    /// Peso di questa serie (serie diverse). nil nelle serie salvate prima: vale il peso della sessione (`setWeightKg`).
    var weightKg: Double?
    var session: WorkoutSessionRecord?

    init(number: Int, plannedReps: Int, doneReps: Int, stoppedEarly: Bool,
         durationSeconds: Double, averagePeak: Double, lowConfidence: Bool, weightKg: Double? = nil) {
        self.weightKg = weightKg
        self.number = number
        self.plannedReps = plannedReps
        self.doneReps = doneReps
        self.stoppedEarly = stoppedEarly
        self.durationSeconds = durationSeconds
        self.averagePeak = averagePeak
        self.lowConfidence = lowConfidence
    }
}

extension SetLogRecord {
    /// Peso della serie (serie salvate prima delle serie diverse: quello della sessione).
    var setWeightKg: Double { weightKg ?? session?.weightKg ?? 0 }
}

extension WorkoutSessionRecord {
    /// Serie svolte in ordine, con ripetizioni obiettivo e peso di ognuna.
    var doneTargets: [SetTarget] {
        sets.sorted { $0.number < $1.number }.map { SetTarget(reps: $0.plannedReps, weightKg: $0.setWeightKg) }
    }

    /// Peso piu' alto usato nella sessione.
    var maxWeightKg: Double { (doneTargets.map(\.weightKg) + [weightKg]).max() ?? weightKg }

    /// Vero se le serie svolte avevano ripetizioni obiettivo o pesi diversi.
    var isVaried: Bool {
        let t = doneTargets
        guard let first = t.first else { return false }
        return t.contains { $0.reps != first.reps || abs($0.weightKg - first.weightKg) > 1e-9 }
    }

    /// Serie previste (ripetizioni e peso di ogni serie svolta); se la sessione e' finita prima, le serie mancanti
    /// fino a `plannedSets` ripetono l'ultima. Serve a riproporre lo stesso schema la volta dopo (come plannedTargets su Android).
    var plannedTargets: [SetTarget] {
        let done = doneTargets
        guard let last = done.last else {
            return Array(repeating: SetTarget(reps: plannedReps, weightKg: weightKg), count: max(plannedSets, 1))
        }
        return done + Array(repeating: last, count: max(plannedSets - done.count, 0))
    }
}

/// Elenco di esercizi salvato dall'utente: ogni esercizio con serie, ripetizioni, pausa e peso.
/// Le schermate lo usano tramite WorkoutListStore (qui sotto), che lo tiene anche solo in memoria senza consenso.
@Model
final class ExerciseListRecord {
    var id: UUID = UUID()
    var name: String = ""
    /// Id degli esercizi (sempre allineato a itemsData; gli elenchi creati prima avevano solo questo).
    var exerciseIDs: [String] = []
    var createdAt: Date = Date()
    /// Esercizi con i parametri: [WorkoutItem] in JSON.
    var itemsData: Data = Data()
    /// Finito un esercizio si propone il successivo (che parte solo quando l'utente lo avvia).
    var autoNext: Bool = false

    init(name: String, exerciseIDs: [String] = []) {
        self.name = name
        self.exerciseIDs = exerciseIDs
    }
}

/// Scheda di allenamento caricata dall'utente (piano Pro). `data` e' un TrainingPlan in JSON.
@Model
final class TrainingPlanRecord {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()
    var data: Data = Data()

    init(name: String, data: Data) {
        self.name = name
        self.data = data
    }
}

/// Scheda del nutrizionista caricata dall'utente (piano Pro). `data` e' un ParsedNutritionPlan in JSON.
@Model
final class NutritionPlanRecord {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var data: Data = Data()

    init(data: Data) { self.data = data }
}

/// Scheda creata con "Crea la tua scheda" (piano Pro). `data` e' il JSON di un CustomPlanRecord, con la stessa
/// struttura usata su Android dentro AppData ("customPlans"): vedi CustomPlanCodec nel Core.
/// Contiene dati sulla salute (eta', altezza, peso): si salva solo con il consenso, nell'archivio escluso dai backup.
@Model
final class CustomPlanEntity {
    var id: String = ""
    var createdAt: Int64 = 0
    var data: Data = Data()

    init(id: String, createdAt: Int64, data: Data) {
        self.id = id
        self.createdAt = createdAt
        self.data = data
    }
}

/// Profilo con dati sulla salute (peso, altezza, eta', obiettivo, dieta). Solo sul telefono.
@Model
final class HealthProfileRecord {
    var sex: String = "male"
    var age: Int = 30
    var heightCm: Double = 170
    var weightKg: Double = 70
    var activity: Double = 1.375
    var goal: String = "maintain"
    var diets: [String] = ["omnivore"]
    /// false finche' l'utente non sceglie l'obiettivo: si usa quello consigliato dal BMI (campo nuovo, migrazione automatica).
    var goalChosen: Bool = false

    init() {}
}

/// Elenchi di allenamento per le schermate (come gli elenchi dell'AppStore su Android).
/// Con il consenso sono salvati in SwiftData; senza, restano solo in memoria finche' l'app e' aperta:
/// ci si puo' allenare, ma non si salva nulla. Dato il consenso, quelli in memoria vengono salvati.
@Observable
@MainActor
final class WorkoutListStore {
    static let shared = WorkoutListStore()

    struct WorkoutList: Identifiable, Equatable {
        let id: UUID
        var name: String
        var items: [WorkoutItem]
        var autoNext: Bool
        var createdAt: Date
        var exerciseIDs: [String] { items.map(\.exerciseID) }
    }

    private(set) var lists: [WorkoutList] = []

    private var context: ModelContext { PersistenceController.container.mainContext }
    private var persistent: Bool { UserDefaults.standard.double(forKey: ConsentStore.grantedAtKey) > 0 }

    private init() {}

    /// Legge gli elenchi salvati (con il consenso) e converte quelli del formato precedente (solo id).
    func reload() {
        guard persistent else { return }
        let records = (try? context.fetch(FetchDescriptor<ExerciseListRecord>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        var result: [WorkoutList] = []
        for r in records {
            var items = WorkoutItem.decodeList(r.itemsData)
            if items.isEmpty && !r.exerciseIDs.isEmpty {
                items = r.exerciseIDs.map { WorkoutItem(exerciseID: $0) }
                r.itemsData = WorkoutItem.encodeList(items)
            }
            result.append(WorkoutList(id: r.id, name: r.name, items: items, autoNext: r.autoNext, createdAt: r.createdAt))
        }
        let memoryOnly = lists.filter { l in !records.contains { $0.id == l.id } }
        lists = result
        for l in memoryOnly { save(l) }
        try? context.save()
    }

    /// Dopo "Elimina dati" o la revoca del consenso.
    func clear() { lists = [] }

    func list(_ id: UUID?) -> WorkoutList? {
        guard let id else { return nil }
        return lists.first { $0.id == id }
    }

    @discardableResult
    func createList(name: String, items: [WorkoutItem] = []) -> UUID {
        let l = WorkoutList(id: UUID(), name: name, items: items, autoNext: false, createdAt: Date())
        save(l)
        return l.id
    }

    /// Dalla scheda Esercizi: aggiunge l'esercizio con i parametri di partenza (una volta sola per elenco).
    func addToList(_ id: UUID, exerciseID: String) {
        update(id) { l in if !l.exerciseIDs.contains(exerciseID) { l.items.append(WorkoutItem(exerciseID: exerciseID)) } }
    }
    func addItem(_ item: WorkoutItem, to id: UUID) { update(id) { $0.items.append(item) } }
    func updateItem(_ item: WorkoutItem, in id: UUID) {
        update(id) { l in if let i = l.items.firstIndex(where: { $0.id == item.id }) { l.items[i] = item } }
    }
    func deleteItem(_ itemID: UUID, from id: UUID) { update(id) { l in l.items.removeAll { $0.id == itemID } } }
    func setDone(_ itemID: UUID, in id: UUID, done: Bool = true) {
        update(id) { l in if let i = l.items.firstIndex(where: { $0.id == itemID }) { l.items[i].done = done } }
    }
    /// "Reset": tutti gli esercizi tornano da fare.
    func reset(_ id: UUID) { update(id) { l in for i in l.items.indices { l.items[i].done = false } } }
    func setAutoNext(_ on: Bool, for id: UUID) { update(id) { $0.autoNext = on } }
    /// Sostituisce gli esercizi di un elenco (scheda pronta usata sull'elenco attuale).
    func replaceItems(_ items: [WorkoutItem], in id: UUID) { update(id) { $0.items = items } }
    /// Allenamento di una scheda pronta come elenco: se c'e' gia' un elenco con lo stesso nome se ne rinnovano gli
    /// esercizi (tutti da fare), altrimenti se ne crea uno. Restituisce l'id. Come upsertList su Android.
    @discardableResult
    func upsertList(name: String, items: [WorkoutItem]) -> UUID {
        if let existing = lists.first(where: { $0.name == name }) { replaceItems(items, in: existing.id); return existing.id }
        return createList(name: name, items: items)
    }
    func deleteList(_ id: UUID) {
        lists.removeAll { $0.id == id }
        if persistent, let r = record(id) { context.delete(r); try? context.save() }
    }

    private func update(_ id: UUID, _ change: (inout WorkoutList) -> Void) {
        guard var l = list(id) else { return }
        change(&l)
        save(l)
    }

    private func record(_ id: UUID) -> ExerciseListRecord? {
        var descriptor = FetchDescriptor<ExerciseListRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func save(_ l: WorkoutList) {
        if let i = lists.firstIndex(where: { $0.id == l.id }) { lists[i] = l } else { lists.append(l) }
        guard persistent else { return }          // senza consenso solo in memoria
        let r: ExerciseListRecord
        if let existing = record(l.id) {
            r = existing
        } else {
            r = ExerciseListRecord(name: l.name)
            r.id = l.id
            r.createdAt = l.createdAt
            context.insert(r)
        }
        r.name = l.name
        r.autoNext = l.autoNext
        r.exerciseIDs = l.exerciseIDs
        r.itemsData = WorkoutItem.encodeList(l.items)
        try? context.save()
    }
}

/// Schede create con "Crea la tua scheda" (come saveCustomPlan / renameCustomPlan / deleteCustomPlan dell'AppStore
/// su Android). Si salvano solo con il consenso ai dati sulla salute (il modulo senza consenso non si apre).
@Observable
@MainActor
final class CustomPlanStore {
    static let shared = CustomPlanStore()

    /// Schede create, dalla piu' recente.
    private(set) var plans: [CustomPlanRecord] = []

    private var context: ModelContext { PersistenceController.container.mainContext }
    private var persistent: Bool { UserDefaults.standard.double(forKey: ConsentStore.grantedAtKey) > 0 }

    private init() {}

    func reload() {
        guard persistent else { plans = []; return }
        let rows = (try? context.fetch(FetchDescriptor<CustomPlanEntity>())) ?? []
        plans = rows.flatMap { CustomPlanCodec.decodeJSON($0.data) }.sorted { $0.createdAt > $1.createdAt }
    }

    func record(id: String) -> CustomPlanRecord? { plans.first { $0.id == id } }

    /// Record della scheda dall'id della scheda ("custom:<id>"), se c'e'.
    func record(planID: String) -> CustomPlanRecord? {
        guard planID.hasPrefix(CustomPlanGenerator.idPrefix) else { return nil }
        return record(id: String(planID.dropFirst(CustomPlanGenerator.idPrefix.count)))
    }

    /// Nuova scheda o scheda rifatta (stesso id: si sostituisce).
    func save(_ r: CustomPlanRecord) {
        guard persistent else { return }
        let data = CustomPlanCodec.encodeJSON([r])
        if let row = entity(r.id) {
            row.data = data
            row.createdAt = r.createdAt
        } else {
            context.insert(CustomPlanEntity(id: r.id, createdAt: r.createdAt, data: data))
        }
        try? context.save()
        reload()
    }

    func rename(_ id: String, to name: String) {
        guard var r = record(id: id) else { return }
        r.name = name
        save(r)
    }

    /// Gli elenchi gia' creati da questa scheda restano.
    func delete(_ id: String) {
        if let row = entity(id) { context.delete(row); try? context.save() }
        reload()
    }

    /// Dopo "Elimina dati" o la revoca del consenso.
    func clear() { plans = [] }

    private func entity(_ id: String) -> CustomPlanEntity? {
        var descriptor = FetchDescriptor<CustomPlanEntity>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}

enum PersistenceController {
    static let container: ModelContainer = {
        let schema = Schema([WorkoutSessionRecord.self, SetLogRecord.self, ExerciseListRecord.self,
                             TrainingPlanRecord.self, NutritionPlanRecord.self, HealthProfileRecord.self,
                             CustomPlanEntity.self])
        var dir = URL.applicationSupportDirectory.appending(path: "MyGymHelperData", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? dir.setResourceValues(values)
        let config = ModelConfiguration(schema: schema, url: dir.appending(path: "store.sqlite"))
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Impossibile aprire l'archivio locale: \(error)")
        }
    }()
}
