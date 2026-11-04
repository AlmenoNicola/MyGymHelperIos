import Foundation

/// Esercizio dentro un elenco di allenamento, con i propri parametri (equivalente di WorkoutItem in Kotlin).
/// `done` = gia' svolto (sfondo verde nell'elenco), si azzera con "Reset".
/// `perSet` = serie diverse (ripetizioni e peso di ogni serie, Pro); vuoto = serie tutte uguali.
public struct WorkoutItem: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var exerciseID: String
    public var sets: Int
    public var reps: Int
    public var restSeconds: Int
    public var weightKg: Double
    public var done: Bool
    public var perSet: [SetTarget]

    /// Parametri di partenza di un esercizio nuovo (poi precompilati da scheda e ultima sessione).
    public static let defaultParameters = WorkoutParameters(sets: 3, reps: 10, restSeconds: 90, weightKg: 0)

    public init(id: UUID = UUID(), exerciseID: String, sets: Int = WorkoutItem.defaultParameters.sets,
                reps: Int = WorkoutItem.defaultParameters.reps, restSeconds: Int = WorkoutItem.defaultParameters.restSeconds,
                weightKg: Double = WorkoutItem.defaultParameters.weightKg, done: Bool = false, perSet: [SetTarget] = []) {
        self.id = id; self.exerciseID = exerciseID; self.sets = sets; self.reps = reps
        self.restSeconds = restSeconds; self.weightKg = weightKg; self.done = done; self.perSet = perSet
    }

    /// Lettura dei dati salvati: gli elenchi salvati prima delle serie diverse non hanno "perSet".
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        exerciseID = try c.decode(String.self, forKey: .exerciseID)
        sets = try c.decode(Int.self, forKey: .sets)
        reps = try c.decode(Int.self, forKey: .reps)
        restSeconds = try c.decode(Int.self, forKey: .restSeconds)
        weightKg = try c.decode(Double.self, forKey: .weightKg)
        done = try c.decode(Bool.self, forKey: .done)
        perSet = try c.decodeIfPresent([SetTarget].self, forKey: .perSet) ?? []
    }

    public var parameters: WorkoutParameters {
        WorkoutParameters(sets: sets, reps: reps, restSeconds: restSeconds, weightKg: weightKg, perSet: perSet)
    }

    public func with(_ p: WorkoutParameters) -> WorkoutItem {
        let c = p.clamped()
        var copy = self
        copy.sets = c.sets; copy.reps = c.reps; copy.restSeconds = c.restSeconds; copy.weightKg = c.weightKg
        copy.perSet = c.perSet
        return copy
    }

    /// Elenco salvato come JSON (SwiftData). Dati illeggibili -> elenco vuoto.
    public static func decodeList(_ data: Data) -> [WorkoutItem] {
        guard !data.isEmpty else { return [] }
        return (try? JSONDecoder().decode([WorkoutItem].self, from: data)) ?? []
    }

    public static func encodeList(_ items: [WorkoutItem]) -> Data {
        (try? JSONEncoder().encode(items)) ?? Data()
    }
}

/// Logica degli elenchi di allenamento e della scelta degli esercizi (uguale su Android: WorkoutListLogic.kt).
public enum WorkoutListLogic {
    /// Prossimo esercizio da fare: il primo non svolto dopo `afterItemID` (nell'ordine dell'elenco);
    /// se non ce ne sono dopo, il primo non svolto dall'inizio. nil se sono tutti svolti.
    public static func nextPending(_ items: [WorkoutItem], after afterItemID: UUID? = nil) -> WorkoutItem? {
        let start = afterItemID.flatMap { id in items.firstIndex { $0.id == id } } ?? -1
        if let next = items.dropFirst(start + 1).first(where: { !$0.done }) { return next }
        return items.first { !$0.done && $0.id != afterItemID }
    }

    /// Muscoli (principali e secondari) dell'esercizio.
    public static func muscles(_ exercise: CatalogExercise) -> Set<MuscleGroup> {
        Set(exercise.primary + exercise.secondary)
    }

    /// Vero se l'esercizio allena TUTTI i muscoli scelti (almeno due: con uno solo ogni risultato lo farebbe).
    public static func coversAll(_ exercise: CatalogExercise, selected: Set<MuscleGroup>) -> Bool {
        selected.count >= 2 && muscles(exercise).isSuperset(of: selected)
    }

