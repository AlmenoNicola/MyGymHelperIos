import Foundation

// MARK: - Scheda personalizzata (uguale su Android: CustomPlans.kt)
// L'utente inserisce sesso, età, altezza, peso, obiettivo, esperienza, allenamenti a settimana e luogo:
// la scheda si crea sul telefono con regole fisse (nessuna API esterna: i dati sulla salute non escono dal telefono).

/// Esperienza dichiarata dall'utente.
public enum Experience: String, CaseIterable, Sendable, Codable {
    case beginner, intermediate, advanced
    public static func from(_ raw: String) -> Experience { Experience(rawValue: raw) ?? .beginner }
}

/// Dove ci si allena: palestra (tutti gli attrezzi), casa (corpo libero + attrezzi in casa), solo corpo libero.
public enum TrainingPlace: String, CaseIterable, Sendable, Codable {
    case gym, home, bodyweight
    public static func from(_ raw: String) -> TrainingPlace { TrainingPlace(rawValue: raw) ?? .gym }
}

/// Dati del profilo che servono alla scheda (sull'app vengono da HealthProfileRecord). Stessi valori predefiniti
/// del profilo su Android (HealthProfile in AppData.kt) e su iOS (HealthProfileRecord).
public struct HealthProfile: Equatable, Sendable {
    public var sex: String
    public var age: Int
    public var heightCm: Double
    public var weightKg: Double
    public var goal: String
    /// false finché l'utente non sceglie l'obiettivo: si usa quello consigliato dal BMI.
    public var goalChosen: Bool
    public init(sex: String = "male", age: Int = 30, heightCm: Double = 170, weightKg: Double = 70,
                goal: String = "maintain", goalChosen: Bool = false) {
        self.sex = sex; self.age = age; self.heightCm = heightCm; self.weightKg = weightKg
        self.goal = goal; self.goalChosen = goalChosen
    }
}

/// Dati inseriti per creare la scheda (si salvano con la scheda, per poterla rifare).
public struct CustomPlanInput: Equatable, Hashable, Sendable {
    public var sex: BiologicalSex
    public var age: Int
    public var heightCm: Double
    public var weightKg: Double
    public var goal: Goal
    public var experience: Experience
    /// Sempre 2, 3 o 4.
    public var daysPerWeek: Int
    public var place: TrainingPlace
    /// Attrezzi in casa usati se `place` = .home (nomi di `HomeEquipment.choices`).
    public var ownedEquipment: Set<String>

    public init(sex: BiologicalSex = .male, age: Int = 30, heightCm: Double = 170, weightKg: Double = 70,
                goal: Goal = .maintain, experience: Experience = .beginner, daysPerWeek: Int = 3,
                place: TrainingPlace = .gym, ownedEquipment: Set<String> = []) {
        self.sex = sex; self.age = age; self.heightCm = heightCm; self.weightKg = weightKg; self.goal = goal
        self.experience = experience; self.daysPerWeek = daysPerWeek; self.place = place; self.ownedEquipment = ownedEquipment
    }

    /// Valori nei limiti dell'app (stessi del profilo: età 18-100, altezza 120-230 cm, peso 30-250 kg).
    public func clamped() -> CustomPlanInput {
        var c = self
        c.age = min(max(age, 18), 100)
        c.heightCm = min(max(heightCm, 120), 230)
        c.weightKg = min(max(weightKg, 30), 250)
        c.daysPerWeek = min(max(daysPerWeek, 2), 4)   // Sempre 2, 3 o 4
        c.ownedEquipment = ownedEquipment.filter { HomeEquipment.choices.contains($0) }
        return c
    }

    public var bmi: BMIResult? { BMICalculator.calculate(weightKg: weightKg, heightCm: heightCm) }

    /// Valori di partenza dal profilo salvato; obiettivo scelto o, se no, quello consigliato dal BMI.
    public static func fromProfile(_ p: HealthProfile?, owned: Set<String> = []) -> CustomPlanInput {
        let profile = p ?? HealthProfile()
        return CustomPlanInput(
            sex: BiologicalSex(rawValue: profile.sex) ?? .male, age: profile.age,
            heightCm: profile.heightCm, weightKg: profile.weightKg,
            goal: NutritionCalculator.effectiveGoal(chosen: profile.goalChosen, goalRaw: profile.goal,
                                                    weightKg: profile.weightKg, heightCm: profile.heightCm),
            ownedEquipment: owned).clamped()
    }
}

