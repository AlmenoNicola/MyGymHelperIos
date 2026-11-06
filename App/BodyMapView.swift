import SwiftUI
import MyGymHelperCore

extension MuscleGroup {
    var title: String { Bundle.main.localizedString(forKey: "muscle.\(rawValue)", value: rawValue, table: nil) }
}

extension BodyRegion {
    var title: String { Bundle.main.localizedString(forKey: "region.\(rawValue)", value: rawValue, table: nil) }
    var symbol: String {
        switch self {
        case .arms: return "figure.strengthtraining.traditional"
        case .legs: return "figure.walk"
        case .glutes: return "figure.step.training"
        case .chest: return "heart.fill"
        case .back: return "figure.mind.and.body"
        case .shoulders: return "figure.arms.open"
        case .core: return "circle.hexagongrid.fill"
        }
    }
}

enum BodySide: String, CaseIterable, Identifiable {
    case front, back
    var id: String { rawValue }
    var titleKey: LocalizedStringKey { self == .front ? "map.front" : "map.back" }
}

/// Come evidenziare un muscolo nella figura.
enum MuscleHighlight { case idle, secondary, primary }

/// Tracciati della figura anatomica (dati nel Core, `BodyFigure`), convertiti una volta sola in `Path`.
enum FigurePaths {
    struct Part { let muscle: MuscleGroup?; let path: Path }

    static let silhouette: [Path] = BodyFigure.silhouette.map(path)
    static let front: [Part] = BodyFigure.front.map { Part(muscle: $0.muscle, path: path($0.path)) }
    static let back: [Part] = BodyFigure.back.map { Part(muscle: $0.muscle, path: path($0.path)) }

    static func parts(front isFront: Bool) -> [Part] { isFront ? front : back }

    static func path(_ d: String) -> Path {
        var p = Path()
        for c in BodyFigure.commands(d) ?? [] {
            switch c {
            case let .move(x, y): p.move(to: CGPoint(x: x, y: y))
            case let .curve(x1, y1, x2, y2, x, y):
                p.addCurve(to: CGPoint(x: x, y: y), control1: CGPoint(x: x1, y: y1), control2: CGPoint(x: x2, y: y2))
            case .close: p.closeSubpath()
            }
        }
        return p
    }

    /// Muscolo nel punto indicato (coordinate della figura), il piu' in alto nel disegno.
    static func muscle(at point: CGPoint, front isFront: Bool) -> MuscleGroup? {
        parts(front: isFront).last { $0.muscle != nil && $0.path.contains(point) }?.muscle
    }
}

/// Figura anatomica disegnata da noi (fronte o retro). `highlight` decide il colore di ogni muscolo: principale
/// (gradiente arancio), secondario (arancio tenue) o nessuno. Con `onTap` il tocco su un muscolo lo restituisce.
/// Stesso disegno dell'app Android (MuscleFigure.kt).
struct MuscleFigure: View {
    let front: Bool
    let highlight: (MuscleGroup) -> MuscleHighlight
    var onTap: ((MuscleGroup) -> Void)? = nil

    var body: some View {
        // Colori letti qui (non nel disegno): cambiando tema la figura si ridisegna. Corpo scuro sui temi scuri,
        // grigio chiaro su quello chiaro.
        let bodyGradient = Gradient(colors: Theme.bodyColors)
        let accent = Gradient(colors: [Theme.accentSoft, Theme.accent])
        let secondaryFill = Theme.accent.opacity(0.45)
        GeometryReader { geo in
            let s = geo.size.width / BodyFigure.width
            Canvas { ctx, _ in
                ctx.scaleBy(x: s, y: s)
                let top = CGPoint(x: 100, y: 0), bottom = CGPoint(x: 100, y: BodyFigure.height)
                for p in FigurePaths.silhouette {
                    ctx.fill(p, with: .linearGradient(bodyGradient, startPoint: top, endPoint: bottom))
                }
                for part in FigurePaths.parts(front: front) {
                    switch part.muscle.map(highlight) {
                    case nil: ctx.fill(part.path, with: .color(Color.primary.opacity(0.05)))
                    case .idle?: ctx.fill(part.path, with: .color(Color.primary.opacity(0.13)))
                    case .secondary?: ctx.fill(part.path, with: .color(secondaryFill))
                    case .primary?:
                        let r = part.path.boundingRect
                        ctx.fill(part.path, with: .linearGradient(accent, startPoint: r.origin,
                                                                  endPoint: CGPoint(x: r.maxX, y: r.maxY)))
                    }
                    ctx.stroke(part.path, with: .color(Color.primary.opacity(0.25)), lineWidth: 0.7)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                guard let onTap, s > 0,
                      let m = FigurePaths.muscle(at: CGPoint(x: location.x / s, y: location.y / s), front: front) else { return }
                onTap(m)
            }
            .allowsHitTesting(onTap != nil)     // senza onTap (miniature, schede) il tocco va alla riga o al pulsante sotto
        }
        .aspectRatio(BodyFigure.width / BodyFigure.height, contentMode: .fit)
    }
}

/// Figura dei muscoli della scheda Profilo: ogni muscolo è colorato in base a quanto è stato usato nel periodo
/// (`intensity` da 0 a 1, nil = non usato): più è usato, più il colore è pieno. Il muscolo `selected` ha il bordo
/// marcato. Con `onTap` il tocco su un muscolo lo restituisce. Come MuscleHeatFigure su Android.
struct MuscleHeatFigure: View {
    let front: Bool
    let intensity: (MuscleGroup) -> Double?
    var selected: MuscleGroup? = nil
    var onTap: ((MuscleGroup) -> Void)? = nil

