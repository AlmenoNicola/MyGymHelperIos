import SwiftUI
import Observation
import MyGymHelperCore

/// Stato del tutorial in sovraimpressione (i passi sono in Core/Tutorial.swift, uguali su Android).
/// Gli elementi da indicare si registrano con `.tutorialTarget(_:)`: la loro posizione sullo schermo
/// (coordinate globali) viene salvata qui e l'overlay li illumina.
@Observable
@MainActor
final class TutorialController {
    static let shared = TutorialController()
    static let seenKey = "tutorial.seenVersion"

    /// Passo mostrato; nil = tutorial chiuso.
    private(set) var index: Int?
    /// Riquadri degli elementi visibili, in coordinate globali.
    var frames: [String: CGRect] = [:]

    var isActive: Bool { index != nil }
    var step: TutorialStep? { index.map { TutorialGuide.steps[$0] } }
    var currentTarget: String? { step?.target }

    private init() {}

    static var seenVersion: Int { UserDefaults.standard.integer(forKey: seenKey) }

    func start() { index = 0 }
    func go(to i: Int) { index = min(max(i, 0), TutorialGuide.steps.count - 1) }

    /// Fine o "Salta": si salva la versione vista, cosi' non riparte da solo.
    func finish() {
        index = nil
        UserDefaults.standard.set(TutorialGuide.version, forKey: Self.seenKey)
    }
}

extension View {
    /// Segna un elemento che il tutorial puo' illuminare (`id` = una costante di TutorialTarget).
    /// Imposta anche `.id(id)`, cosi' `tutorialScrollFollow()` lo porta in vista.
    func tutorialTarget(_ id: String) -> some View {
        self.id(id)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                TutorialController.shared.frames[id] = frame
            }
            .onDisappear { TutorialController.shared.frames[id] = nil }
    }

    /// Da mettere sulla ScrollView di una schermata con elementi del tutorial: scorre fino all'elemento del passo.
    func tutorialScrollFollow() -> some View { modifier(TutorialScrollFollower()) }
}

private struct TutorialScrollFollower: ViewModifier {
    private var tutorial: TutorialController { TutorialController.shared }

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content.onChange(of: tutorial.index, initial: true) { _, _ in
                guard let target = tutorial.currentTarget else { return }
                // Piccola attesa: cambiando scheda la schermata deve prima comparire.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(250))
                    withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(target, anchor: .center) }
                }
            }
        }
    }
}

private extension TutorialTab {
    var mainTab: AppSettings.MainTab {
        switch self {
        case .workout: .workout
        case .exercises: .exercises
        case .nutrition: .nutrition
        case .profile: .profile
        case .info: .info
        }
    }
}

/// Sovraimpressione: oscura l'app, lascia "bucato" l'elemento del passo con un bordo pulsante e una mano che
/// lo indica, e mostra il fumetto con testo e pulsanti. Blocca i tocchi sull'app finche' e' aperta.
/// Va messa sopra a tutta l'app (barra delle schede compresa) con `.ignoresSafeArea()`.
struct TutorialOverlay: View {
    @Bindable private var settings = AppSettings.shared
    private var tutorial: TutorialController { TutorialController.shared }
    @State private var bubbleHeight: CGFloat = 0
    @State private var pulse = false
    @State private var bob = false

