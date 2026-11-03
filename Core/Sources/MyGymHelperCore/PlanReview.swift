import Foundation

// MARK: - Revisione della scheda ogni due settimane (piano Full)
//
// Ogni 14 giorni, a fine allenamento, l'app chiede se la scheda e' troppo leggera, giusta o troppo pesante.
// Con la risposta e lo storico delle ultime due settimane (ripetizioni fatte, serie interrotte, calo di velocita')
// si prepara una proposta per ogni esercizio della scheda: prima con regole fisse (sempre), poi rivista dal
// modello AI del telefono se c'e' (Apple Intelligence / Gemini Nano), che puo' solo spostare il carico di un passo
// nella direzione chiesta dall'utente. La proposta compare nella card "Consiglio per oggi"; con "Applica"
// si aggiornano la scheda e gli elenchi con quegli esercizi, tenendo una copia per tornare alla versione precedente.
// Uguale su Android: PlanReview.kt.

/// Risposta dell'utente alla domanda sulla scheda.
public enum PlanFeedback: String, Codable, Sendable, CaseIterable {
    case tooLight = "light", right = "right", tooHeavy = "heavy"
}

/// Come sono state eseguite le ripetizioni di un esercizio nelle ultime due settimane.
public struct RepQuality: Equatable, Sendable {
    public let sessions: Int
    public let completion: Double
    public let stoppedRate: Double
    public let fatigue: Double
    /// Ripetizioni eseguite correttamente: quasi tutte fatte e poche serie interrotte.
    public var correct: Bool { sessions > 0 && completion >= 0.9 && stoppedRate <= 0.2 }
    /// Tutto fatto, nessuna serie interrotta e velocita' stabile: si puo' spingere di piu'.
    public var easy: Bool { sessions > 0 && completion >= 0.999 && stoppedRate == 0 && fatigue < 0.2 }
}

/// Proposta per una voce della scheda: serie e pausa prima e dopo, con i motivi (chiavi dei testi).
public struct ReviewChange: Codable, Equatable, Sendable {
    public var entryID: UUID
    public var exerciseID: String
    public var name: String
    public var before: [SetTarget]
    public var beforeRest: Int
    public var after: [SetTarget]
    public var afterRest: Int
    public var reasonKeys: [String]
    public var sessions: Int
    /// Ripetizioni fatte sul totale previsto, in percentuale (0-100).
    public var completionPercent: Int

    public init(entryID: UUID, exerciseID: String, name: String, before: [SetTarget], beforeRest: Int,
                after: [SetTarget], afterRest: Int, reasonKeys: [String], sessions: Int = 0, completionPercent: Int = 0) {
        self.entryID = entryID; self.exerciseID = exerciseID; self.name = name; self.before = before
        self.beforeRest = beforeRest; self.after = after; self.afterRest = afterRest; self.reasonKeys = reasonKeys
        self.sessions = sessions; self.completionPercent = completionPercent
    }

    public var beforeParameters: WorkoutParameters { .of(before, restSeconds: beforeRest) }
    public var afterParameters: WorkoutParameters { .of(after, restSeconds: afterRest) }
    public var changed: Bool { before != after || beforeRest != afterRest }
}

/// Proposta per tutta una scheda, in attesa di "Applica".
public struct PlanReview: Codable, Equatable, Sendable {
    public var planID: UUID
    public var planName: String
    public var createdAt: Date
    public var feedback: PlanFeedback
    public var changes: [ReviewChange]
    /// Nota breve del modello AI (nella lingua del telefono); nil senza AI.
    public var note: String?
    /// Vero se il modello AI ha rivisto la proposta.
    public var byAI: Bool

    public init(planID: UUID, planName: String, createdAt: Date, feedback: PlanFeedback, changes: [ReviewChange],
                note: String? = nil, byAI: Bool = false) {
        self.planID = planID; self.planName = planName; self.createdAt = createdAt; self.feedback = feedback
        self.changes = changes; self.note = note; self.byAI = byAI
    }