    var body: some View {
        let bodyGradient = Gradient(colors: Theme.bodyColors)
        let accent = Theme.accent
        GeometryReader { geo in
            let s = geo.size.width / BodyFigure.width
            Canvas { ctx, _ in
                ctx.scaleBy(x: s, y: s)
                let top = CGPoint(x: 100, y: 0), bottom = CGPoint(x: 100, y: BodyFigure.height)
                for p in FigurePaths.silhouette {
                    ctx.fill(p, with: .linearGradient(bodyGradient, startPoint: top, endPoint: bottom))
                }
                for part in FigurePaths.parts(front: front) {
                    let m = part.muscle
                    let v = m.flatMap(intensity)
                    if m == nil {
                        ctx.fill(part.path, with: .color(Color.primary.opacity(0.05)))
                    } else if let v, v > 0 {
                        // Anche il muscolo meno usato si vede (almeno 25% di opacità).
                        ctx.fill(part.path, with: .color(accent.opacity(0.25 + 0.75 * min(max(v, 0), 1))))
                    } else {
                        ctx.fill(part.path, with: .color(Color.primary.opacity(0.13)))
                    }
                    if let m, m == selected {
                        ctx.stroke(part.path, with: .color(Color.primary), lineWidth: 2)
                    } else {
                        ctx.stroke(part.path, with: .color(Color.primary.opacity(0.25)), lineWidth: 0.7)
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                guard let onTap, s > 0,
                      let m = FigurePaths.muscle(at: CGPoint(x: location.x / s, y: location.y / s), front: front) else { return }
                onTap(m)
            }
            .allowsHitTesting(onTap != nil)
        }
        .aspectRatio(BodyFigure.width / BodyFigure.height, contentMode: .fit)
    }
}

/// Lati della figura da mostrare (true = davanti): solo quelli dove si vede almeno un muscolo indicato.
func figureSides(_ muscles: Set<MuscleGroup>) -> [Bool] {
    let list = [true, false].filter { !BodyFigure.muscles(front: $0).isDisjoint(with: muscles) }
    return list.isEmpty ? [true] : list
}

extension CatalogExercise {
    /// Livello di evidenza di un muscolo per questo esercizio: principale, secondario o nessuno.
    func highlight(_ m: MuscleGroup) -> MuscleHighlight {
        primary.contains(m) ? .primary : (secondary.contains(m) ? .secondary : .idle)
    }
}

/// Miniatura per gli elenchi: la figura (fronte e/o retro, solo i lati utili) con i muscoli dell'esercizio
/// evidenziati. Non intercetta i tocchi. Stessa miniatura dell'app Android (MuscleThumbnail).
struct MuscleThumbnail: View {
    let exercise: CatalogExercise
    var height: CGFloat = 72

    var body: some View {
        HStack(spacing: 2) {
            ForEach(figureSides(Set(exercise.primary + exercise.secondary)), id: \.self) { front in
                MuscleFigure(front: front, highlight: { exercise.highlight($0) }).frame(height: height)
            }
        }
        .accessibilityHidden(true)      // i muscoli sono gia' scritti nella riga
    }
}

/// Mappa del corpo per scegliere i muscoli: figura anatomica (MuscleFigure), fronte o retro.
/// Un tocco su un muscolo lo aggiunge o lo toglie dalla selezione.
struct BodyMapView: View {
    let side: BodySide
    @Binding var selected: Set<MuscleGroup>

    var body: some View {
        MuscleFigure(front: side == .front,
                     highlight: { selected.contains($0) ? .primary : .idle },
                     onTap: { m in
                         if selected.contains(m) { selected.remove(m) } else { selected.insert(m) }
                     })
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityElement()
        .accessibilityLabel(Text(side.titleKey))
        .accessibilityValue(Text(verbatim: selected.map(\.title).sorted().joined(separator: ", ")))
    }
}

/// Muscoli scelti come pillole sotto la mappa, anche quelli dell'altro lato (fronte/retro) che sulla figura non si vedono.
/// La X toglie il singolo muscolo dalla selezione. Ordine fisso (quello dei muscoli nel Core), non quello dei tocchi.
struct SelectedMuscleChips: View {
    @Binding var selected: Set<MuscleGroup>

    var body: some View {
        if !selected.isEmpty {
            FlowLayout(spacing: 8) {
                ForEach(MuscleGroup.allCases.filter { selected.contains($0) }, id: \.self) { m in
                    Button {
                        selected.remove(m)
                    } label: {
                        HStack(spacing: 4) {
                            Text(verbatim: m.title)
                                .font(.footnote.weight(.semibold))
                            Image(systemName: "xmark")
                                .font(.caption2.weight(.bold))
                        }
                        .padding(.leading, 12).padding(.trailing, 8).padding(.vertical, 6)
                        .foregroundStyle(Theme.onAccent)
                        .background(Theme.accentGradient, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("ex.removeMuscle \(m.title)"))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Blocchi predefiniti (braccia, gambe, torace...): un tocco seleziona tutti i muscoli della zona.
struct RegionChips: View {
    @Binding var selected: Set<MuscleGroup>

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(BodyRegion.allCases, id: \.self) { region in
                    let all = Set(region.muscles)
                    let on = all.isSubset(of: selected)
                    Button {
                        if on { selected.subtract(all) } else { selected.formUnion(all) }
                    } label: {
                        Label(region.title, systemImage: region.symbol)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .foregroundStyle(on ? Color.white : Color.primary)
                            .background(on ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Color.primary.opacity(0.10)), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
