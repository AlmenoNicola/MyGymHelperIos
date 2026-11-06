import Foundation

// MARK: - Schede pronte e scheda consigliata del mese (uguale su Android: Presets.kt)

/// Esercizio di una scheda pronta. `weightKg` = 0 per le schede fisse (il peso lo sceglie l'utente).
public struct PresetItem: Equatable, Hashable, Sendable, Codable {
    public var exerciseID: String
    public var sets: Int
    public var reps: Int
    public var restSeconds: Int
    public var weightKg: Double

    public init(_ exerciseID: String, sets: Int, reps: Int, restSeconds: Int, weightKg: Double = 0) {
        self.exerciseID = exerciseID; self.sets = sets; self.reps = reps; self.restSeconds = restSeconds; self.weightKg = weightKg
    }

    public var parameters: WorkoutParameters {
        WorkoutParameters(sets: sets, reps: reps, restSeconds: restSeconds, weightKg: weightKg).clamped()
    }
    public func workoutItem() -> WorkoutItem { WorkoutItem(exerciseID: exerciseID).with(parameters) }
}

/// Un allenamento della scheda (giorno A, Push, Upper ...). Titolo = chiave di traduzione.
public struct PresetDay: Equatable, Hashable, Sendable, Codable {
    public var titleKey: String
    public var items: [PresetItem]
    public init(titleKey: String, items: [PresetItem]) { self.titleKey = titleKey; self.items = items }
}

/// Scheda pronta: `titleKey` (con `<titleKey>.summary` per la descrizione), `level` (beginner/intermediate),
/// allenamenti consigliati a settimana e giorni. Le schede non si modificano: si usa un giorno, che diventa un elenco.
public struct PresetPlan: Identifiable, Equatable, Hashable, Sendable, Codable {
    public var id: String
    public var titleKey: String
    public var level: String
    public var daysPerWeek: Int
    public var days: [PresetDay]
    public init(id: String, titleKey: String, level: String, daysPerWeek: Int, days: [PresetDay]) {
        self.id = id; self.titleKey = titleKey; self.level = level; self.daysPerWeek = daysPerWeek; self.days = days
    }
    public var summaryKey: String { "\(titleKey).summary" }
}

/// Sessione dello storico ridotta a cio' che serve alle schede (l'app la ricava da WorkoutSessionRecord).
public struct SessionSummary: Sendable {
    public let exerciseID: String
    public let startedAt: Date
    /// Serie fatte (o pianificate, se non registrate).
    public let sets: Int
    public let weightKg: Double
    public init(exerciseID: String, startedAt: Date, sets: Int, weightKg: Double) {
        self.exerciseID = exerciseID; self.startedAt = startedAt; self.sets = sets; self.weightKg = weightKg
    }
}

public enum PresetPlans {
    public static let freeID = "free-total-body"

    // GENERATO-INIZIO da android/tools/preset_plans.py: non modificare a mano
    public static let freeTotalBody = PresetPlan(id: "free-total-body", titleKey: "presets.free", level: "beginner", daysPerWeek: 3, days: [
        PresetDay(titleKey: "presets.day.single", items: [
            PresetItem("seed-squat", sets: 3, reps: 10, restSeconds: 120),
            PresetItem("seed-bench-press", sets: 3, reps: 10, restSeconds: 120),
            PresetItem("seed-lat-pulldown", sets: 3, reps: 10, restSeconds: 90),
            PresetItem("seed-overhead-press", sets: 3, reps: 10, restSeconds: 90),
            PresetItem("seed-rdl", sets: 3, reps: 10, restSeconds: 120),
            PresetItem("seed-crunch", sets: 3, reps: 15, restSeconds: 60)
        ])
    ])