    var body: some View {
        if let index = tutorial.index {
            let step = TutorialGuide.steps[index]
            GeometryReader { geo in
                let screen = geo.size
                let safe = geo.safeAreaInsets
                let rect = step.target.flatMap { tutorial.frames[$0] }.flatMap { r -> CGRect? in
                    // Solo se l'elemento e' davvero sullo schermo.
                    let visible = r.intersection(CGRect(origin: .zero, size: screen))
                    return visible.width > 1 && visible.height > 1 ? visible : nil
                }
                let hole = rect?.insetBy(dx: -8, dy: -8)
                let layout = BubbleLayout(hole: hole, screen: screen, safe: safe, bubbleHeight: bubbleHeight)

                ZStack(alignment: .topLeading) {
                    // Oscuramento con il "buco" sull'elemento.
                    SpotlightShape(hole: hole)
                        .fill(Theme.scrim, style: FillStyle(eoFill: true))
                        .contentShape(Rectangle())
                        .onTapGesture { }                     // i tocchi non arrivano all'app
                    if let hole {
                        RoundedRectangle(cornerRadius: 22)
                            .stroke(Theme.accent, lineWidth: 2.5)
                            .frame(width: hole.width, height: hole.height)
                            .position(x: hole.midX, y: hole.midY)
                            .allowsHitTesting(false)
                        RoundedRectangle(cornerRadius: 22 + (pulse ? 12 : 0))
                            .stroke(Theme.accent.opacity(pulse ? 0 : 0.9), lineWidth: 3)
                            .frame(width: hole.width + (pulse ? 24 : 0), height: hole.height + (pulse ? 24 : 0))
                            .position(x: hole.midX, y: hole.midY)
                            .allowsHitTesting(false)
                        if layout.handFits {
                            // Mano che indica l'elemento (punta in alto; capovolta se il fumetto e' sopra).
                            Image(systemName: "hand.point.up.left.fill")
                                .font(.system(size: 38 * AppTextScale))
                                .foregroundStyle(.white)
                                .rotationEffect(.degrees(layout.above ? 180 : 0))
                                .position(x: min(max(hole.midX, 40), screen.width - 40),
                                          y: layout.above ? hole.minY - 26 - (bob ? 8 : 0) : hole.maxY + 26 + (bob ? 8 : 0))
                                .allowsHitTesting(false)
                        }
                    }

                    TutorialBubble(index: index, step: step, showArt: rect == nil)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bubbleHeight = $0 }
                        .padding(.horizontal, 16)
                        .frame(width: screen.width)
                        .offset(y: layout.bubbleY)
                }
                .animation(.easeInOut(duration: 0.3), value: index)
                .animation(.easeInOut(duration: 0.3), value: hole)
            }
            .ignoresSafeArea()
            .task(id: index) {
                // Apre la scheda del passo.
                if let tab = step.tab { settings.selectedTab = tab.mainTab }
            }
            .onAppear {
                withAnimation(.easeOut(duration: 1.3).repeatForever(autoreverses: false)) { pulse = true }
                withAnimation(.easeInOut(duration: 0.65).repeatForever(autoreverses: true)) { bob = true }
            }
            // Alla riapertura del tutorial le animazioni ripartono da capo.
            .onDisappear { pulse = false; bob = false }
            .transition(.opacity)
        }
    }
}

/// Posizione del fumetto: nello spazio piu' grande sopra o sotto l'elemento; al centro se non c'e' un elemento.
private struct BubbleLayout {
    let above: Bool
    let handFits: Bool
    let bubbleY: CGFloat

    init(hole: CGRect?, screen: CGSize, safe: EdgeInsets, bubbleHeight: CGFloat) {
        let margin: CGFloat = 16, hand: CGFloat = 52
        let top = safe.top + margin / 2
        let bottom = screen.height - safe.bottom - margin / 2
        guard let hole else {
            above = false; handFits = false
            bubbleY = max(top, (screen.height - bubbleHeight) / 2)
            return
        }
        let spaceAbove = hole.minY - safe.top
        let spaceBelow = screen.height - safe.bottom - hole.maxY
        let needed = bubbleHeight + hand + margin
        above = spaceAbove > spaceBelow
        handFits = (above ? spaceAbove : spaceBelow) >= needed
        let y: CGFloat
        switch (above, handFits) {
        case (true, true): y = hole.minY - hand - margin / 2 - bubbleHeight
        case (false, true): y = hole.maxY + hand + margin / 2
        case (true, false): y = top                                   // non ci sta: in alto, sopra parte dell'elemento
        case (false, false): y = bottom - bubbleHeight                // non ci sta: in basso
        }
        bubbleY = min(max(y, top), max(top, bottom - bubbleHeight))
    }
}

/// Rettangolo dello schermo con un buco arrotondato (riempito con la regola pari-dispari).
private struct SpotlightShape: Shape {
    var hole: CGRect?

    func path(in rect: CGRect) -> Path {
        var p = Path(rect)
        if let hole { p.addRoundedRect(in: hole, cornerSize: CGSize(width: 22, height: 22)) }
        return p
    }
}

