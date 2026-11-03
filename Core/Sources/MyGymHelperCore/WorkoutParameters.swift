import Foundation

/// Obiettivo di una singola serie: ripetizioni e peso (0 = corpo libero). Uguale su Android (SetTarget in Training.kt).
public struct SetTarget: Codable, Equatable, Hashable, Sendable {
    public var reps: Int
    public var weightKg: Double
    public init(reps: Int, weightKg: Double) { self.reps = reps; self.weightKg = weightKg }
}

/// Riga della modifica di un esercizio con le serie diverse: `count` serie uguali da `reps` ripetizioni con `weightKg`
/// (es. 3 serie da 10 con 40 kg, poi 2 da 8 con 50 kg). Uguale su Android (SetGroup in Training.kt).
public struct SetGroup: Equatable, Hashable, Sendable {
    public var count: Int
    public var reps: Int
    public var weightKg: Double
    public init(count: Int, reps: Int, weightKg: Double) { self.count = count; self.reps = reps; self.weightKg = weightKg }

    /// Righe dalle serie: le serie uguali una dopo l'altra diventano una riga sola.
    public static func group(_ targets: [SetTarget]) -> [SetGroup] {
        var out: [SetGroup] = []
        for t in targets {
            if let last = out.last, last.reps == t.reps, abs(last.weightKg - t.weightKg) < 1e-9 {
                out[out.count - 1].count += 1
            } else {
                out.append(SetGroup(count: 1, reps: t.reps, weightKg: t.weightKg))
            }
        }
        return out
    }

    /// Serie dalle righe, nell'ordine (righe con 0 serie ignorate).
    public static func expand(_ groups: [SetGroup]) -> [SetTarget] {
        groups.flatMap { g in Array(repeating: SetTarget(reps: g.reps, weightKg: g.weightKg), count: Swift.max(g.count, 0)) }
    }
}

/// Parametri di un allenamento su un esercizio: quelli impostati dall'utente o proposti da un consiglio.
/// Serie tutte uguali: `sets` serie da `reps` ripetizioni con `weightKg`.
/// Serie diverse (piani Mid e Full): `perSet` ha una voce per serie con le sue ripetizioni e il suo peso; in quel caso
/// `sets`, `reps` e `weightKg` valgono come la prima serie. La pausa e' sempre unica.
/// Usare `WorkoutParameters.of(_:restSeconds:)` per costruirli da un elenco di serie (tutte uguali -> `perSet` vuoto).
public struct WorkoutParameters: Equatable, Sendable {
    public var sets: Int
    public var reps: Int
    public var restSeconds: Int
    public var weightKg: Double
    public var perSet: [SetTarget]

    public init(sets: Int, reps: Int, restSeconds: Int, weightKg: Double, perSet: [SetTarget] = []) {
        self.sets = sets; self.reps = reps; self.restSeconds = restSeconds; self.weightKg = weightKg; self.perSet = perSet
    }

    /// Parametri da un elenco di serie: se sono tutte uguali diventano serie uguali (senza `perSet`).
    public static func of(_ targets: [SetTarget], restSeconds: Int) -> WorkoutParameters {
        let list = targets.isEmpty ? [SetTarget(reps: WorkoutItem.defaultParameters.reps, weightKg: 0)] : targets
        let first = list[0]
        let varied = list.contains { $0.reps != first.reps || abs($0.weightKg - first.weightKg) > 1e-9 }
        return WorkoutParameters(sets: list.count, reps: first.reps, restSeconds: restSeconds, weightKg: first.weightKg,
                                 perSet: varied ? list : [])
    }

    /// Vero se le serie hanno ripetizioni o pesi diversi.
    public var isVaried: Bool { !perSet.isEmpty }

    /// Obiettivo di ogni serie (serie uguali: `sets` copie di ripetizioni e peso).
    public var targets: [SetTarget] {
        perSet.isEmpty ? Array(repeating: SetTarget(reps: reps, weightKg: weightKg), count: Swift.max(sets, 1)) : perSet
    }

    /// Peso piu' alto tra le serie (per il motore adattivo e lo storico).
    public var maxWeightKg: Double { targets.map(\.weightKg).max() ?? weightKg }

    /// Tutte le serie uguali alla prima (piano Free o ritorno alle serie uguali).
    public func uniform() -> WorkoutParameters {
        WorkoutParameters(sets: sets, reps: reps, restSeconds: restSeconds, weightKg: weightKg)
    }