/// Scheda creata dall'utente: nome modificabile, dati inseriti e allenamenti.
public struct CustomPlanRecord: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    /// Millisecondi dal 1970 (come su Android).
    public var createdAt: Int64
    public var input: CustomPlanInput
    public var plan: PresetPlan

    public init(id: String = UUID().uuidString.lowercased(), name: String,
                createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
                input: CustomPlanInput, plan: PresetPlan) {
        self.id = id; self.name = name; self.createdAt = createdAt; self.input = input; self.plan = plan
    }
}

/// Note mostrate sopra la scheda creata: perché è fatta così (chiavi di traduzione).
public struct CustomPlanNotes: Equatable, Sendable {
    public let bmi: BMIResult?
    /// Calorie indicative al giorno per l'obiettivo (Mifflin-St Jeor, attività dagli allenamenti a settimana).
    public let dailyCalories: Int
    /// Esercizi a impatto (salti) esclusi: BMI da obesità o età da 65 anni.
    public let lowImpact: Bool
    /// Pause più lunghe e ripetizioni non sotto 10: età da 50 anni.
    public let gentleLoads: Bool
}

public enum CustomPlanGenerator {
    /// Prefisso dell'id della scheda (PresetPlan.id = "custom:<id record>"), per distinguerla dalle schede pronte.
    public static let idPrefix = "custom:"
    public static let maxPlans = 20

    // Muscoli di ogni allenamento in ordine di priorità: se ne prendono i primi N secondo l'esperienza.
    static let fullA: [MuscleGroup] = [.quads, .chest, .lats, .hamstrings, .abs, .shoulders, .biceps]
    static let fullB: [MuscleGroup] = [.hamstrings, .chest, .traps, .glutes, .abs, .shoulders, .triceps]
    static let fullC: [MuscleGroup] = [.glutes, .lats, .shoulders, .quads, .abs, .chest, .calves]
    static let push: [MuscleGroup] = [.chest, .shoulders, .chest, .triceps, .abs, .shoulders, .triceps]
    static let pull: [MuscleGroup] = [.lats, .traps, .lats, .biceps, .abs, .traps, .biceps]
    static let legs: [MuscleGroup] = [.quads, .hamstrings, .glutes, .quads, .abs, .calves, .hamstrings]
    static let upper: [MuscleGroup] = [.chest, .lats, .shoulders, .traps, .biceps, .triceps, .chest]
    static let lower: [MuscleGroup] = [.quads, .hamstrings, .glutes, .calves, .abs, .quads, .obliques]
    static let twoA: [MuscleGroup] = [.quads, .chest, .lats, .hamstrings, .abs, .shoulders, .biceps]
    static let twoB: [MuscleGroup] = [.glutes, .lats, .chest, .quads, .abs, .triceps, .calves]

    static let excludedCategories: Set<String> = ["olympic", "strongman"]

    /// Esercizi per allenamento (senza il finale pliometrico del dimagrimento).
    public static func exercisesPerDay(_ e: Experience) -> Int {
        switch e { case .beginner: return 5; case .intermediate: return 6; case .advanced: return 7 }
    }

    /// Divisione della settimana:
    /// - 4 allenamenti → parte alta / parte bassa (A e B);
    /// - 2 allenamenti → total body A e B (ogni livello di esperienza);
    /// - 3 allenamenti, principiante → total body A/B/C;
    /// - 3 allenamenti, intermedio o avanzato → push / pull / legs.
    public static func split(_ input: CustomPlanInput) -> [(String, [MuscleGroup])] {
        if input.daysPerWeek >= 4 {
            return [("presets.day.upperA", upper), ("presets.day.lowerA", lower),
                    ("presets.day.upperB", upper), ("presets.day.lowerB", lower)]
        }
        // 2 allenamenti → total body A e B (ogni livello di esperienza)
        if input.daysPerWeek <= 2 {
            return [("presets.day.a", twoA), ("presets.day.b", twoB)]
        }
        if input.experience == .beginner {
            return [("presets.day.a", fullA), ("presets.day.b", fullB), ("presets.day.c", fullC)]
        }
        return [("presets.day.push", push), ("presets.day.pull", pull), ("presets.day.legs", legs)]
    }

    /// Niente salti con BMI da obesità o dai 65 anni.
    public static func isLowImpact(_ input: CustomPlanInput) -> Bool {
        input.age >= 65 || input.bmi?.category == .obese
    }

    /// Dai 50 anni: pause più lunghe e mai meno di 10 ripetizioni.
    public static func gentleLoads(_ input: CustomPlanInput) -> Bool { input.age >= 50 }