    public static let beginnerFullBody = PresetPlan(id: "beginner-full-body", titleKey: "presets.beginner", level: "beginner", daysPerWeek: 3, days: [
        PresetDay(titleKey: "presets.day.a", items: [
            PresetItem("seed-squat", sets: 3, reps: 10, restSeconds: 120),
            PresetItem("seed-bench-press", sets: 3, reps: 10, restSeconds: 120),
            PresetItem("seed-bent-row", sets: 3, reps: 10, restSeconds: 90),
            PresetItem("seed-lateral-raise", sets: 3, reps: 12, restSeconds: 60),
            PresetItem("seed-biceps-curl", sets: 3, reps: 12, restSeconds: 60),
            PresetItem("seed-crunch", sets: 3, reps: 15, restSeconds: 60)
        ]),
        PresetDay(titleKey: "presets.day.b", items: [
            PresetItem("seed-leg-press", sets: 3, reps: 12, restSeconds: 120),
            PresetItem("seed-lat-pulldown", sets: 3, reps: 10, restSeconds: 90),
            PresetItem("fedb-Dumbbell_Shoulder_Press", sets: 3, reps: 10, restSeconds: 90),
            PresetItem("seed-rdl", sets: 3, reps: 10, restSeconds: 120),
            PresetItem("seed-triceps-pushdown", sets: 3, reps: 12, restSeconds: 60),
            PresetItem("fedb-Dead_Bug", sets: 3, reps: 12, restSeconds: 60)
        ])
    ])

    public static let twoDayFullBody = PresetPlan(id: "two-day-full-body", titleKey: "presets.twoDay", level: "beginner", daysPerWeek: 2, days: [
        PresetDay(titleKey: "presets.day.a", items: [
            PresetItem("seed-squat", sets: 3, reps: 10, restSeconds: 120),
            PresetItem("seed-bench-press", sets: 3, reps: 10, restSeconds: 120),
            PresetItem("seed-bent-row", sets: 3, reps: 10, restSeconds: 90),
            PresetItem("seed-overhead-press", sets: 3, reps: 10, restSeconds: 90),
            PresetItem("seed-leg-curl", sets: 3, reps: 12, restSeconds: 75),
            PresetItem("seed-biceps-curl", sets: 3, reps: 12, restSeconds: 60),
            PresetItem("seed-crunch", sets: 3, reps: 15, restSeconds: 60)
        ]),
        PresetDay(titleKey: "presets.day.b", items: [
            PresetItem("seed-rdl", sets: 3, reps: 10, restSeconds: 120),
            PresetItem("seed-leg-press", sets: 3, reps: 12, restSeconds: 120),
            PresetItem("seed-lat-pulldown", sets: 3, reps: 10, restSeconds: 90),
            PresetItem("fedb-Incline_Dumbbell_Press", sets: 3, reps: 10, restSeconds: 90),
            PresetItem("seed-lateral-raise", sets: 3, reps: 12, restSeconds: 60),
            PresetItem("seed-triceps-pushdown", sets: 3, reps: 12, restSeconds: 60),
            PresetItem("fedb-Dead_Bug", sets: 3, reps: 12, restSeconds: 60)
        ])
    ])

    public static let pushPullLegs = PresetPlan(id: "push-pull-legs", titleKey: "presets.ppl", level: "intermediate", daysPerWeek: 3, days: [
        PresetDay(titleKey: "presets.day.push", items: [
            PresetItem("seed-bench-press", sets: 4, reps: 8, restSeconds: 150),
            PresetItem("fedb-Incline_Dumbbell_Press", sets: 3, reps: 10, restSeconds: 120),
            PresetItem("seed-overhead-press", sets: 3, reps: 8, restSeconds: 120),
            PresetItem("seed-lateral-raise", sets: 3, reps: 12, restSeconds: 60),
            PresetItem("seed-triceps-pushdown", sets: 3, reps: 12, restSeconds: 60),
            PresetItem("seed-dips", sets: 3, reps: 10, restSeconds: 90)
        ]),
        PresetDay(titleKey: "presets.day.pull", items: [
            PresetItem("seed-pullup", sets: 4, reps: 8, restSeconds: 150),
            PresetItem("seed-bent-row", sets: 4, reps: 8, restSeconds: 120),
            PresetItem("fedb-Seated_Cable_Rows", sets: 3, reps: 10, restSeconds: 90),
            PresetItem("fedb-Face_Pull", sets: 3, reps: 15, restSeconds: 60),
            PresetItem("seed-biceps-curl", sets: 3, reps: 10, restSeconds: 60),
            PresetItem("seed-hammer-curl", sets: 3, reps: 12, restSeconds: 60)
        ]),
        PresetDay(titleKey: "presets.day.legs", items: [
            PresetItem("seed-squat", sets: 4, reps: 8, restSeconds: 180),
            PresetItem("seed-rdl", sets: 3, reps: 8, restSeconds: 150),
            PresetItem("seed-leg-press", sets: 3, reps: 12, restSeconds: 120),
            PresetItem("seed-leg-curl", sets: 3, reps: 12, restSeconds: 75),
            PresetItem("seed-hip-thrust", sets: 3, reps: 10, restSeconds: 90),
            PresetItem("seed-calf-raise", sets: 4, reps: 15, restSeconds: 60)
        ])
    ])

