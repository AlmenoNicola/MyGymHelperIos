import SwiftUI
import MyGymHelperCore

/// Scala dei testi di tutta l'app (uguale ad APP_TEXT_SCALE su Android): -20% rispetto agli stili di sistema.
/// Restano della dimensione di prima solo i numeri grandi (contatore e timer della sessione, conteggio di prova
/// della calibrazione, BMI) e la nota delle foto, già ridotta.
let AppTextScale: CGFloat = 0.8

extension Font.TextStyle {
    /// Dimensione dello stile con la dimensione del carattere predefinita del telefono (Dynamic Type "Grande").
    var appBaseSize: CGFloat {
        switch self {
        case .largeTitle: return 34
        case .title: return 28
        case .title2: return 22
        case .title3: return 20
        case .headline: return 17
        case .body: return 17
        case .callout: return 16
        case .subheadline: return 15
        case .footnote: return 13
        case .caption: return 12
        case .caption2: return 11
        @unknown default: return 17
        }
    }

    /// Peso predefinito dello stile (il titolo di sezione "headline" è semibold, come quello di sistema).
    var appDefaultWeight: Font.Weight { self == .headline ? .semibold : .regular }
}

/// Carattere dell'app: stile di sistema ridotto di AppTextScale. Con @ScaledMetric segue la dimensione del carattere
/// scelta nel telefono (Dynamic Type), anche se cambia mentre l'app è aperta.
private struct AppFontModifier: ViewModifier {
    @ScaledMetric private var size: CGFloat
    let style: Font.TextStyle
    let weight: Font.Weight?
    let design: Font.Design?
    let monospacedDigit: Bool
    let monospaced: Bool

    init(style: Font.TextStyle, weight: Font.Weight?, design: Font.Design?, monospacedDigit: Bool, monospaced: Bool) {
        self.style = style; self.weight = weight; self.design = design
        self.monospacedDigit = monospacedDigit; self.monospaced = monospaced
        _size = ScaledMetric(wrappedValue: style.appBaseSize * AppTextScale, relativeTo: style)
    }

    func body(content: Content) -> some View {
        var font = Font.system(size: size, weight: weight ?? style.appDefaultWeight, design: design ?? .default)
        if monospacedDigit { font = font.monospacedDigit() }
        if monospaced { font = font.monospaced() }
        return content.font(font)
    }
}

extension View {
    /// Al posto di `.font(.caption)` / `.font(.subheadline.bold())`: stesso stile e peso, testo più piccolo del 20%
    /// (AppTextScale) e sempre legato al Dynamic Type.
    func appFont(_ style: Font.TextStyle, weight: Font.Weight? = nil, design: Font.Design? = nil,
                 monospacedDigit: Bool = false, monospaced: Bool = false) -> some View {
        modifier(AppFontModifier(style: style, weight: weight, design: design,
                                 monospacedDigit: monospacedDigit, monospaced: monospaced))
    }
}

/// Tema grafico scelto nelle Impostazioni, salvato in UserDefaults con la stessa chiave di Android.
/// E' osservabile: cambiando tema tutte le schermate si ridisegnano subito.
@Observable
final class ThemeStore {
    static let shared = ThemeStore()

    var appearance: AppAppearance {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: AppAppearance.key) }
    }

    private init() { appearance = AppAppearance.fromRaw(UserDefaults.standard.string(forKey: AppAppearance.key)) }

    /// Rilegge la scelta (dopo "Elimina tutti i dati" torna il tema predefinito).
    func reload() { appearance = AppAppearance.fromRaw(UserDefaults.standard.string(forKey: AppAppearance.key)) }

    /// Schema colori da imporre all'app: nil = come il telefono (tema neutro), altrimenti sempre scuro.
    var preferredScheme: ColorScheme? { appearance == .system ? nil : .dark }

    var isOriginal: Bool { appearance == .original }
}

/// Colori dell'app. Tre temi (vedi `AppAppearance` nel Core, stessi valori su Android):
/// - neutro (predefinito): colori di sistema di iOS, chiaro o scuro come il telefono;
/// - originale: scuro, gradiente profondo, accento arancio acceso e vetro (Liquid Glass, iOS 26);
/// - scuro: colori di sistema, sempre in modalita' scura.
/// I colori neutri sono quelli "dinamici" di iOS: si adattano da soli alla modalita' chiara o scura.
enum Theme {
    private static var original: Bool { ThemeStore.shared.isOriginal }

    // Tema originale
    private static let orange = Color(red: 1.00, green: 0.42, blue: 0.16)
    private static let orangeSoft = Color(red: 1.00, green: 0.66, blue: 0.20)

