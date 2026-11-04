import Foundation

// MARK: - Scheda Profilo: statistiche degli allenamenti
//
// Percentuale di utilizzo dei muscoli e grafici dell'andamento nel periodo scelto (giorno, settimana, mese, anno,
// totale). Tutto calcolato sul telefono dallo storico. Uguale su Android: ProfileStats.kt (stessi risultati, stessi test).
// I tempi sono millisecondi dal 1970 (Int64), come su Android; il fuso e' un parametro.

/// Periodo scelto nella scheda Profilo: vale sia per le percentuali dei muscoli sia per i grafici.
public enum StatsPeriod: String, CaseIterable, Sendable {
    case day, week, month, year, all

    public var titleKey: String { "stats.period.\(rawValue)" }

    /// Nel piano Free si vede solo il giorno; gli altri periodi e i grafici sono del Pro (Feature.profileStats).
    public var isFree: Bool { self == .day }
}

/// Come leggere l'etichetta di una colonna dei grafici: fascia di ore (value = ora di inizio), giorno della settimana
/// (value 1 = lunedì ... 7 = domenica), giorno del mese, mese (1-12, con l'anno) o anno.
public enum BucketKind: Sendable { case hours, weekday, dayOfMonth, month, year }

/// Una colonna dei grafici: intervallo [start, end) in millisecondi.
public struct StatsBucket: Equatable, Hashable, Sendable {
    public let start: Int64
    public let end: Int64
    public let kind: BucketKind
    public let value: Int
    public let year: Int
    public init(start: Int64, end: Int64, kind: BucketKind, value: Int, year: Int) {
        self.start = start; self.end = end; self.kind = kind; self.value = value; self.year = year
    }
}

/// Quota di lavoro di un muscolo nel periodo: punteggio (serie pesate) e percentuale sul totale (0-100).
public struct MuscleShare: Equatable, Sendable {
    public let muscle: MuscleGroup
    public let score: Double
    public let percent: Double
}

/// Totali di un periodo o di una colonna. `workouts` = giorni con almeno un esercizio svolto; `sets` = serie con almeno
/// una ripetizione; `volumeKg` = somma di ripetizioni × peso di ogni serie.
public struct StatsTotals: Equatable, Sendable {
    public let workouts: Int
    public let sessions: Int
    public let sets: Int
    public let reps: Int
    public let volumeKg: Double
    public init(workouts: Int, sessions: Int, sets: Int, reps: Int, volumeKg: Double) {
        self.workouts = workouts; self.sessions = sessions; self.sets = sets; self.reps = reps; self.volumeKg = volumeKg
    }
    public static let zero = StatsTotals(workouts: 0, sessions: 0, sets: 0, reps: 0, volumeKg: 0)
}

/// Pesata del corpo (scheda Profilo): una al giorno, l'ultima inserita vale per quel giorno.
public struct WeightEntry: Equatable, Hashable, Sendable {
    public let at: Int64
    public let kg: Double
    public init(at: Int64, kg: Double) { self.at = at; self.kg = kg }
}

/// Serie di una sessione per le statistiche (sull'app viene da SetLogRecord).
public struct StatsSet: Equatable, Sendable {
    public let doneReps: Int
    public let weightKg: Double
    public init(doneReps: Int, weightKg: Double) { self.doneReps = doneReps; self.weightKg = weightKg }
}

/// Sessione dello storico ridotta a cio' che serve alle statistiche (sull'app viene da WorkoutSessionRecord;
/// su Android e' WorkoutSessionRecord del Core).
public struct StatsSession: Equatable, Sendable {
    public let startedAt: Int64
    public let exerciseID: String
    public let sets: [StatsSet]
    public init(startedAt: Int64, exerciseID: String, sets: [StatsSet]) {
        self.startedAt = startedAt; self.exerciseID = exerciseID; self.sets = sets
    }
}

public enum ProfileStats {
    /// Ogni serie svolta conta 1 per i muscoli principali dell'esercizio e 0,5 per i secondari.
    public static let primaryWeight = 1.0
    public static let secondaryWeight = 0.5
    /// Grafico del giorno: 6 colonne da 4 ore (0, 4, 8, 12, 16, 20).
    public static let hoursPerBucket = 4
    /// "Totale": una colonna per mese finché sono al massimo 24 mesi, poi una per anno.
    public static let maxMonthBuckets = 24

