import Foundation

// MARK: - Lettura delle schede con l'AI del telefono (uguale su Android: PlanAI.kt)
//
// Il testo estratto dal PDF/foto si legge in due modi: con le regole fisse (TrainingPlanParser) e, se l'iPhone ha
// Apple Intelligence, con il modello sul telefono. Qui c'e' tutto quello che non dipende dal modello: testo da dare al
// modello, controllo della risposta, scelta del risultato e collegamento degli esercizi al catalogo.
// Il testo non esce mai dal telefono.

public enum PlanAI {
    /// Caratteri di testo per ogni richiesta (il modello ha circa 4000 token tra domanda e risposta).
    public static let maxChunk = 1500
    /// Oltre questi pezzi la lettura con l'AI sarebbe troppo lenta: si usano solo le regole.
    public static let maxChunks = 6
    /// Esercizi del catalogo proposti al modello per ogni esercizio della scheda.
    public static let candidateCount = 6
    /// Esercizi per ogni richiesta di collegamento al catalogo.
    public static let matchBatch = 8

    /// Istruzioni comuni (stesso testo di Android).
    public static let instructions = """
    Leggi una scheda di palestra scritta da un personal trainer ed elenca gli esercizi.
    Regole:
    - Ogni esercizio è una voce; il nome è solo il nome dell'esercizio (senza numeri di serie, ripetizioni, peso o recupero), con le varianti utili (es. "gamba destra", "con manubri").
    - "SET 1 DA RIPETERE 4 VOLTE (1.30 MIN DI RECUPERO)" vale per gli esercizi che seguono fino al set successivo: 4 serie, recupero 90 secondi.
    - "6 Squat" sotto un set: 6 ripetizioni. "10 - 6 - 10 - 6 - 10 Hip thrust": 5 serie da 6 a 10 ripetizioni.
    - "40” Plank" o "60'' Polpacci": esercizio a tempo di 40 o 60 secondi, senza ripetizioni.
    - "4x8 Panca piana 60 kg rec 90''": 4 serie, 8 ripetizioni, 60 kg, recupero 90 secondi.
    - "3 serie da 12", "3 x 12" o "3x12": 3 serie da 12 ripetizioni.
    - Il peso può essere scritto "20 kg", "20kg", "kg 20" o "manubri da 8 kg" (8 kg). Non scrivere un peso che il testo non indica.
    - Esercizi uniti da "+" sono voci separate.
    - "Riscaldamento", "Defaticamento", "Settimana 1", "Giorno A", "Lunedì" sono titoli di giorno.
    - Ignora note generiche, nomi della palestra e del trainer. Non inventare: se un valore manca, lascialo vuoto.
    """

    // MARK: Testo per il modello

    /// Divide il testo in pezzi abbastanza piccoli per il modello. Un pezzo nuovo riparte con l'ultimo titolo di giorno
    /// e l'ultima intestazione di set, cosi' gli esercizi non perdono serie e recupero.
    public static func chunks(_ text: String, max: Int = maxChunk) -> [String] {
        var out: [String] = []
        var cur = ""
        var title: String?
        var block: String?
        for raw in text.components(separatedBy: .newlines) {
            let collapsed = raw.trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            let line = String(collapsed.prefix(max / 2))
            if line.isEmpty { continue }
            if !cur.isEmpty && cur.count + line.count + 1 > max {
                out.append(cur.trimmingCharacters(in: .whitespacesAndNewlines))
                cur = ""
                if let title { cur += title + "\n" }
                if let block, block != line { cur += block + "\n" }
            }
            cur += line + "\n"
            let flat = TrainingPlanParser.stripBullet(line)
            if TrainingPlanParser.blockHeader(flat) != nil { block = line }
            else if TrainingPlanParser.dayTitle(flat) != nil { title = line; block = nil }
        }
        let last = cur.trimmingCharacters(in: .whitespacesAndNewlines)
        if !last.isEmpty { out.append(last) }
        return out
    }

    // MARK: Controllo della risposta

