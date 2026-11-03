import Foundation

/// Una serie di una voce di scheda con serie diverse; nil = dato non trovato nella scheda (lo conferma l'utente).
public struct PlanSet: Codable, Equatable, Hashable, Sendable {
    public var reps: Int?
    public var weightKg: Double?
    public init(reps: Int?, weightKg: Double?) { self.reps = reps; self.weightKg = weightKg }
}

public struct PlanEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var sets: Int?
    public var repsMin: Int?
    public var repsMax: Int?
    public var restSeconds: Int?
    public var weightKg: Double?
    /// Esercizio del catalogo collegato alla voce (scelto dall'AI o per somiglianza del nome); nil = non collegato.
    public var exerciseID: String?
    /// Serie diverse: una voce per serie (dalle righe della scheda con lo stesso esercizio, vedi PlanAI.mergeRepeated).
    /// Vuoto = serie tutte uguali, descritte da sets/repsMin/repsMax/weightKg. Se pieno, `sets` e' il numero di serie.
    public var perSet: [PlanSet]

    public init(id: UUID = UUID(), name: String, sets: Int? = nil, repsMin: Int? = nil, repsMax: Int? = nil,
                restSeconds: Int? = nil, weightKg: Double? = nil, exerciseID: String? = nil, perSet: [PlanSet] = []) {
        self.id = id; self.name = name; self.sets = sets; self.repsMin = repsMin; self.repsMax = repsMax
        self.restSeconds = restSeconds; self.weightKg = weightKg; self.exerciseID = exerciseID; self.perSet = perSet
    }

    /// Lettura dei dati salvati: le schede salvate prima delle serie diverse non hanno "perSet".
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        sets = try c.decodeIfPresent(Int.self, forKey: .sets)
        repsMin = try c.decodeIfPresent(Int.self, forKey: .repsMin)
        repsMax = try c.decodeIfPresent(Int.self, forKey: .repsMax)
        restSeconds = try c.decodeIfPresent(Int.self, forKey: .restSeconds)
        weightKg = try c.decodeIfPresent(Double.self, forKey: .weightKg)
        exerciseID = try c.decodeIfPresent(String.self, forKey: .exerciseID)
        perSet = try c.decodeIfPresent([PlanSet].self, forKey: .perSet) ?? []
    }

    public var target: PlanTarget {
        PlanTarget(sets: sets, repsMin: repsMin, repsMax: repsMax, restSeconds: restSeconds, weightKg: weightKg,
                   perSet: perSet.map { SetTarget(reps: $0.reps ?? repsMin ?? repsMax ?? WorkoutItem.defaultParameters.reps,
                                                  weightKg: $0.weightKg ?? 0) })
    }

    /// Voce con le serie indicate (modifica a mano nella revisione): serie, ripetizioni e peso della voce seguono
    /// le serie (numero di serie, valori della prima serie che li ha).
    public func withSets(_ list: [PlanSet]) -> PlanEntry {
        var e = self
        e.perSet = list
        e.sets = list.count
        e.repsMin = list.lazy.compactMap(\.reps).first
        e.repsMax = e.repsMin
        e.weightKg = list.lazy.compactMap(\.weightKg).first
        return e
    }
}

public struct PlanDay: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var entries: [PlanEntry]
    public init(id: UUID = UUID(), title: String, entries: [PlanEntry]) {
        self.id = id; self.title = title; self.entries = entries
    }
}

public struct TrainingPlan: Codable, Equatable, Sendable {
    public var days: [PlanDay]
    public init(days: [PlanDay]) { self.days = days }
    public var allEntries: [PlanEntry] { days.flatMap(\.entries) }
}

private func firstMatch(_ pattern: String, in text: String) -> [String?]? {
    guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
    let ns = text as NSString
    guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
    return (0..<m.numberOfRanges).map { i in
        let r = m.range(at: i)
        return r.location == NSNotFound ? nil : ns.substring(with: r)
    }
}

private func removing(_ pattern: String, from text: String) -> String {
    text.replacingOccurrences(of: "(?i)" + pattern, with: " ", options: .regularExpression)
}