    public static let upperLower = PresetPlan(id: "upper-lower", titleKey: "presets.upperLower", level: "intermediate", daysPerWeek: 4, days: [
        PresetDay(titleKey: "presets.day.upperA", items: [
            PresetItem("seed-bench-press", sets: 4, reps: 6, restSeconds: 150),
            PresetItem("seed-bent-row", sets: 4, reps: 8, restSeconds: 120),
            PresetItem("seed-overhead-press", sets: 3, reps: 8, restSeconds: 120),
            PresetItem("seed-lat-pulldown", sets: 3, reps: 10, restSeconds: 90),
            PresetItem("seed-biceps-curl", sets: 3, reps: 12, restSeconds: 60),
            PresetItem("seed-triceps-pushdown", sets: 3, reps: 12, restSeconds: 60)
        ]),
        PresetDay(titleKey: "presets.day.lowerA", items: [
            PresetItem("seed-squat", sets: 4, reps: 6, restSeconds: 180),
            PresetItem("seed-rdl", sets: 3, reps: 8, restSeconds: 150),
            PresetItem("seed-leg-extension", sets: 3, reps: 12, restSeconds: 75),
            PresetItem("seed-leg-curl", sets: 3, reps: 12, restSeconds: 75),
            PresetItem("seed-calf-raise", sets: 4, reps: 15, restSeconds: 60),
            PresetItem("seed-crunch", sets: 3, reps: 15, restSeconds: 60)
        ]),
        PresetDay(titleKey: "presets.day.upperB", items: [
            PresetItem("fedb-Incline_Dumbbell_Press", sets: 4, reps: 8, restSeconds: 120),
            PresetItem("seed-pullup", sets: 4, reps: 6, restSeconds: 150),
            PresetItem("fedb-Arnold_Dumbbell_Press", sets: 3, reps: 10, restSeconds: 90),
            PresetItem("fedb-One-Arm_Dumbbell_Row", sets: 3, reps: 10, restSeconds: 90),
            PresetItem("seed-hammer-curl", sets: 3, reps: 12, restSeconds: 60),
            PresetItem("seed-dips", sets: 3, reps: 10, restSeconds: 90)
        ]),
        PresetDay(titleKey: "presets.day.lowerB", items: [
            PresetItem("fedb-Barbell_Deadlift", sets: 3, reps: 5, restSeconds: 180),
            PresetItem("seed-leg-press", sets: 4, reps: 10, restSeconds: 120),
            PresetItem("fedb-Dumbbell_Lunges", sets: 3, reps: 10, restSeconds: 90),
            PresetItem("seed-hip-thrust", sets: 3, reps: 10, restSeconds: 90),
            PresetItem("fedb-Seated_Calf_Raise", sets: 4, reps: 15, restSeconds: 60),
            PresetItem("fedb-Hanging_Leg_Raise", sets: 3, reps: 12, restSeconds: 60)
        ])
    ])

    public static let bodyweightStretching = PresetPlan(id: "bodyweight-stretching", titleKey: "presets.bodyweight", level: "beginner", daysPerWeek: 3, days: [
        PresetDay(titleKey: "presets.day.bodyweight", items: [
            PresetItem("seed-pushup", sets: 3, reps: 12, restSeconds: 60),
            PresetItem("fedb-Bodyweight_Squat", sets: 3, reps: 15, restSeconds: 60),
            PresetItem("fedb-Inverted_Row", sets: 3, reps: 10, restSeconds: 90),
            PresetItem("fedb-Bodyweight_Walking_Lunge", sets: 3, reps: 12, restSeconds: 60),
            PresetItem("fedb-Bench_Dips", sets: 3, reps: 12, restSeconds: 60),
            PresetItem("fedb-Mountain_Climbers", sets: 3, reps: 20, restSeconds: 45),
            PresetItem("seed-crunch", sets: 3, reps: 15, restSeconds: 45)
        ]),
        PresetDay(titleKey: "presets.day.stretching", items: [
            PresetItem("fedb-Cat_Stretch", sets: 2, reps: 8, restSeconds: 15),
            PresetItem("fedb-Childs_Pose", sets: 2, reps: 1, restSeconds: 15),
            PresetItem("fedb-Seated_Floor_Hamstring_Stretch", sets: 2, reps: 1, restSeconds: 15),
            PresetItem("fedb-Kneeling_Hip_Flexor", sets: 2, reps: 1, restSeconds: 15),
            PresetItem("fedb-On_Your_Side_Quad_Stretch", sets: 2, reps: 1, restSeconds: 15),
            PresetItem("fedb-Behind_Head_Chest_Stretch", sets: 2, reps: 1, restSeconds: 15),
            PresetItem("fedb-Shoulder_Stretch", sets: 2, reps: 1, restSeconds: 15),
            PresetItem("fedb-Calf_Stretch_Hands_Against_Wall", sets: 2, reps: 1, restSeconds: 15),
            PresetItem("fedb-Spinal_Stretch", sets: 2, reps: 1, restSeconds: 15)
        ])
    ])