private struct TutorialBubble: View {
    let index: Int
    let step: TutorialStep
    let showArt: Bool
    private var tutorial: TutorialController { TutorialController.shared }
    private var isLast: Bool { index == TutorialGuide.steps.count - 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                StepDots(index: index)
                Spacer(minLength: 4)
                Text("tutorial.step \(index + 1) \(TutorialGuide.steps.count)")
                    .appFont(.caption).foregroundStyle(.secondary).monospacedDigit()
                if !isLast {
                    Button("tutorial.skip") { tutorial.finish() }
                        .appFont(.subheadline, weight: .semibold).foregroundStyle(Theme.accentSoft)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                if showArt, let art = step.art {
                    TutorialArtwork(art: art).frame(maxWidth: .infinity)
                }
                Text(LocalizedStringKey(step.titleKey)).appFont(.title3, weight: .bold).lineLimit(1)
                Text(LocalizedStringKey(step.bodyKey)).appFont(.subheadline).foregroundStyle(Color.primary.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .id(step.id)
            .transition(.opacity)
            HStack(spacing: 10) {
                if let prev = TutorialGuide.previous(index) {
                    Button { tutorial.go(to: prev) } label: {
                        Text("tutorial.back").lineLimit(1).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                }
                Button {
                    if let next = TutorialGuide.next(index) { tutorial.go(to: next) } else { tutorial.finish() }
                } label: {
                    Text(LocalizedStringKey(isLast ? "tutorial.done" : "tutorial.next"))
                        .appFont(.headline).lineLimit(1).frame(maxWidth: .infinity).padding(.vertical, 4)
                }
                .buttonStyle(.glassProminent).tint(Theme.accent)
                .layoutPriority(1)
            }
        }
        .padding(18)
        .background(Theme.bubble, in: .rect(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).stroke(Color.primary.opacity(0.14), lineWidth: 1))
        // Il fumetto segue il tema: scuro nei temi originale e scuro (preferredColorScheme), chiaro o scuro nel neutro.
    }
}

/// Puntini di avanzamento (quelli gia' visti in arancio).
private struct StepDots: View {
    let index: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<TutorialGuide.steps.count, id: \.self) { i in
                Capsule()
                    .fill(i <= index ? Theme.accent : Color.primary.opacity(0.2))
                    .frame(width: i == index ? 12 : 5, height: 5)
            }
        }
    }
}

/// Disegni dei passi senza elemento da indicare (benvenuto, telefono sul corpo, sessione, fine).
private struct TutorialArtwork: View {
    let art: TutorialArt
    @State private var phase = false

    var body: some View {
        ZStack {
            Circle().fill(Theme.accentGradient).frame(width: 132, height: 132)
                .shadow(color: Theme.accent.opacity(0.5), radius: 14, y: 6)
            switch art {
            case .welcome:
                Image(systemName: "dumbbell.fill").font(.system(size: 56 * AppTextScale, weight: .bold)).foregroundStyle(.white)
                    .rotationEffect(.degrees(phase ? 20 : -20))
            case .strap:
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "figure.strengthtraining.functional").font(.system(size: 76 * AppTextScale)).foregroundStyle(.white)
                    // Telefono legato al braccio che oscilla come durante una ripetizione.
                    Image(systemName: "iphone.gen3").font(.system(size: 26 * AppTextScale, weight: .bold)).foregroundStyle(Theme.accent)
                        .padding(4).background(.white, in: .rect(cornerRadius: 7))
                        .rotationEffect(.degrees(phase ? 15 : -15))
                        .offset(x: 8, y: phase ? 22 : 12)
                }
            case .session:
                ZStack {
                    Circle().stroke(.white.opacity(0.25), lineWidth: 9)
                    Circle().trim(from: 0, to: phase ? 1 : 0.1)
                        .stroke(.white, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Image(systemName: "timer").appFont(.caption, weight: .bold)
                        Text(verbatim: "10").font(.system(size: 30 * AppTextScale, weight: .black, design: .rounded))
                    }
                    .foregroundStyle(.white)
                }
                .frame(width: 96, height: 96)
            case .done:
                Image(systemName: "checkmark.circle.fill").font(.system(size: 64 * AppTextScale)).foregroundStyle(.white)
                    .scaleEffect(phase ? 1.12 : 0.95)
            }
        }
        .onAppear { withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { phase = true } }
    }
}