    // MARK: Date e millisecondi

    /// Millisecondi dal 1970 di una data (per chi usa Date nell'app).
    public static func millis(_ date: Date) -> Int64 { Int64((date.timeIntervalSince1970 * 1000).rounded()) }
    static func date(_ ms: Int64) -> Date { Date(timeIntervalSince1970: Double(ms) / 1000) }

    /// Calendario gregoriano nel fuso indicato, con la settimana che inizia di lunedì (come java.time su Android).
    static func calendar(_ zone: TimeZone) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = zone
        c.firstWeekday = 2
        return c
    }

    /// Inizio del giorno `day` del mese `month` dell'anno `year` (mese anche fuori da 1-12: si passa all'anno giusto).
    static func dayStart(_ cal: Calendar, year: Int, month: Int, day: Int = 1, hour: Int = 0) -> Date {
        let m0 = month - 1
        let y = year + Int((Double(m0) / 12).rounded(.down))
        let m = ((m0 % 12) + 12) % 12 + 1
        return cal.date(from: DateComponents(year: y, month: m, day: day, hour: hour)) ?? Date(timeIntervalSince1970: 0)
    }

    /// Chiave del giorno nel fuso (anno, mese, giorno).
    static func dayKey(_ ms: Int64, _ cal: Calendar) -> Int {
        let c = cal.dateComponents([.year, .month, .day], from: date(ms))
        return (c.year ?? 0) * 10_000 + (c.month ?? 0) * 100 + (c.day ?? 0)
    }

    /// Primo istante di cui servono i dati per "Totale": la sessione o la pesata più vecchia (nil se non ce ne sono).
    public static func firstActivity(_ sessions: [StatsSession], _ weights: [WeightEntry]) -> Int64? {
        (sessions.map(\.startedAt) + weights.map(\.at)).min()
    }

    /// Colonne dei grafici del periodo, dalla più vecchia: giorno = 6 fasce di 4 ore di oggi; settimana = da lunedì a
    /// domenica della settimana in corso; mese = i giorni del mese in corso; anno = i 12 mesi dell'anno in corso;
    /// totale = i mesi dal primo dato a oggi (o gli anni, se i mesi sono più di `maxMonthBuckets`).
    /// I confini si calcolano dalle date (non sommando millisecondi): giusti anche nei giorni del cambio d'ora.
    public static func buckets(_ period: StatsPeriod, now: Int64, zone: TimeZone, firstActivity: Int64?) -> [StatsBucket] {
        let cal = calendar(zone)
        let today = cal.startOfDay(for: date(now))
        let tc = cal.dateComponents([.year, .month, .day], from: today)
        let year = tc.year ?? 1970, month = tc.month ?? 1, day = tc.day ?? 1
        // Somma di giorni sul calendario (resta la mezzanotte anche nei giorni del cambio d'ora, come plusDays su Android)
        func addDays(_ d: Date, _ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: d) ?? d }
        func nextDay(_ d: Date) -> Date { addDays(d, 1) }
        switch period {
        case .day:
            let n = 24 / hoursPerBucket
            return (0..<n).map { i in
                let h = i * hoursPerBucket
                let s = dayStart(cal, year: year, month: month, day: day, hour: h)
                let e = i == n - 1 ? nextDay(today) : dayStart(cal, year: year, month: month, day: day, hour: h + hoursPerBucket)
                return StatsBucket(start: millis(s), end: millis(e), kind: .hours, value: h, year: cal.component(.year, from: s))
            }
        case .week:
            // weekday: 1 = domenica ... 7 = sabato; giorni da lunedì: lunedì 0 ... domenica 6
            let fromMonday = (cal.component(.weekday, from: today) + 5) % 7
            return (0..<7).map { i in
                let s = addDays(today, i - fromMonday)
                return StatsBucket(start: millis(s), end: millis(nextDay(s)), kind: .weekday, value: i + 1,
                                   year: cal.component(.year, from: s))
            }
        case .month:
            let length = cal.range(of: .day, in: .month, for: today)?.count ?? 30
            let first = dayStart(cal, year: year, month: month)
            return (0..<length).map { i in
                let s = addDays(first, i)
                return StatsBucket(start: millis(s), end: millis(nextDay(s)), kind: .dayOfMonth, value: i + 1,
                                   year: cal.component(.year, from: s))
            }
        case .year:
            return monthBuckets(cal, year: year, month: 1, count: 12)
        case .all:
            let fc = cal.dateComponents([.year, .month], from: date(min(firstActivity ?? now, now)))
            let fy = fc.year ?? year, fm = fc.month ?? month
            let months = (year * 12 + month) - (fy * 12 + fm) + 1
            if months <= maxMonthBuckets { return monthBuckets(cal, year: fy, month: fm, count: months) }
            return (fy...year).map { y in
                StatsBucket(start: millis(dayStart(cal, year: y, month: 1)), end: millis(dayStart(cal, year: y + 1, month: 1)),
                            kind: .year, value: y, year: y)
            }
        }
    }

    static func monthBuckets(_ cal: Calendar, year: Int, month: Int, count: Int) -> [StatsBucket] {
        (0..<count).map { i in
            let s = dayStart(cal, year: year, month: month + i)
            let c = cal.dateComponents([.year, .month], from: s)
            return StatsBucket(start: millis(s), end: millis(dayStart(cal, year: year, month: month + i + 1)),
                               kind: .month, value: c.month ?? 1, year: c.year ?? year)
        }
    }

    /// Intervallo [start, end) di tutto il periodo (dall'inizio della prima colonna alla fine dell'ultima).
    public static func range(_ period: StatsPeriod, now: Int64, zone: TimeZone, firstActivity: Int64?) -> (Int64, Int64) {
        let b = buckets(period, now: now, zone: zone, firstActivity: firstActivity)
        return (b.first?.start ?? now, b.last?.end ?? now)
    }

    static func doneSets(_ s: StatsSession) -> [StatsSet] { s.sets.filter { $0.doneReps > 0 } }

    /// Percentuale di utilizzo dei muscoli nell'intervallo [from, to): per ogni sessione di un esercizio del catalogo,
    /// ogni serie svolta vale `primaryWeight` per ogni muscolo principale e `secondaryWeight` per ogni secondario.
    /// Solo i muscoli usati, dal più usato (a parità, nell'ordine di MuscleGroup). Lista vuota se non c'è nulla.
    public static func muscleShares(_ sessions: [StatsSession], catalog: [CatalogExercise], from: Int64, to: Int64) -> [MuscleShare] {
        let byID = Dictionary(catalog.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let all = MuscleGroup.allCases
        var scores = [Double](repeating: 0, count: all.count)
        func index(_ m: MuscleGroup) -> Int { all.firstIndex(of: m) ?? 0 }
        for s in sessions {
            if s.startedAt < from || s.startedAt >= to { continue }
            guard let ex = byID[s.exerciseID] else { continue }
            let n = Double(doneSets(s).count)
            if n == 0 { continue }
            var primary: [MuscleGroup] = []
            for m in ex.primary where !primary.contains(m) { primary.append(m) }
            for m in primary { scores[index(m)] += n * primaryWeight }
            var secondary: [MuscleGroup] = []
            for m in ex.secondary where !secondary.contains(m) && !primary.contains(m) { secondary.append(m) }
            for m in secondary { scores[index(m)] += n * secondaryWeight }
        }
        let total = scores.reduce(0, +)
        if total <= 0 { return [] }
        return all.indices.filter { scores[$0] > 0 }
            .map { (i: $0, share: MuscleShare(muscle: all[$0], score: scores[$0], percent: scores[$0] / total * 100)) }
            .sorted { a, b in a.share.score != b.share.score ? a.share.score > b.share.score : a.i < b.i }
            .map(\.share)
    }

    /// Intensità del colore di ogni muscolo sulla figura (0-1): il più usato vale 1.
    public static func intensities(_ shares: [MuscleShare]) -> [MuscleGroup: Double] {
        guard let max = shares.map(\.score).max() else { return [:] }
        var out: [MuscleGroup: Double] = [:]
        for s in shares { out[s.muscle] = s.score / max }
        return out
    }

    /// Totali delle sessioni iniziate nell'intervallo [from, to).
    public static func totals(_ sessions: [StatsSession], from: Int64, to: Int64, zone: TimeZone) -> StatsTotals {
        let inRange = sessions.filter { $0.startedAt >= from && $0.startedAt < to }
        if inRange.isEmpty { return .zero }
        let cal = calendar(zone)
        let sets = inRange.flatMap { doneSets($0) }
        return StatsTotals(
            workouts: Set(inRange.filter { !doneSets($0).isEmpty }.map { dayKey($0.startedAt, cal) }).count,
            sessions: inRange.count,
            sets: sets.count,
            reps: sets.reduce(0) { $0 + $1.doneReps },
            volumeKg: sets.reduce(0.0) { $0 + Double($1.doneReps) * $1.weightKg })
    }

    /// Totali di ogni colonna (stesso ordine delle colonne).
    public static func series(_ sessions: [StatsSession], buckets: [StatsBucket], zone: TimeZone) -> [StatsTotals] {
        buckets.map { totals(sessions, from: $0.start, to: $0.end, zone: zone) }
    }

    /// Peso di ogni colonna: l'ultima pesata dentro la colonna (nil se in quella colonna non ci sono pesate).
    public static func weightSeries(_ log: [WeightEntry], buckets: [StatsBucket]) -> [Double?] {
        buckets.map { b in log.filter { $0.at >= b.start && $0.at < b.end }.max { $0.at < $1.at }?.kg }
    }
}