    /// L'esercizio si può fare dove si allena l'utente?
    public static func isDoable(_ ex: CatalogExercise, _ input: CustomPlanInput) -> Bool {
        switch input.place {
        case .gym: return true
        case .home: return HomeEquipment.isDoable(ex, owned: input.ownedEquipment)
        case .bodyweight: return HomeEquipment.alwaysAvailable.contains(ex.equipment)
        }
    }

    /// Esercizi di tenuta (plank): si contano male a ripetizioni, per gli addominali vengono dopo.
    static func isHold(_ ex: CatalogExercise) -> Bool { ex.id.range(of: "plank", options: .caseInsensitive) != nil }

    static func levelAllowed(_ ex: CatalogExercise, _ e: Experience) -> Bool {
        switch e {
        case .beginner: return ex.level == "beginner" || ex.level.isEmpty
        case .intermediate: return ex.level != "expert"
        case .advanced: return true
        }
    }

    public static func notes(_ input: CustomPlanInput) -> CustomPlanNotes {
        let i = input.clamped()
        let activity: ActivityLevel = i.daysPerWeek >= 4 ? .moderate : .light
        let kcal = NutritionCalculator.targets(sex: i.sex, weightKg: i.weightKg, heightCm: i.heightCm,
                                               ageYears: i.age, activity: activity, goal: i.goal).calories
        return CustomPlanNotes(bmi: i.bmi, dailyCalories: kcal, lowImpact: isLowImpact(i), gentleLoads: gentleLoads(i))
    }

    /// Ordinamento stabile con criteri in sequenza (come sortedWith(compareBy ... thenBy ...) in Kotlin):
    /// `key` restituisce i criteri (false prima di true), poi l'hash; a parità resta l'ordine di partenza.
    private static func stableSorted(_ list: [CatalogExercise], flags: (CatalogExercise) -> [Bool],
                                     hash: (CatalogExercise) -> UInt32) -> [CatalogExercise] {
        let keyed = list.enumerated().map { (offset: $0.offset, ex: $0.element, flags: flags($0.element), hash: hash($0.element)) }
        return keyed.sorted { a, b in
            for (fa, fb) in zip(a.flags, b.flags) where fa != fb { return !fa }   // false < true
            if a.hash != b.hash { return a.hash < b.hash }
            return a.offset < b.offset
        }.map(\.ex)
    }

    /// Crea la scheda. `seed` (di solito l'id del record) cambia la scelta tra esercizi equivalenti, così due schede
    /// con gli stessi dati possono essere diverse; con lo stesso seed il risultato è sempre lo stesso (anche su Android).
    /// Regole:
    /// - per ogni muscolo del giorno un esercizio con quel muscolo principale, fattibile nel luogo scelto e adatto
    ///   all'esperienza (principiante: solo esercizi per principianti); alla prima volta che il muscolo compare nel
    ///   giorno prima i multiarticolari (per gli addominali gli esercizi a ripetizioni prima del plank), poi gli
    ///   esercizi base dell'app; mai lo stesso esercizio due volte nella scheda (se non ce ne sono altri si ripete,
    ///   ma mai nello stesso giorno);
    /// - serie, ripetizioni e pausa secondo obiettivo ed esperienza (`parametersFor`);
    /// - dimagrimento: in fondo a ogni allenamento un esercizio pliometrico (a meno che sia a basso impatto).
    public static func generate(_ input: CustomPlanInput, catalog: [CatalogExercise], seed: String,
                                planID: String? = nil) -> PresetPlan {
        let i = input.clamped()
        let lowImpact = isLowImpact(i)
        let pool = catalog.filter { ex in
            ex.isTraining && !excludedCategories.contains(ex.category) && levelAllowed(ex, i.experience) && isDoable(ex, i)
                && !(lowImpact && ex.kind == .plyometrics)
        }
        let count = exercisesPerDay(i.experience)
        var used = Set<String>()
        var days: [PresetDay] = []
        for (key, muscles) in split(i) {
            var today = Set<String>()
            var seen: [MuscleGroup: Int] = [:]
            var items: [PresetItem] = []
            for m in muscles {
                if items.count >= count { break }
                let k = seen[m] ?? 0
                seen[m] = k + 1
                let core = m == .abs || m == .obliques
                let filtered = pool.filter { $0.primary.first == m && $0.kind == .strength && !today.contains($0.id) }
                let candidates = stableSorted(filtered, flags: { ex in
                    [(k == 0 && !core) ? !ex.isCompound : false,
                     // Addominali: prima gli esercizi a ripetizioni (crunch...) delle tenute come il plank
                     core ? isHold(ex) : false,
                     !ex.id.hasPrefix("seed-")]
                }, hash: { MonthlyPlanner.stableHash($0.id + seed) })
                guard let pick = candidates.first(where: { !used.contains($0.id) }) ?? candidates.first else { continue }
                used.insert(pick.id); today.insert(pick.id)
                items.append(parametersFor(pick, muscle: m, i))
            }
            // Dimagrimento: finale pliometrico (salti) per alzare il dispendio
            if i.goal == .lose && !lowImpact {
                let plyo = pool.filter { $0.kind == .plyometrics && !today.contains($0.id) }
                if let f = stableSorted(plyo, flags: { [used.contains($0.id)] },
                                        hash: { MonthlyPlanner.stableHash($0.id + seed) }).first {
                    used.insert(f.id)
                    items.append(PresetItem(f.id, sets: 3, reps: 15, restSeconds: 30))
                }
            }
            if !items.isEmpty { days.append(PresetDay(titleKey: key, items: items)) }
        }
        let level: String
        switch i.experience { case .beginner: level = "beginner"; case .intermediate: level = "intermediate"; case .advanced: level = "expert" }
        return PresetPlan(id: planID ?? idPrefix + seed, titleKey: "custom.title", level: level,
                          daysPerWeek: i.daysPerWeek, days: days)
    }