    /// Limiti usati dalla schermata di impostazione (uguali su Android).
    public static let setsRange = 1...10
    public static let repsRange = 1...50
    public static let restRange = 15...600
    public static let weightRange = 0.0...WeightSteps.max
    /// Passo dei consigli automatici sul peso (motore a regole e adattivo).
    public static let weightStep = 1.25
    /// Arrotondamento del peso salvato.
    public static let weightRounding = 0.25

    /// Riporta i valori nei limiti e arrotonda il peso a 0,25 kg: così restano validi sia i pesi dei pulsanti +/-
    /// (passi di 0,5 / 1 / 5 kg, vedi `WeightSteps`) sia quelli dei consigli (passi di 1,25 kg).
    /// Serie diverse: ogni serie nei limiti, al massimo `setsRange.upperBound` serie.
    public func clamped() -> WorkoutParameters {
        func c(_ v: Int, _ r: ClosedRange<Int>) -> Int { min(max(v, r.lowerBound), r.upperBound) }
        func kg(_ v: Double) -> Double {
            let w = min(max(v, Self.weightRange.lowerBound), Self.weightRange.upperBound)
            return (w / Self.weightRounding).rounded() * Self.weightRounding
        }
        if isVaried {
            return .of(perSet.prefix(Self.setsRange.upperBound).map { SetTarget(reps: c($0.reps, Self.repsRange), weightKg: kg($0.weightKg)) },
                       restSeconds: c(restSeconds, Self.restRange))
        }
        return WorkoutParameters(sets: c(sets, Self.setsRange), reps: c(reps, Self.repsRange),
                                 restSeconds: c(restSeconds, Self.restRange), weightKg: kg(weightKg))
    }
}

/// Pulsanti +/- del peso: 0,5 kg alla volta fino a 4 kg, poi 1 kg alla volta fino a 10 kg, poi 5 kg alla volta.
/// Un peso fuori griglia (es. 12,5 kg letto da una scheda) va al valore di griglia successivo (+) o precedente (-).
/// Stesse regole nell'app Android (WeightSteps in Training.kt).
public enum WeightSteps {
    public static let max = 500.0
    private static let eps = 1e-6

    /// Passo usato salendo da `w`.
    public static func stepUp(_ w: Double) -> Double {
        if w < 4 - eps { return 0.5 }
        if w < 10 - eps { return 1 }
        return 5
    }

    /// Passo usato scendendo da `w`.
    public static func stepDown(_ w: Double) -> Double {
        if w <= 4 + eps { return 0.5 }
        if w <= 10 + eps { return 1 }
        return 5
    }

    /// Peso dopo un tocco su +.
    public static func up(_ w: Double) -> Double {
        let v = Swift.max(0, w)
        let step = stepUp(v)
        return Swift.min(((v / step + eps).rounded(.down) + 1) * step, max)
    }

    /// Peso dopo un tocco su - (0 = corpo libero).
    public static func down(_ w: Double) -> Double {
        let v = Swift.min(max, w)
        if v <= eps { return 0 }
        let step = stepDown(v)
        return Swift.max(((v / step - eps).rounded(.up) - 1) * step, 0)
    }
}

/// Peso scritto a mano: si accettano solo cifre e un separatore decimale (virgola o punto),
/// al massimo 3 cifre intere e 2 decimali. Stesse regole nell'app Android (WeightInput in Training.kt).
public enum WeightInput {
    /// Toglie dal testo tutto quello che non e' ammesso.
    public static func sanitize(_ text: String) -> String {
        var out = ""
        var separator = false
        var intDigits = 0
        var decimals = 0
        for c in text {
            if c.isASCII, c.isNumber {
                if !separator && intDigits < 3 { out.append(c); intDigits += 1 }
                else if separator && decimals < 2 { out.append(c); decimals += 1 }
            } else if (c == "," || c == ".") && !separator {
                separator = true
                out.append(c)
            }
        }
        return out
    }

    /// Valore del testo (nil se vuoto o non valido). "62,5", "62.5", ",5" e "62," sono validi.
    public static func parse(_ text: String) -> Double? {
        var clean = sanitize(text).replacingOccurrences(of: ",", with: ".")
        if clean.isEmpty || clean == "." { return nil }
        if clean.hasSuffix(".") { clean.removeLast() }
        if clean.hasPrefix(".") { clean = "0" + clean }
        return Double(clean)
    }