    public func change(for exerciseID: String) -> ReviewChange? { changes.first { $0.exerciseID == exerciseID } }
    public var changedCount: Int { changes.filter(\.changed).count }
}

/// Scheda ed elenchi com'erano prima dell'ultimo "Applica" (per tornare alla versione precedente).
public struct PlanBackup: Codable, Equatable, Sendable {
    public var planID: UUID
    public var appliedAt: Date
    public var plan: TrainingPlan
    /// Esercizi degli elenchi toccati, per id dell'elenco.
    public var listItems: [UUID: [WorkoutItem]]
    /// Esercizi modificati (per preferire la scheda all'ultima sessione nel precompilare).
    public var exerciseIDs: [String]

    public init(planID: UUID, appliedAt: Date, plan: TrainingPlan, listItems: [UUID: [WorkoutItem]], exerciseIDs: [String]) {
        self.planID = planID; self.appliedAt = appliedAt; self.plan = plan; self.listItems = listItems
        self.exerciseIDs = exerciseIDs
    }
}

/// Stato salvato: ultimo controllo, proposta in attesa, copia per tornare indietro (una versione).
public struct PlanReviewState: Codable, Equatable, Sendable {
    public var lastCheckAt: Date?
    public var pending: PlanReview?
    public var backup: PlanBackup?
    public init(lastCheckAt: Date? = nil, pending: PlanReview? = nil, backup: PlanBackup? = nil) {
        self.lastCheckAt = lastCheckAt; self.pending = pending; self.backup = backup
    }
}

public enum PlanReviewer {
    /// Ogni quanto si fa la domanda: due settimane.
    public static let interval: TimeInterval = 14 * 86_400
    /// Sessioni minime degli esercizi della scheda nelle ultime due settimane per poter controllare le ripetizioni.
    public static let minSessions = 2

    /// Vero se e' ora di chiedere: sono passate due settimane dall'ultimo controllo (o, la prima volta, da quando la
    /// scheda e' stata caricata) e nelle ultime due settimane ci sono almeno `minSessions` sessioni di suoi esercizi.
    public static func isDue(_ state: PlanReviewState, planCreatedAt: Date, planSessionDates: [Date], now: Date) -> Bool {
        let base = max(state.lastCheckAt ?? .distantPast, planCreatedAt)
        guard now.timeIntervalSince(base) >= interval else { return false }
        let from = now.addingTimeInterval(-interval)
        return planSessionDates.filter { $0 >= from && $0 <= now }.count >= minSessions
    }

    /// Ripetizioni delle sessioni delle ultime due settimane.
    public static func quality(_ samples: [SessionSample], now: Date) -> RepQuality {
        let from = now.addingTimeInterval(-interval)
        let recent = samples.filter { $0.date >= from && $0.date <= now && !$0.sets.isEmpty }
        guard !recent.isEmpty else { return RepQuality(sessions: 0, completion: 0, stoppedRate: 0, fatigue: 0) }
        let n = Double(recent.count)
        let completion = recent.map(AdaptiveCoach.completionRate).reduce(0, +) / n
        let sets = recent.reduce(0) { $0 + $1.sets.count }
        let stopped = recent.reduce(0) { $0 + $1.sets.filter(\.stoppedEarly).count }
        let fatigue = recent.map(AdaptiveCoach.velocityDrop).reduce(0, +) / n
        return RepQuality(sessions: recent.count, completion: completion,
                          stoppedRate: sets > 0 ? Double(stopped) / Double(sets) : 0, fatigue: fatigue)
    }

    /// Serie di partenza della voce; il peso mancante nella scheda si prende dall'ultima sessione (`lastWeight`).
    public static func baseTargets(_ entry: PlanEntry, lastWeight: Double) -> [SetTarget] {
        let d = WorkoutItem.defaultParameters
        if !entry.perSet.isEmpty {
            return entry.perSet.map { SetTarget(reps: $0.reps ?? entry.repsMin ?? d.reps, weightKg: $0.weightKg ?? lastWeight) }
        }
        return Array(repeating: SetTarget(reps: entry.repsMin ?? d.reps, weightKg: entry.weightKg ?? lastWeight),
                     count: max(entry.sets ?? d.sets, 1))
    }