    static var accent: Color { original ? orange : .blue }
    static var accentSoft: Color { original ? orangeSoft : .blue }
    /// Testo e icone sopra l'accento (pulsanti, cerchi in gradiente): bianco in tutti i temi.
    static let onAccent = Color.white
    static var bgTop: Color { original ? Color(red: 0.06, green: 0.07, blue: 0.14) : Color(.systemGroupedBackground) }
    static var bgBottom: Color { original ? Color(red: 0.16, green: 0.08, blue: 0.24) : Color(.systemGroupedBackground) }
    /// Fondo delle schede nei temi neutri (nel tema originale le schede sono di vetro).
    static let card = Color(.secondarySystemGroupedBackground)
    /// Esercizio gia' svolto nell'elenco.
    static let done = Color.green
    /// Esercizio che allena tutti i muscoli scelti: ambra, visibile ma non invadente (piu' scuro sul tema chiaro).
    static var highlight: Color {
        original ? Color(red: 1.00, green: 0.76, blue: 0.30)
                 : Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.99, green: 0.84, blue: 0.39, alpha: 1)
                                                                  : UIColor(red: 0.69, green: 0.38, blue: 0.00, alpha: 1) })
    }
    static var accentGradient: LinearGradient {
        LinearGradient(colors: [accentSoft, accent], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    /// Fondo del fumetto del tutorial.
    static var bubble: Color { original ? Color(red: 0.13, green: 0.11, blue: 0.20).opacity(0.95) : Color(.secondarySystemBackground) }
    /// Velo scuro del tutorial attorno all'elemento illuminato (piu' leggero sul tema chiaro).
    static var scrim: Color {
        original ? Color(red: 0.04, green: 0.03, blue: 0.08).opacity(0.88)
                 : Color(UIColor { UIColor(white: 0, alpha: $0.userInterfaceStyle == .dark ? 0.75 : 0.55) })
    }
    /// Corpo della figura anatomica (tre tonalita' dall'alto in basso).
    static var bodyColors: [Color] {
        if original {
            return [Color(red: 0.23, green: 0.20, blue: 0.34), Color(red: 0.16, green: 0.14, blue: 0.25), Color(red: 0.14, green: 0.12, blue: 0.22)]
        }
        func dyn(_ dark: CGFloat, _ light: CGFloat) -> Color {
            Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: dark, alpha: 1) : UIColor(white: light, alpha: 1) })
        }
        return [dyn(0.30, 0.84), dyn(0.25, 0.80), dyn(0.21, 0.77)]
    }
}

/// Sfondo comune: gradiente e due aloni sfocati (tema originale) oppure il fondo di sistema (temi neutri).
struct AppBackground: View {
    var body: some View {
        ZStack {
            if ThemeStore.shared.isOriginal {
                LinearGradient(colors: [Theme.bgTop, Theme.bgBottom], startPoint: .top, endPoint: .bottom)
                Circle().fill(Theme.accent.opacity(0.28)).frame(width: 320).blur(radius: 90).offset(x: 140, y: -260)
                Circle().fill(Color.purple.opacity(0.30)).frame(width: 300).blur(radius: 100).offset(x: -150, y: 300)
            } else {
                Theme.bgTop
            }
        }
        .ignoresSafeArea()
    }
}

/// Scheda dell'app: vetro nel tema originale, fondo pieno di sistema (come Impostazioni) nei temi neutri.
/// `tint` colora leggermente la scheda (verde = svolto, ambra = in evidenza).
private struct CardModifier: ViewModifier {
    let padding: CGFloat
    var tint: Color? = nil

    @ViewBuilder
    func body(content: Content) -> some View {
        if ThemeStore.shared.isOriginal {
            content.padding(padding)
                .glassEffect(tint.map { Glass.regular.tint($0.opacity(0.35)) } ?? Glass.regular, in: .rect(cornerRadius: 28))
        } else {
            content.padding(padding)
                .background {
                    RoundedRectangle(cornerRadius: 28).fill(Theme.card)
                        .overlay { RoundedRectangle(cornerRadius: 28).fill((tint ?? .clear).opacity(0.16)) }
                }
        }
    }
}

extension View {
    /// Scheda con angoli morbidi (vetro nel tema originale).
    func glassCard(padding: CGFloat = 20) -> some View {
        modifier(CardModifier(padding: padding))
    }

    /// Scheda con una tinta (verde = svolto, ambra = in evidenza); nil = scheda normale.
    func themedCard(tint: Color?, padding: CGFloat) -> some View {
        modifier(CardModifier(padding: padding, tint: tint))
    }

    /// Sfondo comune di tutte le schermate.
    func appScreen() -> some View {
        self.scrollContentBackground(.hidden)
            .background { AppBackground() }
    }
}