    /// Serie × ripetizioni, pausa (secondi):
    /// - aumento massa: multiarticolari 3×10 90" (principiante), 4×8 120" (intermedio), 4×6 150" (avanzato);
    ///   complementari 3×12 60", 3×10 75", 4×10 75";
    /// - mantenimento: multiarticolari 3×10 90" (avanzato 4×8 90"); complementari 3×12 60";
    /// - dimagrimento: multiarticolari 3×12 60" (avanzato 4×12 60"); complementari 3×15 45";
    /// - addominali 3×15 45" (dimagrimento 3×20 30"); polpacci 4×15 60";
    /// - dai 50 anni: ripetizioni almeno 10 e +30" di pausa sui multiarticolari; dai 65 anni al massimo 3 serie.
    static func parametersFor(_ ex: CatalogExercise, muscle: MuscleGroup, _ i: CustomPlanInput) -> PresetItem {
        let e = i.experience
        var (sets, reps, rest): (Int, Int, Int)
        if muscle == .abs || muscle == .obliques {
            (sets, reps, rest) = i.goal == .lose ? (3, 20, 30) : (3, 15, 45)
        } else if muscle == .calves {
            (sets, reps, rest) = (4, 15, 60)
        } else if ex.isCompound {
            switch i.goal {
            case .gain:
                switch e { case .beginner: (sets, reps, rest) = (3, 10, 90); case .intermediate: (sets, reps, rest) = (4, 8, 120); case .advanced: (sets, reps, rest) = (4, 6, 150) }
            case .maintain: (sets, reps, rest) = e == .advanced ? (4, 8, 90) : (3, 10, 90)
            case .lose: (sets, reps, rest) = e == .advanced ? (4, 12, 60) : (3, 12, 60)
            }
        } else {
            switch i.goal {
            case .gain:
                switch e { case .beginner: (sets, reps, rest) = (3, 12, 60); case .intermediate: (sets, reps, rest) = (3, 10, 75); case .advanced: (sets, reps, rest) = (4, 10, 75) }
            case .maintain: (sets, reps, rest) = (3, 12, 60)
            case .lose: (sets, reps, rest) = (3, 15, 45)
            }
        }
        if gentleLoads(i) {
            reps = max(reps, 10)
            if ex.isCompound { rest += 30 }
        }
        if i.age >= 65 { sets = min(sets, 3) }
        return PresetItem(ex.id, sets: sets, reps: reps, restSeconds: rest)
    }

    /// Nome proposto: "La mia scheda", "La mia scheda 2" ... (il testo base arriva tradotto dall'app).
    public static func suggestedName(_ base: String, existing: [CustomPlanRecord]) -> String {
        let names = Set(existing.map(\.name))
        if !names.contains(base) { return base }
        var n = 2
        while names.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }
}