/// Estrattore di schede di allenamento da testo (PDF o foto): riconosce giorni, esercizi, serie x ripetizioni,
/// carico e recupero in italiano e inglese. E' un'euristica: l'utente deve sempre controllare il risultato.
public enum TrainingPlanParser {
    static let setsRepsX = #"(\d{1,2})\s*[x×*]\s*(\d{1,3})(?:\s*[-–]\s*(\d{1,3}))?"#
    static let setsRepsWords = #"(\d{1,2})\s*(?:serie|series|sets?)\s*(?:da|di|x|of|per)?\s*(\d{1,3})(?:\s*[-–]\s*(\d{1,3}))?"#
    static let weight = #"(\d{1,3}(?:[.,]\d{1,2})?)\s*(?:kg|kili|chili)"#
    static let rest = #"(?:rec(?:upero)?|rest|pausa|riposo)\.?\s*:?\s*(\d{1,3})\s*(min|m|''|"|sec|s|')?"#
    static let dayHeading = #"^(?:giorno|day|allenamento|workout|sessione|seduta|scheda|settimana|week)\b.{0,30}$"#
    static let weekday = #"^(?:luned[iì]|marted[iì]|mercoled[iì]|gioved[iì]|venerd[iì]|sabato|domenica|monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b.{0,20}$"#