/// Storico delle pesate del corpo.
public enum WeightLog {
    /// Al massimo dieci anni di pesate giornaliere.
    public static let maxEntries = 3660

    /// Aggiunge la pesata di oggi (sostituisce quella già inserita oggi). Il peso è limitato a 30-250 kg come nel
    /// profilo e arrotondato a 0,1 kg. Lista ordinata dalla più vecchia.
    public static func upsert(_ log: [WeightEntry], kg: Double, now: Int64, zone: TimeZone) -> [WeightEntry] {
        let cal = ProfileStats.calendar(zone)
        let day = ProfileStats.dayKey(now, cal)
        let value = (min(max(kg, 30), 250) * 10).rounded() / 10
        let kept = log.filter { ProfileStats.dayKey($0.at, cal) != day } + [WeightEntry(at: now, kg: value)]
        // Ordinamento stabile per data (a parità resta l'ordine di partenza, come sortedBy su Android)
        let sorted = kept.enumerated().sorted { a, b in a.element.at != b.element.at ? a.element.at < b.element.at : a.offset < b.offset }
            .map(\.element)
        return Array(sorted.suffix(maxEntries))
    }

    /// Variazione tra la prima e l'ultima pesata dell'intervallo [from, to) (nil con meno di due pesate).
    public static func change(_ log: [WeightEntry], from: Int64, to: Int64) -> Double? {
        let inRange = log.filter { $0.at >= from && $0.at < to }.enumerated()
            .sorted { a, b in a.element.at != b.element.at ? a.element.at < b.element.at : a.offset < b.offset }.map(\.element)
        guard inRange.count >= 2, let first = inRange.first, let last = inRange.last else { return nil }
        let d = last.kg - first.kg
        return abs(d) < 1e-9 ? 0 : d
    }
}