    /// Testo del valore con il separatore indicato: 62 -> "62", 62.5 -> "62,5", 1.25 -> "1,25".
    public static func format(_ value: Double, separator: Character) -> String {
        let cents = Int((Swift.max(0, value) * 100).rounded())
        let whole = cents / 100
        let rest = cents % 100
        if rest == 0 { return "\(whole)" }
        if rest % 10 == 0 { return "\(whole)\(separator)\(rest / 10)" }
        return "\(whole)\(separator)" + (rest < 10 ? "0\(rest)" : "\(rest)")
    }
}

extension CoachingResult {
    /// Applica i consigli a regole fisse (piano Mid) ai parametri attuali.
    /// Serie diverse: la stessa variazione su ogni serie, mantenendo lo schema (es. +2,5 kg a ogni serie;
    /// una serie in piu' = copia dell'ultima; una in meno = si toglie l'ultima).
    public func applied(to current: WorkoutParameters) -> WorkoutParameters {
        if current.isVaried { return appliedPerSet(current) }
        var p = current
        for item in advice {
            switch item {
            case .increaseWeight(let kg):
                // Corpo libero (peso 0): invece di aggiungere carico si aggiunge una ripetizione, come nel motore adattivo.
                if p.weightKg > 0 { p.weightKg += kg } else { p.reps += 1 }
            case .decreaseWeight(let percent):
                let step = WorkoutParameters.weightStep
                p.weightKg = ((p.weightKg * (1 - Double(percent) / 100)) / step).rounded(.down) * step
            case .addSet: p.sets += 1
            case .removeSet: p.sets -= 1
            case .keepAsIs: break
            }
        }
        p.restSeconds = restSeconds
        return p.clamped()
    }

    private func appliedPerSet(_ current: WorkoutParameters) -> WorkoutParameters {
        var t = current.targets
        let step = WorkoutParameters.weightStep
        for item in advice {
            switch item {
            case .increaseWeight(let kg):
                t = t.map { $0.weightKg > 0 ? SetTarget(reps: $0.reps, weightKg: $0.weightKg + kg) : SetTarget(reps: $0.reps + 1, weightKg: 0) }
            case .decreaseWeight(let percent):
                t = t.map { SetTarget(reps: $0.reps, weightKg: (($0.weightKg * (1 - Double(percent) / 100)) / step).rounded(.down) * step) }
            case .addSet: if let last = t.last { t.append(last) }
            case .removeSet: if t.count > 1 { t.removeLast() }
            case .keepAsIs: break
            }
        }
        return WorkoutParameters.of(t, restSeconds: restSeconds).clamped()
    }
}

extension AdaptiveAdvice {
    /// Parametri proposti dal motore adattivo (piano Full). Se il consiglio non ha un peso (nessun dato) si tiene quello attuale.
    public func parameters(keepingWeight current: Double) -> WorkoutParameters {
        WorkoutParameters(sets: sets, reps: reps, restSeconds: restSeconds,
                          weightKg: weightKg > 0 ? weightKg : current).clamped()
    }

    /// Parametri proposti partendo da quelli attuali. Serie uguali: come `parameters(keepingWeight:)`. Serie diverse:
    /// si applica a ogni serie la stessa variazione decisa dal motore (motivi in `reasonKeys`), mantenendo lo schema.
    public func parameters(from current: WorkoutParameters, weightStep: Double = WorkoutParameters.weightStep) -> WorkoutParameters {
        guard current.isVaried else { return parameters(keepingWeight: current.weightKg) }
        var t = current.targets
        for key in reasonKeys {
            switch key {
            case "coach.deload":
                t = t.map { SetTarget(reps: $0.reps, weightKg: AdaptiveCoach.lowered($0.weightKg, factor: 0.9, step: weightStep)) }
            case "coach.reduce":
                t = t.map { SetTarget(reps: $0.reps, weightKg: AdaptiveCoach.lowered($0.weightKg, factor: 0.92, step: weightStep)) }
                if sets < t.count && t.count > 1 { t.removeLast() }
            case "coach.progress":
                t = t.map { $0.weightKg > 0
                    ? SetTarget(reps: $0.reps, weightKg: $0.weightKg + AdaptiveCoach.increment($0.weightKg, step: weightStep))
                    : SetTarget(reps: $0.reps + 1, weightKg: 0) }
            case "coach.morereps":
                t = t.map { SetTarget(reps: $0.reps + 1, weightKg: $0.weightKg) }
            case "coach.addset":
                if let last = t.last { t.append(last) }
            default: break
            }
        }
        return WorkoutParameters.of(t, restSeconds: restSeconds).clamped()
    }
}
