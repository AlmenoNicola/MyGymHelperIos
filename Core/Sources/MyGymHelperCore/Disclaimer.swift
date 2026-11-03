import Foundation

/// Chiavi di localizzazione del disclaimer. Il testo va tradotto nello String Catalog
/// e mostrato: alla prima installazione, nella sezione Informazioni e nella descrizione dell'app su App Store.
public enum Disclaimer {
    public static let titleKey = "disclaimer.title"
    public static let bodyKey = "disclaimer.body"
    public static let acceptedDefaultsKey = "disclaimer.accepted.v1"

    /// Testo di riferimento in italiano (la traduzione e' nello String Catalog).
    public static let referenceTextIT =
        "Questa app fornisce indicazioni generali e non sostituisce un nutrizionista, un personal trainer o un medico. Consulta sempre un professionista prima di cambiare allenamento o alimentazione."
}