    /// Proposta per una voce; nil se l'esercizio non e' stato fatto nelle ultime due settimane (niente da controllare).
    public static func propose(_ entry: PlanEntry, exerciseID: String, samples: [SessionSample], feedback: PlanFeedback,
                               now: Date, step: Double = WorkoutParameters.weightStep) -> ReviewChange? {
        let q = quality(samples, now: now)
        guard q.sessions > 0 else { return nil }
        let lastWeight = samples.last?.weightKg ?? 0
        let before = WorkoutParameters.of(baseTargets(entry, lastWeight: lastWeight),
                                          restSeconds: entry.restSeconds ?? WorkoutItem.defaultParameters.restSeconds).clamped()
        var t = before.targets
        var rest = before.restSeconds
        let bodyweight = t.allSatisfy { $0.weightKg <= 0 }
        var reasons: [String] = []

        func up(_ times: Double) -> [SetTarget] {
            t.map { $0.weightKg > 0 ? SetTarget(reps: $0.reps, weightKg: $0.weightKg + AdaptiveCoach.increment($0.weightKg, step: step) * times) : $0 }
        }
        func down(_ factor: Double) -> [SetTarget] {
            t.map { $0.weightKg > 0 ? SetTarget(reps: $0.reps, weightKg: AdaptiveCoach.lowered($0.weightKg, factor: factor, step: step)) : $0 }
        }
        func reps(_ delta: Int) -> [SetTarget] { t.map { SetTarget(reps: max(1, $0.reps + delta), weightKg: $0.weightKg) } }

        switch feedback {
        case .tooLight:
            if q.correct {
                if bodyweight { t = reps(2); reasons.append("review.lightReps") }
                else { t = up(q.easy ? 2 : 1); reasons.append("review.lightUp") }
                if q.easy && rest > 60 { rest -= 15; reasons.append("review.lessRest") }
            } else {
                // Leggero ma con ripetizioni mancate: prima si completano con questo carico.
                reasons.append("review.lightButMissed")
            }
        case .tooHeavy:
            if bodyweight { t = reps(-2); reasons.append("review.heavyReps") }
            else { t = down(0.9); reasons.append("review.heavyDown") }
            if q.completion < 0.7 && t.count > 2 { t.removeLast(); reasons.append("review.heavyLessSets") }
            rest = min(rest + 15, 300)
        case .right:
            if q.completion < 0.7 { t = bodyweight ? reps(-1) : down(0.92); reasons.append("review.missedDown") }
            else if q.easy { t = bodyweight ? reps(1) : up(1); reasons.append("review.progress") }
            else { reasons.append("review.keep") }
        }
        let after = WorkoutParameters.of(t, restSeconds: rest).clamped()
        return ReviewChange(entryID: entry.id, exerciseID: exerciseID, name: entry.name, before: before.targets,
                            beforeRest: before.restSeconds, after: after.targets, afterRest: after.restSeconds,
                            reasonKeys: reasons, sessions: q.sessions, completionPercent: Int((q.completion * 100).rounded()))
    }

    /// Proposta per tutta la scheda. `resolve` = esercizio del catalogo della voce (PlanAI.exercise(for:in:)),
    /// `samplesFor` = sessioni dell'esercizio (CoachingService.samples). Una proposta per esercizio.
    public static func build(planID: UUID, planName: String, plan: TrainingPlan, feedback: PlanFeedback, now: Date,
                             resolve: (PlanEntry) -> CatalogExercise?, samplesFor: (String) -> [SessionSample]) -> PlanReview {
        var seen = Set<String>()
        let changes = plan.allEntries.compactMap { entry -> ReviewChange? in
            guard let ex = resolve(entry), seen.insert(ex.id).inserted else { return nil }
            return propose(entry, exerciseID: ex.id, samples: samplesFor(ex.id), feedback: feedback, now: now)
        }
        return PlanReview(planID: planID, planName: planName, createdAt: now, feedback: feedback, changes: changes)
    }

