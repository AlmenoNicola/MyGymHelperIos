import Foundation

/// Tema grafico scelto nell'Area personale. Equivalente di Appearance.kt: stessi valori salvati.
///
/// - `system`: colori neutri del telefono (colori di sistema su iOS, Material You su Android 12+) e modalita'
///   chiara/scura come il telefono. E' il tema predefinito.
/// - `original`: lo stile scuro con gradiente blu-viola e accento arancio (quello usato fino a ottobre 2026).
/// - `dark`: colori neutri del telefono, sempre in modalita' scura.
public enum AppAppearance: String, CaseIterable, Sendable {
    case system, original, dark

    /// Chiave delle impostazioni (stessa su Android).
    public static let key = "appearance.theme"
    public static let defaultValue: AppAppearance = .system

    /// Chiave del testo da mostrare nella scelta ("appearance.system" ...).
    public var titleKey: String { "appearance.\(rawValue)" }

    /// Valore salvato -> tema; valori sconosciuti o assenti = tema predefinito.
    public static func fromRaw(_ raw: String?) -> AppAppearance {
        raw.flatMap(AppAppearance.init(rawValue:)) ?? defaultValue
    }

    /// Se il tema e' scuro, dato se il telefono e' in modalita' scura.
    public func isDark(systemDark: Bool) -> Bool {
        switch self {
        case .system: return systemDark
        case .original, .dark: return true
        }
    }
}