    /// Tutte le schede pronte, la base (Free) per prima.
    public static let all: [PresetPlan] = [freeTotalBody, beginnerFullBody, twoDayFullBody, pushPullLegs, upperLower, bodyweightStretching]
    // GENERATO-FINE

    public static func plan(_ id: String) -> PresetPlan? { all.first { $0.id == id } }

    /// Free: solo la scheda base total body. Pro: tutte.
    public static func isAvailable(_ plan: PresetPlan, for tier: SubscriptionTier) -> Bool {
        plan.id == freeID || FeatureGate.isAvailable(.presetPlans, for: tier)
    }

    /// Elementi dell'elenco per un giorno della scheda; il peso viene dall'ultima volta che si e' fatto l'esercizio.
    public static func items(for day: PresetDay, sessions: [SessionSummary]) -> [WorkoutItem] {
        day.items.map { p in
            var item = p
            if p.weightKg <= 0, let last = sessions.filter({ $0.exerciseID == p.exerciseID && $0.weightKg > 0 })
                .max(by: { $0.startedAt < $1.startedAt }) {
                item.weightKg = last.weightKg
            }
            return item.workoutItem()
        }
    }
}

/// Perche' la scheda del mese e' fatta cosi' (mostrato sopra la scheda).
public struct MonthlySummary: Equatable, Sendable, Codable {
    public var monthKey: String
    public var trainingDays: Int
    public var sessions: Int
    public var undertrained: [MuscleGroup]
    public var keptExercises: Int
    public var newExercises: Int
}

public struct MonthlyPlan: Equatable, Sendable, Codable {
    public var plan: PresetPlan
    public var summary: MonthlySummary
    /// Nota scritta dal modello sul telefono (Apple Intelligence); nil = scheda a regole fisse.
    public var aiNote: String?
    public init(plan: PresetPlan, summary: MonthlySummary, aiNote: String? = nil) {
        self.plan = plan; self.summary = summary; self.aiNote = aiNote
    }
}

/// Scheda consigliata del mese (Pro), a regole fisse dallo storico del mese precedente (stesse regole di
/// MonthlyPlanner in Presets.kt). Su iPhone con Apple Intelligence il modello sul telefono puo' poi rivederla
/// scegliendo solo tra gli esercizi candidati (MonthlyPlanAI.swift nell'app).
public enum MonthlyPlanner {
    public static let id = "monthly"
    static let weeksPerMonth = 4.33

    static let fullA: [MuscleGroup] = [.quads, .chest, .lats, .shoulders, .biceps, .abs]
    static let fullB: [MuscleGroup] = [.hamstrings, .chest, .traps, .shoulders, .triceps, .abs]
    static let fullC: [MuscleGroup] = [.glutes, .lats, .chest, .shoulders, .calves, .abs]
    static let upper: [MuscleGroup] = [.chest, .lats, .shoulders, .traps, .biceps, .triceps]
    static let lower: [MuscleGroup] = [.quads, .hamstrings, .glutes, .calves, .abs]
    static let lightEquipment: Set<String> = ["bodyweight", "band", "exerciseBall", "other"]
    static let excludedCategories: Set<String> = ["olympic", "strongman"]

