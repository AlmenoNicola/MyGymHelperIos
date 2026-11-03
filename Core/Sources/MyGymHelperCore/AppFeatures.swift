import Foundation

/// Interruttori delle funzioni dell'app, uguali su iOS e Android (AppFeatures.kt).
/// Servono a spegnere una funzione intera senza cancellarne il codice.
public enum AppFeatures {
    /// Scheda Nutrizione (BMI, fabbisogno calorico, ricerca alimenti, scheda del nutrizionista).
    /// Disattivata per ora: verra' proposta in seguito come nuova opzione. Rimettere `true` per riattivarla:
    /// tornano la scheda, i suoi passi del tutorial e le righe del confronto tra i piani.
    public static let nutritionEnabled = false

    /// Importazione delle schede da file (pulsante "File": PDF, Excel, Word, CSV, testo) nella card "Importa".
    /// Disattivata per ora (novembre 2026): restano la foto della scheda e l'inserimento a mano. Rimettere `true`
    /// per riattivarla (tornano il pulsante e i testi su formati e privacy che citano i file).
    public static let planFileImportEnabled = false

    /// Caricamento della scheda da foto (pulsante "Foto" con lettura del testo e AI del telefono) nella card "Importa".
    /// Disattivato per ora (novembre 2026): resta solo l'inserimento a mano. Rimettere `true` per riattivarlo
    /// (tornano il pulsante, l'interruttore dell'AI, i testi su formati e privacy, il sottotitolo e il testo del tutorial).
    public static let planPhotoImportEnabled = false

    /// Vero se e' attivo almeno un modo per caricare una scheda (file o foto).
    public static var planImportEnabled: Bool { planFileImportEnabled || planPhotoImportEnabled }
}