// MARK: - Avatar della scheda Profilo

/// Avatar dell'utente: la sagoma di BodyFigure deformata con sesso, altezza e BMI. Più alto o più basso (altezza
/// 140-210 cm, scala rispetto a 175 cm), più largo o più stretto in modo diverso per spalle, vita e fianchi (BMI
/// 16-40) e con spalle più larghe per i maschi e fianchi più larghi per le femmine. Coordinate su `width` x `height`,
/// piedi sempre in basso. Nessuna immagine: solo tracciati SVG (comandi M, C, Z) come la figura dei muscoli.
public enum AvatarFigure {
    public static let width = 240.0
    public static let height = 520.0
    static let sourceCenter = 100.0
    static let center = 120.0
    static let sourceGround = 432.0
    static let ground = 516.0
    public static let referenceHeightCm = 175.0

    /// Altezze della figura originale (0-440) a cui sono fissati i fattori di larghezza; in mezzo si interpola.
    public static let knotY: [Double] = [0, 56, 70, 90, 140, 175, 225, 300, 440]
    /// Quanto ogni altezza segue il BMI: la vita più di tutto, la testa quasi niente.
    public static let bulkWeight: [Double] = [0.15, 0.25, 0.35, 0.45, 0.65, 0.8, 0.7, 0.55, 0.35]
    public static let maleShape: [Double] = [1.0, 1.0, 1.04, 1.06, 1.03, 1.0, 0.97, 0.98, 1.0]
    public static let femaleShape: [Double] = [0.97, 0.95, 0.94, 0.93, 0.95, 0.9, 1.06, 1.04, 0.98]