    /// Mese ("yyyy-MM") e inizio del mese in corso e di quello precedente, nel fuso del telefono.
    static func monthBounds(_ now: Date, calendar: Calendar = .current) -> (key: String, start: Date, previous: Date) {
        let comps = calendar.dateComponents([.year, .month], from: now)
        let start = calendar.date(from: comps) ?? now
        let previous = calendar.date(byAdding: .month, value: -1, to: start) ?? start
        return (String(format: "%04d-%02d", comps.year ?? 0, comps.month ?? 0), start, previous)
    }

    /// Hash stabile (FNV-1a a 32 bit sui byte UTF-8): stesso valore su Android e iOS.
    public static func stableHash(_ text: String) -> UInt32 {
        var h: UInt32 = 0x811C9DC5
        for b in text.utf8 { h ^= UInt32(b); h = h &* 0x01000193 }
        return h
    }

    /// Candidati per un muscolo (esclusi quelli gia' usati), nello stesso ordine di Android.
    static func candidates(for muscle: MuscleGroup, occurrence k: Int, catalog: [CatalogExercise], used: Set<String>,
                           lightOnly: Bool, timesDone: [String: Int], monthKey: String) -> (done: [CatalogExercise], others: [CatalogExercise]) {
        let pool = catalog.filter { ex in
            ex.isTraining && ex.primary.first == muscle && !excludedCategories.contains(ex.category)
                && ex.level != "expert" && !used.contains(ex.id) && (!lightOnly || lightEquipment.contains(ex.equipment))
        }
        let done = pool.filter { (timesDone[$0.id] ?? 0) > 0 }.sorted { a, b in
            let ta = timesDone[a.id] ?? 0, tb = timesDone[b.id] ?? 0
            return ta != tb ? ta > tb : a.id < b.id
        }
        let others = pool.filter { (timesDone[$0.id] ?? 0) == 0 }.sorted { a, b in
            let sa = a.id.hasPrefix("seed-"), sb = b.id.hasPrefix("seed-")
            if sa != sb { return sa }
            if k == 0, a.isCompound != b.isCompound { return a.isCompound }
            return stableHash(a.id + monthKey) < stableHash(b.id + monthKey)
        }
        return (done, others)
    }

