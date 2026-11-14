import Foundation

/// Asse del movimento di ogni esercizio (novembre 2026), uguale su Android (Movement.kt).
///
/// Il catalogo non lo indica: si ricava dall'id (che contiene il nome inglese, es. "fedb-Seated_Cable_Rows") con
/// regole fisse. Sinistra/destra = movimento nel piano orizzontale o rotazione attorno alla verticale (twist,
/// woodchop, rematori ai cavi da seduti, chest press e croci alla macchina, adductor/abductor da seduti, salti
/// laterali); avanti/indietro = oscillazioni e trascinamenti in orizzontale (swing, pull through, slitta, bear crawl,
/// mountain climber, skier: 9 novembre 2026); tutto il resto e' su/giu'. Un esercizio del catalogo puo' avere il valore scritto ("movement" nel file
/// degli esercizi), che vince sulle regole; l'utente puo' cambiarlo per la riga dell'elenco (`WorkoutItem.movement`)
/// e durante il conteggio (solo per quella sessione).
public enum MovementRules {
    /// Parole che indicano sinistra/destra (sull'id in minuscolo, con spazi al posto di "_" e "-").
    static let leftRight = [
        "twist", "wood chop", "woodchop", "landmine 180", "torso rotation", "internal rotation", "external rotation",
        "pallof", "halo", "wipers", "carioca", "butterfly", "pec deck", "reverse machine fly", "cable rear delt fly",
        "back flyes with bands", "crossover", "chest press", "seated cable row", "seated one arm cable pulley row",
        "elevated cable row", "leverage iso row", "rowing stationary", "rope rear delt row", "shotgun row", "sled row",
        "low pulley row", "face pull", "thigh abductor", "thigh adductor"
    ]

    /// Eccezioni: contengono una parola qui sopra ma il movimento e' su/giu'.
    static let upDown = [
        "with a twist", "low cable crossover", "stride jump crossover", "reverse flyes with external rotation",
        "wrist rotation", "supine chest", "crossover reverse lunge"
    ]

    /// Parole che indicano avanti/indietro (controllate dopo le liste qui sopra, prima dei salti laterali).
    static let forwardBack = ["swing", "pull through", "sled push", "sled drag", "bear crawl", "mountain climber", "skier"]

    /// Pliometria che si sposta di lato (salti e passi laterali).
    static let lateralJumps = ["lateral", "side", "shuffle", "skater", "carioca"]

    static func text(_ id: String) -> String {
        let afterPrefix = id.firstIndex(of: "-").map { String(id[id.index(after: $0)...]) } ?? id
        let words = afterPrefix.lowercased().replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
        return " " + words.joined(separator: " ") + " "
    }

    /// Asse del movimento dell'esercizio del catalogo.
    public static func of(_ exercise: CatalogExercise) -> MovementAxis {
        if let m = exercise.movement { return m }
        let t = text(exercise.id)
        if upDown.contains(where: { t.contains($0) }) { return .upDown }
        if leftRight.contains(where: { t.contains($0) }) { return .leftRight }
        if forwardBack.contains(where: { t.contains($0) }) { return .forwardBack }
        if exercise.kind == .plyometrics && lateralJumps.contains(where: { t.contains(" " + $0) }) { return .leftRight }
        return .upDown
    }

    /// Asse da usare per la riga dell'elenco: quello scelto dall'utente per la riga (se e' ancora lo stesso esercizio),
    /// altrimenti quello del catalogo. Senza esercizio (conteggio libero): su/giu'.
    public static func forItem(_ exercise: CatalogExercise?, _ item: WorkoutItem?) -> MovementAxis {
        guard let exercise else { return .upDown }
        if let item, item.exerciseID == exercise.id, let chosen = item.movement { return chosen }
        return of(exercise)
    }

    /// Valore da salvare sulla riga: nil se la scelta e' quella del catalogo (cosi' segue eventuali correzioni).
    public static func override(_ exercise: CatalogExercise, _ chosen: MovementAxis) -> MovementAxis? {
        chosen == of(exercise) ? nil : chosen
    }
}