/// Conversione JSON delle schede create: stessa struttura di Android (dentro AppData, chiave "customPlans").
/// Su iOS ogni scheda si salva in SwiftData (CustomPlanEntity) con questo JSON.
public enum CustomPlanCodec {
    public static func encode(_ list: [CustomPlanRecord]) -> [[String: Any]] {
        list.map { r in
            [
                "id": r.id, "name": r.name, "createdAt": r.createdAt,
                "input": [
                    "sex": r.input.sex.rawValue, "age": r.input.age, "heightCm": r.input.heightCm,
                    "weightKg": r.input.weightKg, "goal": r.input.goal.rawValue, "experience": r.input.experience.rawValue,
                    "daysPerWeek": r.input.daysPerWeek, "place": r.input.place.rawValue,
                    "ownedEquipment": HomeEquipment.choices.filter { r.input.ownedEquipment.contains($0) }
                ] as [String: Any],
                "plan": [
                    "level": r.plan.level, "daysPerWeek": r.plan.daysPerWeek,
                    "days": r.plan.days.map { d in
                        ["titleKey": d.titleKey, "items": d.items.map { p in
                            ["exerciseId": p.exerciseID, "sets": p.sets, "reps": p.reps,
                             "restSeconds": p.restSeconds, "weightKg": p.weightKg] as [String: Any]
                        }] as [String: Any]
                    }
                ] as [String: Any]
            ]
        }
    }

    public static func decode(_ v: Any?) -> [CustomPlanRecord] {
        guard let arr = v as? [Any] else { return [] }
        return arr.compactMap { rv -> CustomPlanRecord? in
            guard let r = rv as? [String: Any], let id = r["id"] as? String,
                  let iv = r["input"] as? [String: Any] else { return nil }
            let input = CustomPlanInput(
                sex: BiologicalSex(rawValue: str(iv["sex"]) ?? "male") ?? .male,
                age: int(iv["age"]) ?? 30, heightCm: num(iv["heightCm"]) ?? 170, weightKg: num(iv["weightKg"]) ?? 70,
                goal: Goal(rawValue: str(iv["goal"]) ?? "maintain") ?? .maintain,
                experience: .from(str(iv["experience"]) ?? "beginner"), daysPerWeek: int(iv["daysPerWeek"]) ?? 3,
                place: .from(str(iv["place"]) ?? "gym"),
                ownedEquipment: Set((iv["ownedEquipment"] as? [Any] ?? []).compactMap { $0 as? String })).clamped()
            guard let pv = r["plan"] as? [String: Any] else { return nil }
            let days: [PresetDay] = (pv["days"] as? [Any] ?? []).compactMap { dv in
                guard let d = dv as? [String: Any], let title = str(d["titleKey"]) else { return nil }
                let items: [PresetItem] = (d["items"] as? [Any] ?? []).compactMap { pi in
                    guard let p = pi as? [String: Any], let exID = str(p["exerciseId"]) else { return nil }
                    return PresetItem(exID, sets: int(p["sets"]) ?? 3, reps: int(p["reps"]) ?? 10,
                                      restSeconds: int(p["restSeconds"]) ?? 90, weightKg: num(p["weightKg"]) ?? 0)
                }
                return PresetDay(titleKey: title, items: items)
            }
            return CustomPlanRecord(id: id, name: str(r["name"]) ?? "", createdAt: num(r["createdAt"]).map { Int64($0) } ?? 0,
                                    input: input,
                                    plan: PresetPlan(id: CustomPlanGenerator.idPrefix + id, titleKey: "custom.title",
                                                     level: str(pv["level"]) ?? "beginner",
                                                     daysPerWeek: int(pv["daysPerWeek"]) ?? input.daysPerWeek, days: days))
        }
    }

    /// JSON completo con la chiave "customPlans" (come in AppData su Android).
    public static func encodeJSON(_ list: [CustomPlanRecord]) -> Data {
        (try? JSONSerialization.data(withJSONObject: ["customPlans": encode(list)], options: [.sortedKeys])) ?? Data()
    }

    /// Lettura del JSON completo: senza la chiave (dati salvati prima) o con dati non validi, nessuna scheda.
    public static func decodeJSON(_ data: Data) -> [CustomPlanRecord] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        return decode(obj["customPlans"])
    }

    // Letture tolleranti dei valori JSON (numeri come Int, Double o NSNumber).
    static func str(_ v: Any?) -> String? { v as? String }
    static func num(_ v: Any?) -> Double? {
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        if let i = v as? Int64 { return Double(i) }
        if let n = v as? NSNumber { return n.doubleValue }
        return nil
    }
    static func int(_ v: Any?) -> Int? {
        if let i = v as? Int { return i }
        if let d = num(v) { return Int(d) }
        return nil
    }
}
