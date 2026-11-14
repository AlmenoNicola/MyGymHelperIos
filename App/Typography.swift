import SwiftUI

// Sistema tipografico dell'app (9 novembre 2026), uguale a ui/Type.kt su Android.
// Due famiglie: Inter per testi, pulsanti e moduli; Oswald Tabular (Oswald con le cifre tutte larghe uguali) per
// titoli brevi, numeri e pulsanti principali. I file sono in App/Fonts (licenza SIL OFL 1.1, OFL_*.txt) e sono
// registrati in Support/Info.plist (UIAppFonts).
// Le dimensioni sono nominali: sopra si applica AppTextScale (-20%), tranne timer e display che restano grandi come
// prima (contatore, timer della pausa, numero della calibrazione, BMI). Nessun testo sotto "caption" (13).

/// Famiglie di caratteri dell'app.
enum AppFontFamily {
    case inter, oswald

    /// Nome PostScript del file per il peso richiesto (si usano solo i pesi inclusi nell'app).
    func postScriptName(_ weight: Font.Weight) -> String {
        switch self {
        case .inter:
            switch weight {
            case .bold, .heavy, .black: return "Inter-Bold"
            case .semibold: return "Inter-SemiBold"
            case .medium: return "Inter-Medium"
            default: return "Inter-Regular"
            }
        case .oswald:
            switch weight {
            case .bold, .heavy, .black: return "OswaldTabular-Bold"
            case .semibold: return "OswaldTabular-SemiBold"
            default: return "OswaldTabular-Medium"
            }
        }
    }
}

/// Token tipografici: famiglia, peso e dimensione nominale. Come AppType in ui/Type.kt.
enum AppType {
    /// Inter Medium 13: la dimensione minima dell'app (note, didascalie, etichette piccole).
    case caption
    /// Inter Regular 14: testo secondario.
    case secondary
    /// Inter Regular 15: testo normale.
    case body
    /// Inter Regular 16.
    case bodyLarge
    /// Inter SemiBold 17: titolo di una card o di una riga.
    case cardTitle
    /// Inter SemiBold 17 / 14: pulsanti.
    case button, buttonSmall
    /// Oswald SemiBold 20: titoli di sezione brevi.
    case sectionTitle
    /// Oswald SemiBold 20 / 22: numeri con unità ("80 KG") e valori.
    case metric, stat
    /// Oswald Bold 26.
    case headline
    /// Oswald Bold 28: titolo della schermata (in maiuscolo).
    case screenTitle
    /// Oswald SemiBold 18, maiuscolo e spaziato: pulsanti principali (CTA).
    case cta
    /// Oswald Bold 30 / 64: numeri grandi (avanzamento della calibrazione; numero del test e BMI).
    case number, display
    /// Oswald Bold 88: contatore delle ripetizioni e timer della pausa, senza AppTextScale.
    case timer

    var family: AppFontFamily {
        switch self {
        case .caption, .secondary, .body, .bodyLarge, .cardTitle, .button, .buttonSmall: return .inter
        default: return .oswald
        }
    }

    var weight: Font.Weight {
        switch self {
        case .caption: return .medium
        case .secondary, .body, .bodyLarge: return .regular
        case .cardTitle, .button, .buttonSmall, .sectionTitle, .metric, .stat, .cta: return .semibold
        case .headline, .screenTitle, .number, .display, .timer: return .bold
        }
    }

    /// Dimensione nominale (prima di AppTextScale).
    var size: CGFloat {
        switch self {
        case .caption: return 13
        case .secondary, .buttonSmall: return 14
        case .body: return 15
        case .bodyLarge: return 16
        case .cardTitle, .button: return 17
        case .cta: return 18
        case .sectionTitle, .metric: return 20
        case .stat: return 22
        case .headline: return 26
        case .screenTitle: return 28
        case .number: return 30
        case .display: return 64
        case .timer: return 88
        }
    }

    /// Stile di sistema a cui legare il Dynamic Type.
    var relativeTo: Font.TextStyle {
        switch self {
        case .caption: return .caption
        case .secondary, .buttonSmall: return .subheadline
        case .body, .bodyLarge: return .body
        case .cardTitle, .button: return .headline
        case .cta, .sectionTitle, .metric: return .title3
        case .stat: return .title2
        case .headline, .screenTitle, .number: return .title
        case .display, .timer: return .largeTitle
        }
    }

    /// Timer e display restano grandi come prima (fuori dalla riduzione del 20%) e non seguono il Dynamic Type.
    var isFixed: Bool { self == .timer || self == .display }

    /// Testo in maiuscolo con spaziatura (pulsanti principali).
    var isUppercase: Bool { self == .cta || self == .screenTitle }
    var tracking: CGFloat { self == .cta ? 0.8 : 0 }

    /// Carattere del token, con un peso diverso se richiesto (Inter: Regular/Medium/SemiBold/Bold; Oswald:
    /// Medium/SemiBold/Bold).
    func font(weight override: Font.Weight? = nil) -> Font {
        let name = family.postScriptName(override ?? weight)
        if isFixed { return .custom(name, fixedSize: size) }
        return .custom(name, size: size * AppTextScale, relativeTo: relativeTo)
    }
}

private struct AppTypeModifier: ViewModifier {
    let type: AppType
    let weight: Font.Weight?
    let uppercase: Bool?
    let monospacedDigit: Bool

    private var font: Font {
        let f = type.font(weight: weight)
        // Oswald Tabular ha già le cifre tutte larghe uguali; Inter le ha con la variante tabellare
        return monospacedDigit && type.family == .inter ? f.monospacedDigit() : f
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        // Maiuscolo solo se richiesto: senza, il caso del testo resta quello ereditato
        if uppercase ?? type.isUppercase {
            content.font(font).textCase(.uppercase).tracking(type.tracking)
        } else {
            content.font(font).tracking(type.tracking)
        }
    }
}

extension View {
    /// Carattere dell'app da un token (al posto di `.font(...)` e del vecchio `.appFont(stile)` sui testi).
    /// `weight`: peso diverso da quello del token; `uppercase`: maiuscolo (nil = quello del token).
    func appType(_ type: AppType, weight: Font.Weight? = nil, uppercase: Bool? = nil,
                 monospacedDigit: Bool = false) -> some View {
        modifier(AppTypeModifier(type: type, weight: weight, uppercase: uppercase, monospacedDigit: monospacedDigit))
    }
}

extension String {
    /// Titolo "sportivo": tutto maiuscolo con le regole della lingua del telefono.
    func sportTitle() -> String { uppercased(with: Locale.current) }
}
