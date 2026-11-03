import SwiftUI
import MyGymHelperCore

/// Testi condivisi per i consigli (usati in impostazione allenamento e riepilogo).
extension CoachingAdvice {
    var textKey: LocalizedStringKey { textKey(bodyweight: false) }

    /// Con il corpo libero (peso 0) l'aumento di carico diventa una ripetizione in piu' (vedi `CoachingResult.applied`).
    func textKey(bodyweight: Bool) -> LocalizedStringKey {
        switch self {
        case .increaseWeight(let kg): return bodyweight ? "advice.moreReps" : "advice.increase \(kg.formatted())"
        case .keepAsIs: return "advice.keep"
        case .decreaseWeight(let percent): return "advice.decrease \(percent)"
        case .addSet: return "advice.addSet"
        case .removeSet: return "advice.removeSet"
        }
    }
}

extension Double {
    /// Peso leggibile: "62,5 kg" (separatore decimale della lingua del telefono).
    var kgText: String { "\(formatted(.number.precision(.fractionLength(0...2)))) kg" }
}

/// Riga riassuntiva di parametri proposti: serie x ripetizioni, peso, pausa.
/// Serie diverse: una riga per serie ("1. 12 × 40 kg") e la pausa.
/// Riga del carico di un consiglio: "Carico: 60 → 62,5 kg (+2,5 kg)"; serie diverse "40/45 → 42,5/47,5 kg (+2,5 kg)";
/// "Carico: 60 kg (invariato)"; "Carico: corpo libero". Come loadChangeLine su Android.
enum AdviceText {
    static func loadChange(before: WorkoutParameters, after: WorkoutParameters) -> String {
        let b = before.targets.map(\.weightKg), a = after.targets.map(\.weightKg)
        if a.allSatisfy({ $0 <= 0 }) && b.allSatisfy({ $0 <= 0 }) { return String(localized: "advice.loadBodyweight") }
        func fmt(_ w: [Double]) -> String {
            let list = Set(w).count == 1 ? [w[0]] : w
            return list.map { $0.kgText.replacingOccurrences(of: " kg", with: "") }.joined(separator: "/") + " kg"
        }
        if fmt(b) == fmt(a) { return String(localized: "advice.loadUnchanged \(fmt(a))") }
        let deltas = Array(Set(zip(a, b).map { $0 - $1 }))
        let delta = deltas.count == 1 && abs(deltas[0]) > 1e-9
            ? " (" + (deltas[0] > 0 ? "+" : "−") + abs(deltas[0]).kgText + ")" : ""
        return String(localized: "advice.load \(fmt(b) + " → " + fmt(a) + delta)")
    }
}

struct ParametersLine: View {
    let parameters: WorkoutParameters

    var body: some View {
        if parameters.isVaried {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(parameters.targets.enumerated()), id: \.offset) { i, t in
                    Text(verbatim: "\(i + 1). \(t.reps) × " + (t.weightKg > 0 ? t.weightKg.kgText : String(localized: "setup.bodyweight")))
                }
                Label { Text(verbatim: "\(parameters.restSeconds) s") } icon: { Image(systemName: "timer") }
                    .labelStyle(.titleAndIcon)
            }
            .font(.subheadline.weight(.semibold))
        } else {
            uniformLine
        }
    }

    private var uniformLine: some View {
        HStack(spacing: 14) {
            Label { Text(verbatim: "\(parameters.sets) × \(parameters.reps)") } icon: { Image(systemName: "repeat") }
            Label { Text(verbatim: parameters.weightKg > 0 ? parameters.weightKg.kgText : "—") } icon: { Image(systemName: "scalemass") }
            Label { Text(verbatim: "\(parameters.restSeconds) s") } icon: { Image(systemName: "timer") }
        }
        .font(.subheadline.weight(.semibold))
        .labelStyle(.titleAndIcon)
    }
}

/// Scheda con un consiglio e il pulsante "Applica".
struct AdviceCard: View {
    let title: LocalizedStringKey
    let reasons: [String]
    let parameters: WorkoutParameters
    var details: [LocalizedStringKey] = []
    /// Valori attuali: se presenti si mostra il carico in kg prima → dopo.
    var before: WorkoutParameters? = nil
    var onApply: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label { Text(title).font(.headline) } icon: { Image(systemName: "sparkles").foregroundStyle(Theme.accent) }
            ForEach(reasons, id: \.self) { key in
                Text(LocalizedStringKey(key)).font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(Array(details.enumerated()), id: \.offset) { _, item in
                Text(item).font(.subheadline)
            }
            if let before {
                Text(verbatim: AdviceText.loadChange(before: before, after: parameters))
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent)
            }
            ParametersLine(parameters: parameters)
            if let onApply {
                Button(action: onApply) {
                    Label("advice.apply", systemImage: "checkmark").lineLimit(1).frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent).tint(Theme.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}

/// Avviso di funzione disponibile con un piano superiore.
struct LockedNote: View {
    let key: LocalizedStringKey
    var body: some View {
        // Tocco: apre i piani (la funzione e' disponibile con un abbonamento).
        NavigationLink { PaywallView() } label: {
            HStack {
                Label(key, systemImage: "lock.fill")
                    .font(.footnote).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text("plans.see").font(.footnote.bold()).foregroundStyle(Theme.accentSoft)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}