    static func stripBullet(_ line: String) -> String {
        line.replacingOccurrences(of: #"^\s*(?:[-•*·]|\d{1,2}[.)])\s+"#, with: "", options: .regularExpression)
    }

    static func restSeconds(value: Int, unit: String?) -> Int {
        switch unit?.lowercased() {
        case "min", "m", "'": return value * 60
        // Un recupero di pochi secondi non e' realistico: "rec 3\"" si intende come 3 minuti.
        case "''", "\"", "sec", "s": return value < 10 ? value * 60 : value
        default: return value <= 10 ? value * 60 : value
        }
    }

    static func parseEntry(_ line: String) -> PlanEntry? {
        var usedPattern = setsRepsX
        var sr = firstMatch(setsRepsX, in: line)
        if sr == nil { usedPattern = setsRepsWords; sr = firstMatch(setsRepsWords, in: line) }
        guard let g = sr, let sets = g[1].flatMap({ Int($0) }), let repsA = g[2].flatMap({ Int($0) }) else { return nil }
        let repsB = g.count > 3 ? g[3].flatMap({ Int($0) }) : nil
        let lo = min(repsA, repsB ?? repsA), hi = max(repsA, repsB ?? repsA)
        guard (1...12).contains(sets), (1...100).contains(lo) else { return nil }

        var weightKg: Double?
        if let w = firstMatch(weight, in: line), let s = w[1] { weightKg = Double(s.replacingOccurrences(of: ",", with: ".")) }
        var restSec: Int?
        if let r = firstMatch(rest, in: line), let s = r[1], let v = Int(s) { restSec = restSeconds(value: v, unit: r.count > 2 ? r[2] : nil) }

        var name = line
        for p in [usedPattern, weight, rest] { name = removing(p, from: name) }
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: " :-–—,.;()/\t"))
        name = name.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
        guard name.filter(\.isLetter).count >= 3 else { return nil }
        return PlanEntry(name: name, sets: sets, repsMin: lo, repsMax: hi, restSeconds: restSec, weightKg: weightKg)
    }

    static func dayTitle(_ line: String) -> String? {
        let clean = line.trimmingCharacters(in: CharacterSet(charactersIn: " :-–—"))
        if firstMatch(dayHeading, in: clean) != nil || firstMatch(weekday, in: clean) != nil
            || firstMatch(section, in: clean) != nil { return clean }
        return nil
    }

    // MARK: Schede a blocchi: "SET 1 DA RIPETERE 4 VOLTE (1.30 MIN DI RECUPERO)" e righe "6 Squat" (come Plans.kt)

    /// Parte di allenamento con un titolo proprio (riscaldamento, defaticamento ...): diventa un giorno a parte.
    static let section = #"^(?:riscaldamento|warm[\s-]?up|defaticamento|cool[\s-]?down|stretching|mobilit[aà]|attivazione)\b.{0,40}$"#
    /// Intestazione di un blocco: serie, giri, circuito, superserie... con quante volte si ripete e il recupero.
    static let block = #"^(?:set|serie|blocco|circuito|superserie|superset|giro|round)\s*\d{0,2}\b(.*)$"#
    static let repeatCount = #"(?:ripetere|ripeti|ripetuto|per|x)\s*(\d{1,2})\s*(?:volte|volta|giri|giro|round)\b|(\d{1,2})\s*(?:volte|giri|round)\b"#
    /// Recupero scritto prima della parola: "1.30 MIN DI RECUPERO" (1 minuto e 30), "60” DI RECUPERO".
    static let blockRest = #"(\d{1,2})(?:[.,:](\d{1,2}))?\s*(min(?:uti)?\b|'|’|sec(?:ondi)?\b|s\b|”|″|"|'')?\s*(?:di\s+)?(?:recupero|rec\b|pausa|riposo)"#
    /// Riga che inizia con le ripetizioni ("6 Squat", "10 - 6 - 10 Hip thrust") o con il tempo ("40” Plank").
    static let leading = #"^((?:\d{1,3}\s*[-–]\s*)*\d{1,3})\s*(”|″|"|''|sec(?:ondi)?\b|s\b|min(?:uti)?\b|'|’)?\s+(?=\w)(.*)$"#
    /// Dopo il numero non c'e' un esercizio ma un'unita' (alimenti, durate): "100 g riso", "15 minuti".
    static let notName = #"^(?:g|gr|grammi|ml|cl|l|kcal|cal|kg|minuti|minuto|min|secondi|sec|ore|volte|serie|x)\b"#

    /// Serie e recupero dell'intestazione di un blocco; nil se la riga non e' un'intestazione.
    static func blockHeader(_ line: String) -> (sets: Int, rest: Int?)? {
        guard let g = firstMatch(block, in: line) else { return nil }
        let rest = g.count > 1 ? (g[1] ?? "") : ""
        let r = firstMatch(repeatCount, in: rest)
        let sets = r.flatMap { m in (m[1] ?? m[2]).flatMap { Int($0) } } ?? 1
        var restSec: Int?
        if let b = firstMatch(blockRest, in: rest), let v = b[1].flatMap({ Int($0) }) {
            let frac = b[2]
            let unit = b[3]?.lowercased() ?? ""
            if unit.hasPrefix("min") || unit == "'" || unit == "’" {
                let extra = frac.flatMap { $0.count == 2 ? Int($0) : nil }.flatMap { $0 < 60 ? $0 : nil } ?? 0
                restSec = v * 60 + extra
            } else if !unit.isEmpty {
                restSec = v
            } else {
                restSec = v <= 10 ? v * 60 : v
            }
        }
        // "SET 1 Panca": senza volte ne' recupero non e' un'intestazione
        if r == nil && restSec == nil && !rest.trimmingCharacters(in: .whitespaces).isEmpty { return nil }
        return (min(max(sets, 1), 12), restSec)
    }

    /// Esercizi di una riga che inizia con il numero. Piu' esercizi separati da "+" (serie a scalare) diventano
    /// esercizi distinti; serie e recupero vengono dall'intestazione del blocco. A tempo: il tempo va nel nome.
    static func parseLeading(_ line: String, blockSets: Int?, blockRest: Int?) -> [PlanEntry]? {
        var out: [PlanEntry] = []
        let parts = line.replacingOccurrences(of: #"\s\+\s*(?=\d)"#, with: "\u{1F}", options: .regularExpression)
            .components(separatedBy: "\u{1F}")
        for part in parts {
            guard let g = firstMatch(leading, in: part.trimmingCharacters(in: .whitespaces)), let numsText = g[1] else {
                return out.isEmpty ? nil : out
            }
            let nums = numsText.components(separatedBy: CharacterSet(charactersIn: "-–")).compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            let unit = g[2]?.lowercased() ?? ""
            let name = (g[3] ?? "").components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
                .trimmingCharacters(in: CharacterSet(charactersIn: " :-–—,.;/"))
            guard let first = nums.first, let top = nums.max(), firstMatch(notName, in: name) == nil,
                  name.filter(\.isLetter).count >= 3, top <= 100 else { return out.isEmpty ? nil : out }
            let sets = blockSets ?? 1
            if !unit.isEmpty {
                let seconds = unit.hasPrefix("min") || unit == "'" || unit == "’" ? first * 60 : first
                out.append(PlanEntry(name: "\(name) (\(seconds)\")", sets: sets, restSeconds: blockRest))
            } else if nums.count > 1 {
                // "10 - 6 - 10 - 6 - 10": una serie per numero (se il blocco non dice gia' quante)
                out.append(PlanEntry(name: name, sets: sets > 1 ? sets : nums.count, repsMin: nums.min(), repsMax: top, restSeconds: blockRest))
            } else {
                out.append(PlanEntry(name: name, sets: sets, repsMin: first, repsMax: first, restSeconds: blockRest))
            }
        }
        return out.isEmpty ? nil : out
    }

    public static func parse(_ text: String) -> TrainingPlan {
        var days: [PlanDay] = []
        var current = PlanDay(title: "", entries: [])
        var header: TableHeader?
        var blockInfo: (sets: Int, rest: Int?)?      // serie e recupero del blocco in corso
        var lastWasLeading = false                  // la riga prima era "6 Squat ...": la prossima puo' continuarne il nome
        func flush() { if !current.entries.isEmpty { days.append(current) } }
        func newDay(_ title: String) { flush(); current = PlanDay(title: title, entries: []); blockInfo = nil }
        for raw in text.components(separatedBy: .newlines) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let line = stripBullet(trimmed)
            // Intestazione di una tabella (Esercizio | Serie | Ripetizioni | Peso): da qui si leggono le colonne.
            if let h = tableHeader(raw) {
                header = h
                if let title = h.dayTitle { newDay(title) }
                continue
            }
            // Riga completa della tabella: si legge per colonne; altrimenti prima il formato "4x8" e poi le colonne in ordine.
            let fullRow = header.map { $0.byIndex && cells(raw).count >= $0.columns.count } ?? false
            let entry = fullRow ? (parseRow(raw, header: header!) ?? parseEntry(line)) : parseEntry(line)
            if let entry { current.entries.append(entry); lastWasLeading = false; continue }
            // Schede a blocchi (Word/PDF): intestazione del blocco, poi righe che iniziano con ripetizioni o tempo.
            let flat = line.replacingOccurrences(of: "\t", with: " ")
            if let b = blockHeader(flat) { blockInfo = b; lastWasLeading = false; continue }
            if let lead = parseLeading(flat, blockSets: blockInfo?.sets, blockRest: blockInfo?.rest) {
                current.entries.append(contentsOf: lead); lastWasLeading = true; continue
            }
            // Nome andato a capo ("... + 8 Abductor" / "machine con peso piu' basso"): si unisce all'esercizio prima.
            if lastWasLeading, !current.entries.isEmpty, let c = flat.first, c.isLowercase {
                current.entries[current.entries.count - 1].name += " " + flat
                continue
            }
            lastWasLeading = false
            if let title = dayTitle(line) { newDay(title); continue }
            if !fullRow, let header, let row = parseRow(raw, header: header) { current.entries.append(row) }
        }
        flush()
        return TrainingPlan(days: days)
    }

    // MARK: Tabelle: Excel, Word, CSV e PDF/foto con le colonne

    enum Column { case name, sets, reps, setsReps, weight, rest, other }

    /// Intestazione riconosciuta. byIndex: le celle sono separate (TAB o "|") e si leggono per posizione;
    /// altrimenti l'intestazione era una riga unica (OCR) e i valori si assegnano in ordine.
    struct TableHeader: Equatable {
        var columns: [Column]
        var byIndex: Bool
        var dayTitle: String? = nil
    }

    static let nameWords: Set<String> = ["esercizio", "esercizi", "exercise", "exercises", "nome", "name", "movimento", "attrezzo"]
    static let setsWords: Set<String> = ["serie", "series", "set", "sets", "giri"]
    static let repsWords: Set<String> = ["ripetizioni", "ripetizione", "rip", "ripet", "ripetiz", "reps", "rep", "repetitions", "repetition"]
    static let weightWords: Set<String> = ["peso", "pesi", "carico", "kg", "weight", "load", "kili", "chili"]
    static let restWords: Set<String> = ["recupero", "recuperi", "rec", "pausa", "riposo", "rest"]

    /// Parole (solo lettere, minuscole) di una cella.
    static func words(_ text: String) -> [String] {
        var out: [String] = []
        var w = ""
        for ch in text.lowercased() {
            if ch.isLetter { w.append(ch) } else if !w.isEmpty { out.append(w); w = "" }
        }
        if !w.isEmpty { out.append(w) }
        return out
    }

    static func column(of word: String) -> Column {
        if nameWords.contains(word) { return .name }
        if setsWords.contains(word) { return .sets }
        if repsWords.contains(word) { return .reps }
        if weightWords.contains(word) { return .weight }
        if restWords.contains(word) { return .rest }
        return .other
    }

    /// Celle di una riga: separate da TAB (Excel, Word, OCR) o da "|".
    static func cells(_ line: String) -> [String] {
        let ws = CharacterSet.whitespaces
        if line.contains("\t") { return line.components(separatedBy: "\t").map { $0.trimmingCharacters(in: ws) } }
        if line.contains("|") { return line.components(separatedBy: "|").map { $0.trimmingCharacters(in: ws) } }
        return [line.trimmingCharacters(in: ws)]
    }

    static func tableHeader(_ line: String) -> TableHeader? {
        if line.contains(where: \.isNumber) { return nil }
        let parts = cells(line)
        let byIndex = parts.count > 1
        var dayName: String?
        var columns: [Column]
        if byIndex {
            columns = parts.map { (cell: String) -> Column in
                let found = words(cell).map(column(of:)).filter { $0 != .other }
                if found.contains(.sets) && found.contains(.reps) { return .setsReps }
                if let first = found.first { return first }
                if dayName == nil && !cell.isEmpty { dayName = dayTitle(cell) }
                return .other
            }
        } else {
            // Riga unica (OCR): una colonna per parola riconosciuta, senza ripetizioni consecutive ("Peso (kg)").
            columns = []
            for c in words(line).map(column(of:)) where c != .other && columns.last != c { columns.append(c) }
        }
        let known = columns.filter { $0 != .other }
        guard known.count >= 2, known.contains(where: { $0 == .sets || $0 == .reps || $0 == .setsReps }) else { return nil }
        return TableHeader(columns: columns, byIndex: byIndex, dayTitle: dayName)
    }

    static let cellValue = #"\d{1,3}(?:[.,]\d{1,2})?(?:\s*[-–/x×*]\s*\d{1,3})?(?:\s*(?:kg|min|sec|s|''|"|'))?"#
    static let restUnit = #"(?:min|sec|s|''|"|')$"#

    private static func allMatches(_ pattern: String, in text: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
    }

    /// Una riga di dati letta con le colonne dell'intestazione.
    static func parseRow(_ line: String, header: TableHeader) -> PlanEntry? {
        let parts = cells(line)
        var values: [Column: String] = [:]
        var name: String?
        if header.byIndex && parts.count >= header.columns.count {
            for (i, c) in header.columns.enumerated() {
                let v = parts[i]
                if v.isEmpty { continue }
                switch c {
                case .name: if name == nil { name = v }
                case .other:
                    if name == nil, !header.columns.contains(.name), v.filter(\.isLetter).count >= 3,
                       firstMatch("^" + cellValue + "$", in: v) == nil { name = v }
                default: if values[c] == nil { values[c] = v }
                }
            }
        } else {
            // Celle mancanti (OCR) o riga unica: nome = testo prima del primo numero, poi i valori in ordine.
            let joined = parts.filter { !$0.isEmpty }.joined(separator: " ")
            guard let firstDigit = joined.firstIndex(where: \.isNumber), firstDigit != joined.startIndex else { return nil }
            name = String(joined[..<firstDigit])
            var found = allMatches(cellValue, in: String(joined[firstDigit...])).map { $0.trimmingCharacters(in: .whitespaces) }
            var numeric = header.columns.filter { $0 != .name && $0 != .other }
            // Le unita' decidono la colonna: "60 kg" e' il peso, "90''" il recupero.
            if let i = found.firstIndex(where: { $0.lowercased().hasSuffix("kg") }) {
                if let j = numeric.firstIndex(of: .weight) { values[.weight] = found[i]; numeric.remove(at: j) }
                found.remove(at: i)
            }
            if let i = found.firstIndex(where: { firstMatch(restUnit, in: $0) != nil }) {
                if let j = numeric.firstIndex(of: .rest) { values[.rest] = found[i]; numeric.remove(at: j) }
                found.remove(at: i)
            }
            for (c, v) in zip(numeric, found) { values[c] = v }
        }

        var sets: Int?, lo: Int?, hi: Int?
        if let v = values[.setsReps], let g = firstMatch(setsRepsX, in: v) ?? firstMatch(setsRepsWords, in: v) {
            sets = g[1].flatMap { Int($0) }; lo = g[2].flatMap { Int($0) }
            hi = (g.count > 3 ? g[3].flatMap { Int($0) } : nil) ?? lo
        }
        if let v = values[.sets] { sets = firstMatch(#"(\d{1,2})"#, in: v)?[1].flatMap { Int($0) } }
        if let v = values[.reps], let g = firstMatch(#"(\d{1,3})(?:\s*[-–/]\s*(\d{1,3}))?"#, in: v), let a = g[1].flatMap({ Int($0) }) {
            let b = g.count > 2 ? g[2].flatMap { Int($0) } : nil
            lo = min(a, b ?? a); hi = max(a, b ?? a)
        }
        if let s = sets, !(1...12).contains(s) { sets = nil }
        if let l = lo, !(1...100).contains(l) { lo = nil; hi = nil }
        if let h = hi, !(1...100).contains(h) { hi = lo }
        if sets == nil && lo == nil { return nil }

        var weightKg: Double?
        if let v = values[.weight], let s = firstMatch(#"(\d{1,3}(?:[.,]\d{1,2})?)"#, in: v)?[1],
           let w = Double(s.replacingOccurrences(of: ",", with: ".")), w > 0, w <= 500 { weightKg = w }
        let restSec = values[.rest].flatMap { restCell($0) }

        guard let name else { return nil }
        var clean = stripBullet(name).trimmingCharacters(in: CharacterSet(charactersIn: " :-–—,.;()/\t"))
        clean = clean.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
        guard clean.filter(\.isLetter).count >= 3 else { return nil }
        return PlanEntry(name: clean, sets: sets, repsMin: lo, repsMax: hi, restSeconds: restSec, weightKg: weightKg)
    }

    /// Recupero in una cella: 90, 90", 1'30, 1:30, 2 min.
    static func restCell(_ v: String) -> Int? {
        if let g = firstMatch(#"(\d{1,2})\s*[':]\s*(\d{2})"#, in: v), let m = g[1].flatMap({ Int($0) }), let s = g[2].flatMap({ Int($0) }) {
            let total = m * 60 + s
            return (5...900).contains(total) ? total : nil
        }
        guard let g = firstMatch(#"(\d{1,3})\s*(min|m|''|"|sec|s|')?"#, in: v), let value = g[1].flatMap({ Int($0) }) else { return nil }
        let sec = restSeconds(value: value, unit: g.count > 2 ? g[2] : nil)
        return (5...900).contains(sec) ? sec : nil
    }
}

// MARK: - Scheda del nutrizionista

public struct ParsedMeal: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var items: [String]
    public init(id: UUID = UUID(), name: String, items: [String]) { self.id = id; self.name = name; self.items = items }
}

public struct ParsedNutritionPlan: Codable, Equatable, Sendable {
    public var calories: Int?
    public var proteinG: Int?
    public var carbsG: Int?
    public var fatG: Int?
    public var meals: [ParsedMeal]
    public init(calories: Int? = nil, proteinG: Int? = nil, carbsG: Int? = nil, fatG: Int? = nil, meals: [ParsedMeal] = []) {
        self.calories = calories; self.proteinG = proteinG; self.carbsG = carbsG; self.fatG = fatG; self.meals = meals
    }
}

public enum NutritionPlanParser {
    static let mealWords = "colazione|spuntino|pranzo|merenda|cena|breakfast|lunch|dinner|snack"

    static func number(_ patterns: [String], in text: String, range: ClosedRange<Int>) -> Int? {
        for p in patterns {
            if let m = firstMatch(p, in: text), let s = m[1], let v = Int(s), range.contains(v) { return v }
        }
        return nil
    }

    public static func parse(_ text: String) -> ParsedNutritionPlan {
        let calories = number([#"(\d{3,4})\s*(?:kcal|cal\b)"#, #"calorie\D{0,12}(\d{3,4})"#], in: text, range: 800...6000)
        let protein = number([#"(?:proteine|protein)\D{0,12}(\d{2,3})\s*g"#, #"(\d{2,3})\s*g\s*(?:di\s*)?(?:proteine|protein)"#], in: text, range: 20...400)
        let carbs = number([#"(?:carboidrati|carbs?|carbohydrates)\D{0,12}(\d{2,3})\s*g"#, #"(\d{2,3})\s*g\s*(?:di\s*)?(?:carboidrati|carbs?|carbohydrates)"#], in: text, range: 20...800)
        let fat = number([#"(?:grassi|lipidi|fats?)\D{0,12}(\d{2,3})\s*g"#, #"(\d{2,3})\s*g\s*(?:di\s*)?(?:grassi|lipidi|fats?)"#], in: text, range: 10...300)

        var meals: [ParsedMeal] = []
        var current: ParsedMeal?
        for raw in text.components(separatedBy: .newlines) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let line = TrainingPlanParser.stripBullet(trimmed)
            if let m = firstMatch("^(" + mealWords + ")\\b\\s*[:\\-–]?\\s*(.*)$", in: line), let name = m[1] {
                if let c = current { meals.append(c) }
                var items: [String] = []
                if let rest = m[2], !rest.trimmingCharacters(in: .whitespaces).isEmpty { items.append(rest.trimmingCharacters(in: .whitespaces)) }
                current = ParsedMeal(name: name.capitalized, items: items)
            } else if current != nil {
                current?.items.append(line)
            }
        }
        if let c = current { meals.append(c) }
        return ParsedNutritionPlan(calories: calories, proteinG: protein, carbsG: carbs, fatG: fat, meals: meals)
    }
}

// MARK: - Risposta di un eventuale modello AI locale

/// Formato JSON che un modello AI locale deve restituire; i numeri vengono sempre limitati a valori plausibili.
public enum PlanAIOutput {
    struct EntryJSON: Decodable { let name: String?; let sets: Int?; let repsMin: Int?; let repsMax: Int?; let restSeconds: Int?; let weightKg: Double?; let seconds: Int? }
    struct DayJSON: Decodable { let title: String?; let entries: [EntryJSON]? }
    struct PlanJSON: Decodable { let days: [DayJSON]? }

    public static let trainingPrompt = """
    Estrai la scheda di allenamento dal testo. Rispondi SOLO con JSON valido nel formato \
    {"days":[{"title":"","entries":[{"name":"","sets":0,"repsMin":0,"repsMax":0,"restSeconds":0,"weightKg":0,"seconds":0}]}]}. \
    Non inventare dati: se un valore manca, omettilo.
    """

    /// Estrae il primo oggetto JSON dall'output del modello e lo trasforma in una scheda validata.
    public static func decodeTrainingPlan(from output: String) -> TrainingPlan? {
        guard let start = output.firstIndex(of: "{"), let end = output.lastIndex(of: "}"), start < end,
              let data = String(output[start...end]).data(using: .utf8),
              let json = try? JSONDecoder().decode(PlanJSON.self, from: data) else { return nil }
        let days: [PlanDay] = (json.days ?? []).compactMap { d in
            let entries: [PlanEntry] = (d.entries ?? []).compactMap { e in
                PlanAI.entry(name: e.name, sets: e.sets, repsMin: e.repsMin, repsMax: e.repsMax,
                             restSeconds: e.restSeconds, weightKg: e.weightKg, seconds: e.seconds)
            }
            return entries.isEmpty ? nil : PlanDay(title: d.title ?? "", entries: entries)
        }
        return days.isEmpty ? nil : TrainingPlan(days: days)
    }
}