    /// Una voce controllata: valori fuori misura scartati; gli esercizi a tempo hanno la durata nel nome (come le regole).
    public static func entry(name: String?, sets: Int?, repsMin: Int?, repsMax: Int?, restSeconds: Int?,
                             weightKg: Double?, seconds: Int?) -> PlanEntry? {
        guard let name else { return nil }
        let n = name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " :-–—,.;/|"))
        guard n.filter(\.isLetter).count >= 3 else { return nil }
        func ok(_ v: Int?, _ r: ClosedRange<Int>) -> Int? { v.flatMap { r.contains($0) ? $0 : nil } }
        let secs = ok(seconds, 5...900)
        var lo = ok(repsMin, 1...100)
        var hi = ok(repsMax, 1...100)
        if lo == nil { lo = hi }
        if hi == nil { hi = lo }
        if let l = lo, let h = hi, l > h { lo = h; hi = l }
        let timed = secs != nil
        let w = weightKg.flatMap { $0 > 0 && $0 <= 500 ? $0 : nil }
        return PlanEntry(name: timed && !n.contains("\"") ? "\(n) (\(secs!)\")" : n, sets: ok(sets, 1...12),
                         repsMin: timed ? nil : lo, repsMax: timed ? nil : hi,
                         restSeconds: ok(restSeconds, 10...600), weightKg: w)
    }

    /// Parole simili: uguali o con la stessa radice ("polpacci"/"polpaccio", "squat"/"squats").
    static func close(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let p = a.commonPrefix(with: b).count
        return p >= 5 && p >= min(a.count, b.count) - 2
    }

    /// Vero se le parole del nome sono (quasi tutte) nel testo: il modello non deve inventare esercizi.
    static func grounded(_ name: String, source: Set<String>) -> Bool {
        let base = name.components(separatedBy: " (").first ?? name
        let words = ExerciseMatcher.tokens(base.isEmpty ? name : base).filter { $0.count > 2 && $0.contains(where: \.isLetter) }
        guard !words.isEmpty else { return false }
        let found = words.filter { w in source.contains { close(w, $0) } }.count
        return found * 10 >= words.count * 6
    }

    /// Toglie gli esercizi che non si trovano nel testo e unisce i giorni senza titolo a quello prima.
    public static func ground(_ parts: [TrainingPlan], text: String) -> TrainingPlan? {
        let source = ExerciseMatcher.tokens(text)
        var days: [PlanDay] = []
        for day in parts.flatMap(\.days) {
            let entries = day.entries.filter { grounded($0.name, source: source) }
            if entries.isEmpty { continue }
            let title = day.title.trimmingCharacters(in: .whitespaces)
            if var last = days.last, title.isEmpty || title.caseInsensitiveCompare(last.title) == .orderedSame {
                last.entries += entries
                days[days.count - 1] = last
            } else {
                days.append(PlanDay(title: title, entries: entries))
            }
        }
        return days.isEmpty ? nil : TrainingPlan(days: days)
    }

    /// Si usa la lettura dell'AI se ha trovato almeno meta' degli esercizi trovati dalle regole.
    public static func choose(rules: TrainingPlan, ai: TrainingPlan?) -> (plan: TrainingPlan, usedAI: Bool) {
        let a = ai?.allEntries.count ?? 0
        if let ai, a > 0, a * 2 >= rules.allEntries.count { return (ai, true) }
        return (rules, false)
    }

    /// Risultato finale della lettura: l'AI e' il motore principale (choose) e i dati che non ha trovato si completano con
    /// quelli letti dalle regole sullo stesso esercizio (complete). Quello che manca ancora lo conferma l'utente (gaps).
    public static func combine(rules: TrainingPlan, ai: TrainingPlan?) -> (plan: TrainingPlan, usedAI: Bool) {
        let choice = choose(rules: rules, ai: ai)
        return choice.usedAI ? (complete(choice.plan, with: rules), true) : choice
    }

    /// Completa la lettura dell'AI con quella delle regole: per ogni voce dell'AI si cerca la voce delle regole con lo
    /// stesso esercizio (nome simile, ognuna usata una volta sola, seguendo l'ordine della scheda) e si copiano solo i
    /// valori che l'AI non ha trovato. I valori trovati dall'AI non si cambiano mai.
    public static func complete(_ ai: TrainingPlan, with rules: TrainingPlan) -> TrainingPlan {
        let pool = rules.allEntries
        var used = [Bool](repeating: false, count: pool.count)
        var from = 0
        var out = ai
        for d in out.days.indices {
            for i in out.days[d].entries.indices {
                let e = out.days[d].entries[i]
                guard let k = sameExercise(e.name, pool: pool, used: used, from: from) else { continue }
                used[k] = true; from = k + 1
                let r = pool[k]
                var c = e
                let noReps = e.repsMin == nil && e.repsMax == nil && !isTimed(e)
                c.sets = e.sets ?? r.sets
                if noReps { c.repsMin = r.repsMin; c.repsMax = r.repsMax }
                c.restSeconds = e.restSeconds ?? r.restSeconds
                c.weightKg = e.weightKg ?? r.weightKg
                out.days[d].entries[i] = c
            }
        }
        return out
    }

    /// Voce libera delle regole con lo stesso esercizio: prima dopo l'ultima usata, poi dall'inizio.
    private static func sameExercise(_ name: String, pool: [PlanEntry], used: [Bool], from: Int) -> Int? {
        func same(_ i: Int) -> Bool { !used[i] && sameName(name, pool[i].name) }
        let start = min(from, pool.count)
        return (start..<pool.count).first(where: same) ?? (0..<start).first(where: same)
    }

    /// Stesso esercizio per nome: le parole dell'uno sono quasi tutte nell'altro, in entrambi i sensi.
    static func sameName(_ a: String, _ b: String) -> Bool { min(score(a, b), score(b, a)) >= 0.6 }

    // MARK: Dati mancanti (da far confermare all'utente prima di importare)

    /// Dati che la lettura deve trovare per ogni esercizio.
    public enum Missing: String, CaseIterable, Sendable { case sets, reps, weight }

    /// Esercizio di una scheda letta a cui manca qualche dato.
    public struct Gap: Equatable, Sendable {
        public let day: String
        public let name: String
        public let missing: [Missing]
    }

    /// Esercizio a tempo (durata nel nome, es. "Plank (40\")"): le ripetizioni non servono.
    public static func isTimed(_ e: PlanEntry) -> Bool {
        e.name.range(of: #"\d+\s*(["”″]|'')"#, options: .regularExpression) != nil
    }

    /// Dati che mancano a una voce: serie, ripetizioni (non per gli esercizi a tempo) e peso. Ordine: serie, ripetizioni, peso.
    /// Serie diverse: le serie ci sono sempre; mancano ripetizioni o peso se mancano in almeno una serie.
    public static func missing(_ e: PlanEntry) -> [Missing] {
        var out: [Missing] = []
        if !e.perSet.isEmpty {
            if e.perSet.contains(where: { $0.reps == nil }) && !isTimed(e) { out.append(.reps) }
            if e.perSet.contains(where: { ($0.weightKg ?? 0) <= 0 }) { out.append(.weight) }
            return out
        }
        if e.sets == nil { out.append(.sets) }
        if e.repsMin == nil && e.repsMax == nil && !isTimed(e) { out.append(.reps) }
        if (e.weightKg ?? 0) <= 0 { out.append(.weight) }
        return out
    }

    /// Esercizi (con nome) a cui manca almeno un dato, nell'ordine della scheda.
    public static func gaps(_ plan: TrainingPlan) -> [Gap] {
        plan.days.flatMap { d in
            d.entries.compactMap { e -> Gap? in
                let name = e.name.trimmingCharacters(in: .whitespaces)
                let m = missing(e)
                return name.isEmpty || m.isEmpty ? nil : Gap(day: d.title.trimmingCharacters(in: .whitespaces), name: name, missing: m)
            }
        }
    }

    // MARK: Stesso esercizio su piu' righe (serie diverse)

    /// Nome per riconoscere lo stesso esercizio su piu' righe: minuscole, spazi e punteggiatura finale normalizzati.
    static func mergeKey(_ name: String) -> String {
        name.lowercased().components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " :-–—,.;/|"))
    }

    /// Unisce le righe con lo stesso esercizio nello stesso giorno (anche non consecutive) in una sola voce con serie
    /// diverse: es. "Panca piana 2x10 40 kg" e "Panca piana 2x8 50 kg" diventano 4 serie (10, 10, 8, 8 ripetizioni con
    /// 40, 40, 50, 50 kg). La voce resta al posto della prima riga. Una riga senza serie vale una serie; con un intervallo
    /// di ripetizioni ("8-12") si usa il minimo. Se alla fine le serie sono tutte uguali si torna a una voce normale.
    /// Gli esercizi a tempo (durata nel nome) non si uniscono. Uguale su Android (PlanAI.mergeRepeated).
    public static func mergeRepeated(_ plan: TrainingPlan) -> TrainingPlan {
        var out = plan
        for d in out.days.indices {
            var order: [String] = []
            var groups: [String: [PlanEntry]] = [:]
            for (i, e) in out.days[d].entries.enumerated() {
                let k = mergeKey(e.name)
                let key = isTimed(e) || k.isEmpty ? "#\(i)" : k
                if groups[key] == nil { order.append(key) }
                groups[key, default: []].append(e)
            }
            out.days[d].entries = order.map { mergeGroup(groups[$0]!) }
        }
        return out
    }

    private static func mergeGroup(_ group: [PlanEntry]) -> PlanEntry {
        guard group.count > 1 else { return group[0] }
        let sets = group.flatMap { e -> [PlanSet] in
            e.perSet.isEmpty ? Array(repeating: PlanSet(reps: e.repsMin ?? e.repsMax, weightKg: e.weightKg), count: e.sets ?? 1) : e.perSet
        }
        var merged = group[0]
        merged.sets = sets.count
        merged.restSeconds = group.lazy.compactMap(\.restSeconds).first
        merged.exerciseID = group.lazy.compactMap(\.exerciseID).first
        if sets.allSatisfy({ $0 == sets[0] }) {
            merged.weightKg = sets[0].weightKg
            merged.perSet = []
        } else {
            merged.repsMin = sets.lazy.compactMap(\.reps).first
            merged.repsMax = merged.repsMin
            merged.weightKg = sets.lazy.compactMap(\.weightKg).first
            merged.perSet = sets
        }
        return merged
    }

    // MARK: Collegamento al catalogo

    /// Quanto il nome del catalogo e' contenuto nel nome della scheda (0-1).
    static func score(_ name: String, _ exercise: String) -> Double {
        let a = ExerciseMatcher.tokens(name), b = ExerciseMatcher.tokens(exercise)
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        let hit = Double(b.filter { w in a.contains { close($0, w) } }.count)
        return hit / Double(b.count) * 0.7 + hit / Double(a.count) * 0.3
    }

    /// Esercizi del catalogo piu' vicini al nome (da far scegliere al modello).
    public static func candidates(for name: String, in catalog: [CatalogExercise], k: Int = candidateCount) -> [CatalogExercise] {
        catalog.map { ($0, score(name, $0.name)) }.filter { $0.1 > 0.2 }
            .sorted { $0.1 > $1.1 }.prefix(k).map(\.0)
    }

    /// Senza modello: l'esercizio del catalogo piu' vicino, solo se e' chiaramente lo stesso.
    public static func localMatch(for name: String, in catalog: [CatalogExercise]) -> CatalogExercise? {
        let scored = catalog.map { ($0, score(name, $0.name), ExerciseMatcher.similarity(name, $0.name)) }.filter { $0.1 >= 0.6 }
        return scored.max { ($0.1, $0.2) < ($1.1, $1.2) }?.0
    }

    /// Esercizio del catalogo di una voce: quello collegato (exerciseID) o, se manca, il piu' simile per nome.
    public static func exercise(for entry: PlanEntry, in catalog: [CatalogExercise]) -> CatalogExercise? {
        if let id = entry.exerciseID, let ex = catalog.first(where: { $0.id == id }) { return ex }
        return ExerciseMatcher.bestMatch(for: entry.name, in: catalog)
    }

    /// Testo della richiesta di collegamento: per ogni numero i candidati "id = nome".
    public static func matchPrompt(names: [String], candidates: [[CatalogExercise]]) -> String {
        var text = """
        Per ogni esercizio di una scheda di palestra scegli tra i candidati l'esercizio del catalogo che è lo stesso \
        movimento (stessa attrezzatura se è indicata). Se nessun candidato è lo stesso esercizio usa un id vuoto.\n\n
        """
        for (i, n) in names.enumerated() where !candidates[i].isEmpty {
            text += "\(i + 1). \(n) -> candidati: " + candidates[i].map { "\($0.id) = \($0.name)" }.joined(separator: " ; ") + "\n"
        }
        return text
    }

    /// Tiene solo le scelte valide: numero esistente e id tra i candidati di quel numero (indici da 0).
    /// `pairs`: (numero dell'esercizio da 1, id scelto).
    public static func validMatches(_ pairs: [(Int, String)], candidates: [[CatalogExercise]]) -> [Int: String] {
        var out: [Int: String] = [:]
        for (number, id) in pairs {
            let i = number - 1
            guard candidates.indices.contains(i), candidates[i].contains(where: { $0.id == id }) else { continue }
            out[i] = id
        }
        return out
    }

    /// Mette l'esercizio del catalogo su ogni voce: quello scelto dal modello (indici sulla lista di tutte le voci) o,
    /// dove il modello non ha scelto, quello chiaramente uguale per le regole (localMatch); altrimenti nessuno.
    public static func applyMatches(_ plan: TrainingPlan, catalog: [CatalogExercise], chosen: [Int: String]?) -> TrainingPlan {
        var i = 0
        var out = plan
        for d in out.days.indices {
            for e in out.days[d].entries.indices {
                let name = out.days[d].entries[e].name
                let id = chosen?[i] ?? localMatch(for: name, in: catalog)?.id
                if let id { out.days[d].entries[e].exerciseID = id }
                i += 1
            }
        }
        // Ultimo passo della lettura: le righe con lo stesso esercizio nello stesso giorno diventano serie diverse.
        return mergeRepeated(out)
    }

    /// Risultato della lettura (per l'anteprima e per il rapporto d'errore).
    public struct Result: Sendable {
        public let plan: TrainingPlan
        public let usedAI: Bool
        public let aiStatus: String
        public let aiError: String?
        public init(plan: TrainingPlan, usedAI: Bool, aiStatus: String, aiError: String? = nil) {
            self.plan = plan; self.usedAI = usedAI; self.aiStatus = aiStatus; self.aiError = aiError
        }
    }
}