    public static func generate(catalog: [CatalogExercise], sessions: [SessionSummary], now: Date = Date(),
                                calendar: Calendar = .current) -> MonthlyPlan {
        let bounds = monthBounds(now, calendar: calendar)
        let byID = Dictionary(catalog.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let lastMonth = sessions.filter { $0.startedAt >= bounds.previous && $0.startedAt < bounds.start && !$0.exerciseID.isEmpty }

        let dayKeys = Set(lastMonth.map { s -> Int in
            let y = calendar.component(.year, from: s.startedAt)
            return y * 1000 + (calendar.ordinality(of: .day, in: .year, for: s.startedAt) ?? 0)
        })
        let trainingDays = dayKeys.count
        var setsByMuscle: [MuscleGroup: Int] = [:]
        for s in lastMonth {
            guard let ex = byID[s.exerciseID] else { continue }
            for m in ex.primary { setsByMuscle[m, default: 0] += s.sets }
        }
        var timesDone: [String: Int] = [:]
        for s in lastMonth { timesDone[s.exerciseID, default: 0] += 1 }

        let perWeek = Double(trainingDays) / weeksPerMonth
        let template: [(String, [MuscleGroup])]
        let daysPerWeek: Int
        if trainingDays == 0 {
            template = [("presets.day.a", fullA), ("presets.day.b", fullB), ("presets.day.c", fullC)]; daysPerWeek = 3
        } else if perWeek < 2.5 {
            // Le schede sono sempre da 3 o 4 allenamenti a settimana: qui si alternano A e B tre volte a settimana
            template = [("presets.day.a", fullA), ("presets.day.b", fullB)]; daysPerWeek = 3
        } else if perWeek < 3.5 {
            template = [("presets.day.a", fullA), ("presets.day.b", fullB), ("presets.day.c", fullC)]; daysPerWeek = 3
        } else {
            template = [("presets.day.upperA", upper), ("presets.day.lowerA", lower),
                        ("presets.day.upperB", upper), ("presets.day.lowerB", lower)]; daysPerWeek = 4
        }

        // Muscoli trascurati (in ordine di comparsa nella scheda, come su Android)
        var planned: [MuscleGroup] = []
        for (_, muscles) in template { for m in muscles where !planned.contains(m) { planned.append(m) } }
        let undertrained: [MuscleGroup] = trainingDays == 0 ? [] : Array(
            planned.filter { setsByMuscle[$0, default: 0] < 4 }
                .enumerated().sorted { a, b in
                    let sa = setsByMuscle[a.element, default: 0], sb = setsByMuscle[b.element, default: 0]
                    return sa != sb ? sa < sb : a.offset < b.offset
                }.map(\.element).prefix(2))
        let slots: [(String, [MuscleGroup])] = template.enumerated().map { i, t in
            (t.0, i < undertrained.count ? t.1 + [undertrained[i]] : t.1)
        }

        let usedEquipment = Set(lastMonth.compactMap { byID[$0.exerciseID]?.equipment })
        let lightOnly = lastMonth.count >= 3 && !usedEquipment.isEmpty && usedEquipment.allSatisfy { lightEquipment.contains($0) }
        let advanced = trainingDays >= 10

        var used = Set<String>()
        var occurrences: [MuscleGroup: Int] = [:]
        var kept = 0, fresh = 0
        let days: [PresetDay] = slots.map { key, muscles in
            var items: [PresetItem] = []
            for m in muscles {
                let k = occurrences[m, default: 0]
                occurrences[m] = k + 1
                let c = candidates(for: m, occurrence: k, catalog: catalog, used: used, lightOnly: lightOnly,
                                   timesDone: timesDone, monthKey: bounds.key)
                guard let pick = k % 2 == 0 ? (c.done.first ?? c.others.first) : (c.others.first ?? c.done.first) else { continue }
                used.insert(pick.id)
                if timesDone[pick.id, default: 0] > 0 { kept += 1 } else { fresh += 1 }
                items.append(parameters(for: pick, muscle: m, advanced: advanced))
            }
            return PresetDay(titleKey: key, items: items)
        }
        let plan = PresetPlan(id: id, titleKey: "presets.monthly", level: advanced ? "intermediate" : "beginner",
                              daysPerWeek: daysPerWeek, days: days)
        return MonthlyPlan(plan: plan, summary: MonthlySummary(monthKey: bounds.key, trainingDays: trainingDays,
                                                                sessions: lastMonth.count, undertrained: undertrained,
                                                                keptExercises: kept, newExercises: fresh))
    }

    /// Serie, ripetizioni e pausa secondo il tipo di esercizio e l'esperienza (piu' di 10 allenamenti nel mese).
    public static func parameters(for ex: CatalogExercise, muscle: MuscleGroup, advanced: Bool) -> PresetItem {
        if muscle == .abs || muscle == .obliques { return PresetItem(ex.id, sets: 3, reps: 15, restSeconds: 45) }
        if muscle == .calves { return PresetItem(ex.id, sets: 4, reps: 15, restSeconds: 60) }
        if ex.kind == .plyometrics { return PresetItem(ex.id, sets: 3, reps: 10, restSeconds: 90) }
        if ex.isCompound { return advanced ? PresetItem(ex.id, sets: 4, reps: 8, restSeconds: 120) : PresetItem(ex.id, sets: 3, reps: 10, restSeconds: 90) }
        return PresetItem(ex.id, sets: 3, reps: 12, restSeconds: 60)
    }

    /// Candidati per ogni posto della scheda (per la revisione con l'AI sul telefono): per ogni giorno e muscolo,
    /// l'esercizio scelto dalle regole piu' fino a `limit` alternative, mai usate altrove nella scheda.
    public static func alternatives(for plan: MonthlyPlan, catalog: [CatalogExercise], limit: Int = 4) -> [[[CatalogExercise]]] {
        let byID = Dictionary(catalog.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let usedAll = Set(plan.plan.days.flatMap { $0.items.map(\.exerciseID) })
        return plan.plan.days.map { day in
            day.items.map { item in
                guard let ex = byID[item.exerciseID], let m = ex.primary.first else { return [] }
                let others = catalog.filter { c in
                    c.isTraining && c.primary.first == m && !excludedCategories.contains(c.category) && c.level != "expert"
                        && !usedAll.contains(c.id) && c.equipment == ex.equipment || c.id == ex.id
                }
                .sorted { a, b in
                    if a.id == ex.id || b.id == ex.id { return a.id == ex.id && b.id != ex.id }   // prima quello scelto
                    return stableHash(a.id + plan.summary.monthKey) < stableHash(b.id + plan.summary.monthKey)
                }
                return Array(others.prefix(limit + 1))
            }
        }
    }
}
