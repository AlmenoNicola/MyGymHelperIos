import SwiftUI
import MyGymHelperCore

// Revisione della scheda ogni due settimane (piano Pro): domanda a fine allenamento, proposta in
// "Consiglio per oggi", elenco dei suggeriti nel dettaglio della scheda e ritorno alla scheda precedente.
// Come PlanReviewUi.kt su Android.

private struct ReviewCardTitle: View {
    let key: LocalizedStringKey
    var body: some View {
        Label { Text(key).appFont(.headline) } icon: { Image(systemName: "sparkles").foregroundStyle(Theme.accent) }
    }
}

/// Nota scritta dall'IA del telefono e pulsante "Segnala il testo dell'IA" (norme degli store sui contenuti generati
/// dall'IA): apre l'app di posta con l'e-mail a AIContentReport.email gia' compilata con il testo da segnalare.
/// Senza app di posta mostra l'indirizzo a cui scrivere. Come AiNote in PlanReviewUi.kt su Android.
private struct AINoteView: View {
    let note: String
    @Environment(\.openURL) private var openURL
    @State private var noMail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("review.aiNote \(note)").appFont(.footnote).foregroundStyle(Theme.accent)
            Button {
                noMail = false
                let info = ErrorReporter.info(time: Date())
                var c = URLComponents(); c.scheme = "mailto"; c.path = AIContentReport.email
                c.queryItems = [URLQueryItem(name: "subject", value: AIContentReport.subject(info: info)),
                                URLQueryItem(name: "body", value: AIContentReport.body(
                                    intro: String(localized: "review.report.intro"), aiText: note, info: info))]
                if let url = c.url { openURL(url) { accepted in if !accepted { noMail = true } } } else { noMail = true }
            } label: {
                Label("review.report", systemImage: "flag").appFont(.caption).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            if noMail {
                Text("suggest.noMail \(AIContentReport.email)").appFont(.footnote).foregroundStyle(.orange)
            }
        }
    }
}

/// Domanda di fine allenamento: troppo leggero, giusto, troppo pesante (o "Non ora", si richiede la volta dopo).
struct PlanReviewQuestionCard: View {
    let planName: String
    let onAnswer: (PlanFeedback) -> Void
    let onLater: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ReviewCardTitle(key: "review.question.title")
            Text("review.question.body \(planName)").appFont(.subheadline).foregroundStyle(.secondary)
            Button { onAnswer(.tooLight) } label: { Text("review.light").lineLimit(1).frame(maxWidth: .infinity) }
                .buttonStyle(.glassProminent).tint(Theme.accent)
            Button { onAnswer(.right) } label: { Text("review.right").lineLimit(1).frame(maxWidth: .infinity) }
                .buttonStyle(.glass)
            Button { onAnswer(.tooHeavy) } label: { Text("review.heavy").lineLimit(1).frame(maxWidth: .infinity) }
                .buttonStyle(.glass)
            Button(action: onLater) { Text("review.later").lineLimit(1).frame(maxWidth: .infinity).foregroundStyle(.secondary) }
                .buttonStyle(.glass)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}

/// Dopo la risposta: proposta in preparazione o pronta.
struct PlanReviewAnsweredNote: View {
    let working: Bool
    let hasProposal: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ReviewCardTitle(key: "review.question.title")
            Text(LocalizedStringKey(working ? "review.working" : hasProposal ? "review.ready" : "review.none"))
                .appFont(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}

/// "Consiglio per oggi" con la proposta della revisione per questo esercizio: prima e dopo, motivi, nota dell'AI.
/// "Applica" aggiorna tutta la scheda e gli elenchi (e i valori della schermata); "Ignora" scarta la proposta.
struct PlanReviewAdviceCard: View {
    let review: PlanReview
    let change: ReviewChange
    let working: Bool
    let onApply: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ReviewCardTitle(key: "advice.adaptiveTitle")
            Text("review.cardSubtitle").appFont(.caption).foregroundStyle(.secondary)
            ForEach(change.reasonKeys, id: \.self) { Text(LocalizedStringKey($0)).appFont(.subheadline).foregroundStyle(.secondary) }
            if let note = review.note { AINoteView(note: note) }
            Text(verbatim: AdviceText.loadChange(before: change.beforeParameters, after: change.afterParameters))
                .appFont(.subheadline, weight: .semibold).foregroundStyle(Theme.accent)
            Text("review.before \(change.beforeParameters.summaryText)").appFont(.footnote).foregroundStyle(.secondary)
            Text("review.after \(change.afterParameters.summaryText)").appFont(.subheadline, weight: .semibold)
            if working { Text("review.working").appFont(.caption).foregroundStyle(.secondary) }
            Text("review.scope \(review.changedCount) \(review.planName)").appFont(.caption).foregroundStyle(.secondary)
            Button(action: onApply) {
                Label("advice.apply", systemImage: "checkmark").lineLimit(1).frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent).tint(Theme.accent)
            Button(action: onDiscard) { Text("review.discard").lineLimit(1).frame(maxWidth: .infinity).foregroundStyle(.secondary) }
                .buttonStyle(.glass)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}

/// Scheda aggiornata con "Applica": data e ritorno alla versione precedente.
struct PlanReviewUndoCard: View {
    let appliedAt: Date
    let onUndo: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("review.applied \(appliedAt.formatted(date: .abbreviated, time: .omitted))")
                .appFont(.subheadline).foregroundStyle(.secondary)
            Button(action: onUndo) {
                Label("review.undo", systemImage: "arrow.uturn.backward").lineLimit(1).frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}

/// Dettaglio della scheda: "Suggeriti", tutte le proposte in attesa con Applica e Ignora.
struct PlanReviewPlanCard: View {
    let review: PlanReview
    let working: Bool
    let onApply: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ReviewCardTitle(key: "review.planTitle")
            Text("review.cardSubtitle").appFont(.caption).foregroundStyle(.secondary)
            if let note = review.note { AINoteView(note: note) }
            if working { Text("review.working").appFont(.caption).foregroundStyle(.secondary) }
            ForEach(review.changes, id: \.entryID) { c in
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: c.name).appFont(.subheadline, weight: .bold)
                    Text(verbatim: AdviceText.loadChange(before: c.beforeParameters, after: c.afterParameters))
                        .appFont(.caption, weight: .semibold).foregroundStyle(Theme.accent)
                    if c.changed {
                        Text("review.before \(c.beforeParameters.summaryText)").appFont(.caption).foregroundStyle(.secondary)
                        Text("review.after \(c.afterParameters.summaryText)").appFont(.footnote, weight: .semibold)
                    }
                    ForEach(c.reasonKeys, id: \.self) { Text(LocalizedStringKey($0)).appFont(.caption).foregroundStyle(.secondary) }
                }
            }
            if review.changedCount > 0 {
                Button(action: onApply) {
                    Label("advice.apply", systemImage: "checkmark").lineLimit(1).frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent).tint(Theme.accent)
            } else {
                Text("review.nothingChanged").appFont(.footnote).foregroundStyle(.secondary)
            }
            Button(action: onDiscard) { Text("review.discard").lineLimit(1).frame(maxWidth: .infinity).foregroundStyle(.secondary) }
                .buttonStyle(.glass)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}