/// Titolo grande di schermata, con icona su cerchio in gradiente.
struct ScreenHeader: View {
    let symbol: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 28 * AppTextScale, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 60, height: 60)
                .background(Theme.accentGradient, in: Circle())
                .shadow(color: Theme.accent.opacity(0.5), radius: 14, y: 6)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).appFont(.title, weight: .bold).lineLimit(1)     // rimpicciolisce invece di andare a capo
                Text(subtitle).appFont(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

/// Riga con titolo e contatore con tasti meno/più.
struct CounterRow: View {
    let title: LocalizedStringKey
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step = 1

    var body: some View {
        HStack {
            Text(title).appFont(.headline)
            Spacer()
            HStack(spacing: 14) {
                Button { value = max(range.lowerBound, value - step) } label: { Image(systemName: "minus") }
                    .buttonStyle(.glass).buttonBorderShape(.circle)
                Text("\(value)")
                    .appFont(.title2, weight: .bold, monospacedDigit: true)
                    .frame(minWidth: 56)
                    .contentTransition(.numericText())
                Button { value = min(range.upperBound, value + step) } label: { Image(systemName: "plus") }
                    .buttonStyle(.glass).buttonBorderShape(.circle)
            }
        }
        .sensoryFeedback(.selection, trigger: value)
        .animation(.snappy, value: value)
    }
}

/// Anello di avanzamento per il conteggio delle ripetizioni.
struct RepRing: View {
    let count: Int
    let target: Int

    private var progress: Double { target > 0 ? min(Double(count) / Double(target), 1) : 0 }

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.10), lineWidth: 22)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Theme.accentGradient, style: StrokeStyle(lineWidth: 22, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: Theme.accent.opacity(0.6), radius: 16)
                .animation(.spring(duration: 0.5), value: progress)
            VStack(spacing: 2) {
                Text("\(count)")
                    .font(.system(size: 88, weight: .heavy, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
                    .animation(.snappy, value: count)
                Text("/ \(target)").appFont(.title3, weight: .semibold).foregroundStyle(.secondary)
            }
        }
        .frame(width: 270, height: 270)
        .sensoryFeedback(.impact, trigger: count)
    }
}

/// Riga del peso di un esercizio: il numero si scrive a mano (tastierino numerico, solo cifre e virgola) oppure si
/// cambia con +/-: passi di 0,5 kg fino a 4 kg, 1 kg fino a 10 kg, poi 5 kg (`WeightSteps` nel Core).
/// Campo vuoto o 0 = corpo libero.
struct WeightRow: View {
    let title: LocalizedStringKey
    @Binding var value: Double

    var body: some View {
        KgInputRow(title: title, value: $value, range: 0...WeightSteps.max, placeholder: "setup.bodyweight",
                   minus: WeightSteps.down, plus: WeightSteps.up)
    }
}

/// Riga con un peso in kg scritto a mano (solo numeri, fino a 2 decimali) e i pulsanti +/-.
/// Il valore viene salvato solo se e' nei limiti; fuori dai limiti il campo diventa rosso e, quando si esce dal campo,
/// torna l'ultimo valore valido. Con `placeholder` il campo vuoto vale 0. Stesso comportamento dell'app Android.
struct KgInputRow: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>
    var placeholder: LocalizedStringKey? = nil
    let minus: (Double) -> Double
    let plus: (Double) -> Double

    @State private var text = ""
    @FocusState private var focused: Bool

    private var separator: Character { Locale.current.decimalSeparator?.first ?? "," }
    private var lowest: Double { placeholder != nil ? 0 : range.lowerBound }

    private func show(_ v: Double) -> String { v <= 0 && placeholder != nil ? "" : WeightInput.format(v, separator: separator) }

    private var invalid: Bool {
        guard !text.isEmpty else { return false }
        guard let v = WeightInput.parse(text) else { return true }
        return !range.contains(v)
    }

    var body: some View {
        HStack {
            Text(title).appFont(.headline)
            Spacer()
            HStack(spacing: 10) {
                Button { value = min(max(minus(value), lowest), range.upperBound) } label: { Image(systemName: "minus") }
                    .buttonStyle(.glass).buttonBorderShape(.circle)
                    .buttonRepeatBehavior(.enabled)
                HStack(spacing: 3) {
                    TextField("", text: $text, prompt: placeholder.map { Text($0) })
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .appFont(.title3, weight: .bold, monospacedDigit: true)
                        .minimumScaleFactor(0.6)
                        .focused($focused)
                    Text(verbatim: "kg").appFont(.footnote).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8).padding(.vertical, 6)
                .frame(width: 104)
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .stroke(invalid ? Color.red : Color.primary.opacity(focused ? 0.6 : 0.25), lineWidth: 1))
                Button { value = min(max(plus(value), lowest), range.upperBound) } label: { Image(systemName: "plus") }
                    .buttonStyle(.glass).buttonBorderShape(.circle)
                    .buttonRepeatBehavior(.enabled)
            }
        }
        .onAppear { text = show(value) }
        .onChange(of: text) { _, new in
            let clean = WeightInput.sanitize(new)
            if clean != new { text = clean; return }         // solo cifre e un separatore
            if clean.isEmpty, placeholder != nil { value = 0 }
            else if let v = WeightInput.parse(clean), range.contains(v) { value = v }
        }
        .onChange(of: value) { _, new in
            // Valore cambiato da fuori (pulsanti +/-, Apple Salute): si aggiorna il testo se non corrisponde gia'.
            if WeightInput.parse(text) != new && !(new <= 0 && text.isEmpty) { text = show(new) }
        }
        .onChange(of: focused) { _, isFocused in if !isFocused { text = show(value) } }
        .toolbar {
            // Il tastierino numerico non ha il tasto Invio: "Fine" chiude la tastiera (solo per il campo attivo).
            ToolbarItemGroup(placement: .keyboard) {
                if focused {
                    Spacer()
                    Button("common.done") { focused = false }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: value)
    }
}