    /// Scheda con le proposte applicate (voci per id; le altre restano com'erano).
    public static func apply(_ review: PlanReview, to plan: TrainingPlan) -> TrainingPlan {
        var byEntry: [UUID: ReviewChange] = [:]
        for c in review.changes where c.changed { byEntry[c.entryID] = c }
        var result = plan
        for d in result.days.indices {
            result.days[d].entries = result.days[d].entries.map { e in byEntry[e.id].map { updatedEntry(e, $0) } ?? e }
        }
        return result
    }

    static func updatedEntry(_ e: PlanEntry, _ c: ReviewChange) -> PlanEntry {
        let after = c.after
        let varied = after.contains { $0.reps != after[0].reps || abs($0.weightKg - after[0].weightKg) > 1e-9 }
        if !e.perSet.isEmpty || varied {
            var out = e.withSets(after.map { PlanSet(reps: $0.reps, weightKg: $0.weightKg > 0 ? $0.weightKg : nil) })
            out.restSeconds = c.afterRest
            return out
        }
        let a = after[0]
        let delta = a.reps - c.before[0].reps
        var out = e
        out.sets = after.count
        out.repsMin = a.reps
        out.repsMax = e.repsMax.map { max($0 + delta, a.reps) } ?? a.reps
        out.weightKg = a.weightKg > 0 ? a.weightKg : e.weightKg
        out.restSeconds = c.afterRest
        return out
    }

    /// Esercizi di un elenco con le proposte applicate (si tiene se erano gia' fatti).
    public static func apply(_ review: PlanReview, to items: [WorkoutItem]) -> [WorkoutItem] {
        items.map { item in
            guard let c = review.change(for: item.exerciseID), c.changed else { return item }
            return item.with(c.afterParameters)
        }
    }

    /// Elenchi che contengono almeno un esercizio modificato.
    public static func touchedLists(_ lists: [UUID: [WorkoutItem]], review: PlanReview) -> Set<UUID> {
        let ids = Set(review.changes.filter(\.changed).map(\.exerciseID))
        return Set(lists.filter { $0.value.contains { ids.contains($0.exerciseID) } }.keys)
    }

    /// Vero se per precompilare l'esercizio va usata la scheda e non l'ultima sessione: la scheda e' stata aggiornata
    /// con "Applica" dopo l'ultima volta che l'esercizio e' stato fatto.
    public static func prefersPlan(_ state: PlanReviewState, exerciseID: String, lastSessionAt: Date?) -> Bool {
        guard let b = state.backup, b.exerciseIDs.contains(exerciseID) else { return false }
        guard let lastSessionAt else { return true }
        return b.appliedAt > lastSessionAt
    }

    // MARK: Revisione con il modello AI del telefono

    /// Richiesta al modello: per ogni esercizio una correzione -1, 0 o +1 e una nota (Android: righe "ES | n | x").
    public static func aiPrompt(_ review: PlanReview, italian: Bool) -> String {
        var text = "Sei un allenatore. Una persona ha detto che la sua scheda di palestra è "
        switch review.feedback {
        case .tooLight: text += "troppo leggera"
        case .right: text += "giusta"
        case .tooHeavy: text += "troppo pesante"
        }
        text += ". Per ogni esercizio vedi come ha eseguito le ripetizioni nelle ultime due settimane e la modifica proposta. "
        text += "Puoi correggere la proposta di un passo: +1 = un passo di carico in più (o una ripetizione se è a corpo libero), "
        text += "-1 = un passo in meno, 0 = va bene così. "
        switch review.feedback {
        case .tooLight: text += "Non scendere mai sotto il carico di prima. "
        case .tooHeavy: text += "Non salire mai sopra il carico di prima. "
        case .right: break
        }
        text += "Non dare consigli medici.\n"
        text += "Rispondi solo con una riga per esercizio: ES | numero | correzione\n"
        text += "e alla fine una riga: NOTA | al massimo due frasi brevi in \(italian ? "italiano" : "English") sul perché.\n"
        for (i, c) in review.changes.enumerated() {
            text += "\(i + 1). \(c.name): \(c.sessions) sessioni, ripetizioni fatte \(c.completionPercent)%; "
            text += "prima \(describe(c.before)), proposta \(describe(c.after))\n"
        }
        return text
    }