    /// Esercizi da proporre: senza muscoli scelti, tutti (in ordine alfabetico); altrimenti quelli che allenano
    /// almeno uno dei muscoli scelti come muscolo principale, o tutti quelli scelti. In cima quelli che li allenano
    /// tutti, poi per numero di muscoli scelti allenati, poi per nome. `query` filtra per nome.
    public static func browse(_ pool: [CatalogExercise], selected: Set<MuscleGroup>, query: String = "") -> [CatalogExercise] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let byName = pool.filter { q.isEmpty || $0.name.localizedCaseInsensitiveContains(q) }
        func name(_ e: CatalogExercise) -> String { e.name.lowercased() }
        if selected.isEmpty { return byName.sorted { name($0) < name($1) } }
        return byName
            .filter { ex in ex.primary.contains(where: selected.contains) || coversAll(ex, selected: selected) }
            .sorted { a, b in
                let fa = coversAll(a, selected: selected), fb = coversAll(b, selected: selected)
                if fa != fb { return fa }
                let ca = muscles(a).intersection(selected).count, cb = muscles(b).intersection(selected).count
                if ca != cb { return ca > cb }
                return name(a) < name(b)
            }
    }

    /// Posizione del telefono proposta per un esercizio (gambe: coscia; il resto: braccio).
    public static func suggestedPosition(_ exercise: CatalogExercise?) -> SensorPosition {
        (exercise?.isLowerBody ?? false) ? .legThigh : .armUpper
    }

    // MARK: - Avviso a voce nella pausa prima dell'ultima serie

    /// Vero nella pausa che precede l'ultima serie (servono almeno due serie: con una sola non c'e' pausa).
    public static func isRestBeforeLastSet(afterSet: Int, totalSets: Int) -> Bool {
        totalSets >= 2 && afterSet == totalSets - 1
    }

    /// Cosa dire nella pausa prima dell'ultima serie. Senza elenco (conteggio libero o esercizio singolo): solo
    /// "la prossima e' l'ultima serie". Con un elenco: il prossimo esercizio da fare, con la posizione del telefono
    /// consigliata; se questo e' l'ultimo esercizio non svolto, la fine degli esercizi della giornata.
    /// `exercise` cerca l'esercizio nel catalogo (se non lo trova si dice solo "ultima serie").
    public static func lastSetNotice(_ items: [WorkoutItem]?, currentItemID: UUID?,
                                     exercise: (String) -> CatalogExercise?) -> LastSetNotice {
        guard let items, let currentItemID, items.contains(where: { $0.id == currentItemID }) else { return .lastSetOnly }
        guard let next = nextPending(items, after: currentItemID), next.id != currentItemID else { return .endOfDay }
        guard let ex = exercise(next.exerciseID) else { return .lastSetOnly }
        return .nextExercise(ex, position: suggestedPosition(ex))
    }

    // MARK: - Esercizio alternativo (solo per la sessione in corso)

    /// Muscoli già scelti quando si apre la scelta dell'alternativa: i muscoli principali dell'esercizio originale.
    public static func alternativeMuscles(_ original: CatalogExercise) -> Set<MuscleGroup> {
        Set(original.primary)
    }

    /// Muscoli che si vedono sul retro della mappa del corpo.
    private static let backSide: Set<MuscleGroup> = [.traps, .lats, .lowerBack, .triceps, .glutes, .hamstrings, .calves]

    /// Vero se la mappa va aperta sul retro: tutti i muscoli principali dell'esercizio originale stanno dietro.
    public static func alternativeOnBack(_ original: CatalogExercise) -> Bool {
        !original.primary.isEmpty && original.primary.allSatisfy(backSide.contains)
    }

    /// Esercizi proposti come alternativa: come `browse`, senza l'esercizio che non si può fare.
    public static func alternatives(_ pool: [CatalogExercise], original: CatalogExercise, selected: Set<MuscleGroup>,
                                    query: String = "") -> [CatalogExercise] {
        browse(pool.filter { $0.id != original.id }, selected: selected, query: query)
    }

    /// Parametri dell'alternativa: stesse serie, ripetizioni e pausa dell'esercizio dell'elenco; se l'alternativa è
    /// a corpo libero il peso si toglie (quello dell'esercizio originale non avrebbe senso). L'elenco non cambia.
    public static func alternativeParameters(_ parameters: WorkoutParameters, alternative: CatalogExercise) -> WorkoutParameters {
        guard CatalogFilter.isBodyweight(alternative) else { return parameters }
        return .of(parameters.targets.map { SetTarget(reps: $0.reps, weightKg: 0) }, restSeconds: parameters.restSeconds)
    }

    /// "Sostituisci nell'elenco": l'alternativa diventa definitiva. La riga resta la stessa (stesso id e stato
    /// "svolto") ma con il nuovo esercizio e i suoi parametri.
    public static func replaceExercise(_ item: WorkoutItem, exerciseID: String, parameters: WorkoutParameters) -> WorkoutItem {
        var copy = item.with(parameters)
        copy.exerciseID = exerciseID
        return copy
    }
}

/// Avviso a voce nella pausa prima dell'ultima serie (uguale su Android: LastSetNotice in WorkoutLists.kt).
public enum LastSetNotice: Equatable, Sendable {
    /// Solo "la prossima sara' l'ultima serie".
    case lastSetOnly
    /// Ultima serie dell'ultimo esercizio dell'elenco: "hai finito tutti i tuoi esercizi".
    case endOfDay
    /// Ultima serie, poi il prossimo esercizio: nome, muscoli, attrezzo e dove mettere il telefono.
    case nextExercise(CatalogExercise, position: SensorPosition)
}