    /// Forma dell'avatar: scala dell'altezza e fattore di larghezza per ogni `knotY`.
    public struct Shape: Equatable, Sendable {
        public let heightScale: Double
        public let factors: [Double]
    }

    public static func shape(sex: BiologicalSex, heightCm: Double, weightKg: Double) -> Shape {
        let bmi = BMICalculator.calculate(weightKg: weightKg, heightCm: heightCm)?.value ?? 22
        let bulk = (min(max(bmi, 16), 40) - 22) / 18          // da -0,33 (molto magro) a 1 (obesità grave)
        let base = sex == .female ? femaleShape : maleShape
        let factors = knotY.indices.map { i in min(max(base[i] * (1 + bulk * bulkWeight[i]), 0.7), 1.55) }
        return Shape(heightScale: min(max(heightCm, 140), 210) / referenceHeightCm, factors: factors)
    }

    /// Fattore di larghezza all'altezza `y` della figura originale (interpolazione lineare tra i `knotY`).
    public static func factorAt(_ shape: Shape, _ y: Double) -> Double {
        if y <= knotY[0] { return shape.factors[0] }
        for i in 1..<knotY.count where y <= knotY[i] {
            let t = (y - knotY[i - 1]) / (knotY[i] - knotY[i - 1])
            return shape.factors[i - 1] + (shape.factors[i] - shape.factors[i - 1]) * t
        }
        return shape.factors[shape.factors.count - 1]
    }

    /// Punto della figura originale -> punto dell'avatar.
    public static func map(_ shape: Shape, _ x: Double, _ y: Double) -> (Double, Double) {
        (center + (x - sourceCenter) * factorAt(shape, y), ground - (sourceGround - y) * shape.heightScale)
    }

    private static let token = try! NSRegularExpression(pattern: "[MCZ]|-?\\d+(?:\\.\\d+)?")

    /// Numero con un decimale, uguale su Kotlin e Swift (arrotondamento `.rounded()`, punto come separatore).
    public static func format1(_ v: Double) -> String {
        let t = Int((v * 10).rounded())
        let sign = t < 0 ? "-" : ""
        let a = abs(t)
        return "\(sign)\(a / 10).\(a % 10)"
    }

    /// Tracciato deformato: i numeri vanno a coppie (x y) dopo M e C.
    public static func transform(_ path: String, _ shape: Shape) -> String {
        var out = ""
        var pending: [Double] = []
        let ns = path as NSString
        for m in token.matches(in: path, range: NSRange(location: 0, length: ns.length)) {
            let t = ns.substring(with: m.range)
            if t == "M" || t == "C" || t == "Z" {
                pending.removeAll(); out += t
            } else {
                pending.append(Double(t) ?? 0)
                if pending.count == 2 {
                    let (x, y) = map(shape, pending[0], pending[1])
                    if let last = out.last, last != "M" && last != "C" { out += " " }
                    out += format1(x) + " " + format1(y)
                    pending.removeAll()
                }
            }
        }
        return out
    }

    /// Tracciati dell'avatar (testa, tronco e gambe, braccia).
    public static func paths(sex: BiologicalSex, heightCm: Double, weightKg: Double) -> [String] {
        let s = shape(sex: sex, heightCm: heightCm, weightKg: weightKg)
        return BodyFigure.silhouette.map { transform($0, s) }
    }
}