    private static func describe(_ t: [SetTarget]) -> String {
        t.map { $0.weightKg > 0 ? "\($0.reps)x\(formatKg($0.weightKg))kg" : "\($0.reps) rip." }.joined(separator: ", ")
    }

    private static func formatKg(_ w: Double) -> String {
        abs(w - w.rounded()) < 1e-9 ? String(Int(w.rounded())) : String(w)
    }

    /// Legge la risposta a righe del modello: correzioni per numero di esercizio (1 = primo) e nota.
    public static func decodeAI(_ output: String) -> (adjustments: [Int: Int], note: String?) {
        var adjustments: [Int: Int] = [:]
        var note: String?
        for raw in output.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: CharacterSet(charactersIn: "`*- ").union(.whitespaces))
            let cells = line.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            guard cells.count >= 2 else { continue }
            switch cells[0].uppercased() {
            case "ES":
                guard cells.count >= 3,
                      let n = Int(cells[1].trimmingCharacters(in: CharacterSet(charactersIn: "."))),
                      let v = Int(cells[2].replacingOccurrences(of: "+", with: "")) else { continue }
                adjustments[n] = v
            case "NOTA", "NOTE":
                let text = cells.dropFirst().joined(separator: " | ").trimmingCharacters(in: .whitespaces)
                note = text.isEmpty ? nil : text
            default: continue
            }
        }
        return (adjustments, note)
    }

    /// Applica le correzioni del modello dove sono valide: un passo al massimo, mai contro la richiesta dell'utente
    /// (con "troppo leggero" mai sotto il carico di prima, con "troppo pesante" mai sopra), nessuna modifica
    /// se le ripetizioni non erano corrette con "troppo leggero". Corpo libero: il passo e' una ripetizione.
    public static func applyAI(_ review: PlanReview, adjustments: [Int: Int], note: String?,
                               step: Double = WorkoutParameters.weightStep) -> PlanReview {
        var touched = false
        let changes = review.changes.enumerated().map { (i, c) -> ReviewChange in
            let adj = min(max(adjustments[i + 1] ?? 0, -1), 1)
            guard adj != 0, !c.reasonKeys.contains("review.lightButMissed") else { return c }
            let bodyweight = c.after.allSatisfy { $0.weightKg <= 0 }
            let moved = c.after.enumerated().map { (j, t) -> SetTarget in
                let ref = j < c.before.count ? c.before[j] : c.before[c.before.count - 1]
                if bodyweight {
                    var r = max(1, t.reps + adj)
                    if review.feedback == .tooLight { r = max(r, ref.reps) }
                    if review.feedback == .tooHeavy { r = min(r, ref.reps) }
                    return SetTarget(reps: r, weightKg: t.weightKg)
                } else if t.weightKg > 0 {
                    var w = max(0, t.weightKg + Double(adj) * step)
                    if review.feedback == .tooLight { w = max(w, ref.weightKg) }
                    if review.feedback == .tooHeavy { w = min(w, ref.weightKg) }
                    return SetTarget(reps: t.reps, weightKg: w)
                }
                return t
            }
            let after = WorkoutParameters.of(moved, restSeconds: c.afterRest).clamped().targets
            guard after != c.after else { return c }
            touched = true
            var out = c
            out.after = after
            out.reasonKeys.append("review.aiAdjusted")
            return out
        }
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cleanNote = trimmed.isEmpty ? nil : String(trimmed.prefix(400))
        guard touched || cleanNote != nil else { return review }
        var out = review
        out.changes = changes
        out.note = cleanNote
        out.byAI = true
        return out
    }
}
