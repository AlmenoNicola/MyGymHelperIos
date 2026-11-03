import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers
import MyGymHelperCore

/// Schede di allenamento (piano Full, con consenso): elenco, dettaglio, eliminazione e importazione da PDF, Excel, Word o foto.
/// La scheda piu' recente e' quella usata dai consigli adattivi.
struct TrainingPlansView: View {
    @Environment(SubscriptionManager.self) private var subscriptions
    @Environment(\.modelContext) private var context
    @Query(sort: \TrainingPlanRecord.createdAt, order: .reverse) private var plans: [TrainingPlanRecord]
    @AppStorage(ConsentStore.grantedAtKey) private var consentAt = 0.0
    @State private var importer = PlanImportModel()
    @State private var showConsent = false

    private var allowed: Bool { FeatureGate.isAvailable(.uploadTrainingAndNutritionPlans, for: subscriptions.tier) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ScreenHeader(symbol: "doc.text.magnifyingglass", title: "plans.list.title",
                             subtitle: LocalizedStringKey(AppFeatures.planImportEnabled ? "plans.list.subtitle" : "plans.list.subtitleManual"))

                if !allowed {
                    LockedNote(key: "plans.list.locked").glassCard(padding: 16)
                } else if consentAt == 0 {
                    VStack(spacing: 12) {
                        Label("plans.list.needConsent", systemImage: "lock.fill").font(.callout)
                        Button("consent.open") { showConsent = true }.buttonStyle(.glassProminent).tint(Theme.accent)
                    }
                    .frame(maxWidth: .infinity)
                    .glassCard()
                } else {
                    ImportButtons(model: importer, kind: .training)

                    if plans.isEmpty {
                        Text("plans.list.empty").font(.callout).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading).glassCard(padding: 16)
                    } else {
                        Text("plans.list.activeNote").font(.footnote).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(plans) { record in
                        NavigationLink { TrainingPlanDetailView(record: record) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(verbatim: record.name).font(.headline)
                                    Text(record.createdAt.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if record.id == plans.first?.id {
                                    Text("plans.list.active").font(.caption.bold())
                                        .padding(.horizontal, 10).padding(.vertical, 4)
                                        .background(Theme.accent.opacity(0.35), in: Capsule())
                                }
                                Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.secondary)
                            }
                            .glassCard(padding: 16)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("history.delete", role: .destructive) { context.delete(record); try? context.save() }
                        }
                    }
                }
            }
            .padding(20)
        }
        .appScreen()
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showConsent) { ConsentView { } }
        .sheet(item: $importer.trainingDraft) { draft in
            TrainingPlanReviewView(draft: draft, record: nil)
        }
        .importErrorAlert(importer)
    }
}

// MARK: - Importazione (condivisa con la scheda del nutrizionista)

enum PlanKind { case training, nutrition }

struct TrainingDraft: Identifiable {
    let id = UUID()
    var name: String
    var plan: TrainingPlan
    var sourceText: String
    /// Come e' stata letta (con o senza AI), da mostrare nella revisione.
    var readNote: String? = nil
    /// Scheda importata da file o foto: se a qualche esercizio mancano serie, ripetizioni o peso, i campi si
    /// evidenziano e prima di salvare si chiede conferma all'utente.
    var checkMissing = false
}

struct NutritionDraft: Identifiable {
    let id = UUID()
    var plan: ParsedNutritionPlan
    var sourceText: String
}

/// Stato dell'importazione: legge il file o la foto, estrae il testo e prepara una bozza da rivedere.
@Observable
@MainActor
final class PlanImportModel {
    var isWorking = false
    /// Motivo dell'ultimo errore di lettura (nil = nessun errore): decide il messaggio.
    var failure: TextExtractor.ExtractError?
    var trainingDraft: TrainingDraft?
    var nutritionDraft: NutritionDraft?
    /// Catalogo per collegare gli esercizi della scheda (lo imposta ImportButtons).
    var catalog: [CatalogExercise] = []

    func handle(fileResult: Result<URL, Error>, kind: PlanKind) {
        guard case .success(let url) = fileResult else { failure = .unreadable; return }
        run(kind: kind, name: url.deletingPathExtension().lastPathComponent) {
            try await TextExtractor.text(fromFile: url)
        }
    }

    func handle(photo item: PhotosPickerItem?, kind: PlanKind) {
        guard let item else { return }
        run(kind: kind, name: Date().formatted(date: .abbreviated, time: .omitted)) {
            guard let data = try await item.loadTransferable(type: Data.self) else { throw TextExtractor.ExtractError.unreadable }
            return try await TextExtractor.text(fromImageData: data)
        }
    }

    /// Scheda vuota da compilare a mano.
    func blank(kind: PlanKind) {
        switch kind {
        case .training:
            trainingDraft = TrainingDraft(name: String(localized: "plans.review.newName"),
                                          plan: TrainingPlan(days: [PlanDay(title: "", entries: [PlanEntry(name: "")])]),
                                          sourceText: "")
        case .nutrition:
            nutritionDraft = NutritionDraft(plan: ParsedNutritionPlan(), sourceText: "")
        }
    }

    private func run(kind: PlanKind, name: String, extract: @escaping () async throws -> String) {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                let text = try await extract()
                switch kind {
                case .training:
                    // Con l'AI del telefono (se c'e' e se l'utente non l'ha spenta), altrimenti con le regole.
                    let useAI = UserDefaults.standard.object(forKey: "import.ai") as? Bool ?? true
                    let result = useAI ? await PlanImportAI.read(text, catalog: catalog)
                        : PlanAI.Result(plan: PlanAI.applyMatches(TrainingPlanParser.parse(text), catalog: catalog, chosen: nil),
                                        usedAI: false, aiStatus: "spenta dall'utente")
                    if result.plan.allEntries.isEmpty {
                        // Nessun esercizio: niente revisione vuota, si propone di inviare il rapporto con il testo letto
                        // (per capire cosa non va). La scheda si puo' sempre inserire a mano.
                        ErrorReporter.shared.report("Importa scheda", message: String(localized: "plans.nothingFound"),
                            details: "File: \(name)\nAI: \(result.aiStatus)\n\(result.aiError ?? "")\n\nTesto estratto (\(text.count) caratteri):\n\(String(text.prefix(6000)))")
                    } else {
                        trainingDraft = TrainingDraft(name: name, plan: result.plan, sourceText: text,
                                                      readNote: result.usedAI ? "plans.readByAI" : "plans.readByRules",
                                                      checkMissing: true)
                    }
                case .nutrition:
                    nutritionDraft = NutritionDraft(plan: NutritionPlanParser.parse(text), sourceText: text)
                }
            } catch let error as TextExtractor.ExtractError {
                // Testo non leggibile o assente: si propone il rapporto d'errore; gli altri motivi hanno il loro messaggio.
                if error == .unreadable || error == .empty {
                    ErrorReporter.shared.report("Importa scheda: \(name)", error: error, message: String(localized: "import.failedMessage"))
                } else {
                    failure = error
                }
            } catch {
                ErrorReporter.shared.report("Importa scheda: \(name)", error: error)
            }
        }
    }
}

/// Pulsanti per scegliere la fonte: file (PDF, Excel, Word, CSV, immagine, testo), foto, inserimento manuale. Riga "AI locale" disattivata.
struct ImportButtons: View {
    @Bindable var model: PlanImportModel
    let kind: PlanKind
    @State private var showFiles = false
    @State private var photo: PhotosPickerItem?
    @Environment(CatalogStore.self) private var catalogStore
    @AppStorage("import.ai") private var useAI = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Caricamento schede spento (file e foto): la card serve solo a inserire la scheda a mano.
            Text(LocalizedStringKey(AppFeatures.planImportEnabled ? "import.title" : "import.titleManual")).font(.headline)
            if AppFeatures.planImportEnabled {
                HStack(spacing: 10) {
                    // Importazione da file disattivata per ora (AppFeatures.planFileImportEnabled): resta solo la foto.
                    if AppFeatures.planFileImportEnabled {
                        Button { showFiles = true } label: {
                            Label("import.file", systemImage: "doc.fill").lineLimit(1).frame(maxWidth: .infinity)
                        }
                    }
                    // Caricamento da foto disattivato per ora (AppFeatures.planPhotoImportEnabled).
                    if AppFeatures.planPhotoImportEnabled {
                        PhotosPicker(selection: $photo, matching: .images) {
                            Label("import.photo", systemImage: "photo.fill").lineLimit(1).frame(maxWidth: .infinity)
                        }
                    }
                }
                .buttonStyle(.glass)
            }
            Button { model.blank(kind: kind) } label: {
                Label("import.manual", systemImage: "square.and.pencil").lineLimit(1).frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)

            if model.isWorking {
                HStack(spacing: 10) { ProgressView(); Text("import.reading").font(.footnote) }
            }

            // Lettura con Apple Intelligence sul telefono: interruttore e stato
            if kind == .training && AppFeatures.planImportEnabled {
                Toggle(isOn: $useAI) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("import.ai").font(.subheadline)
                        Text("import.aiNote").font(.caption).foregroundStyle(.secondary)
                        if useAI {
                            Text(LocalizedStringKey(PlanImportAI.isAvailable ? "import.aiReady" : "import.aiUnavailable"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .tint(Theme.accent)
            }
            // Con l'operatore ?: le stringhe vanno passate come chiavi (LocalizedStringKey), altrimenti non si traducono.
            if AppFeatures.planImportEnabled {
                Text(LocalizedStringKey(AppFeatures.planFileImportEnabled ? "import.formats" : "import.formatsPhoto")).font(.caption).foregroundStyle(.secondary)
                Text(LocalizedStringKey(AppFeatures.planFileImportEnabled ? "import.privacy" : "import.privacyPhoto")).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .fileImporter(isPresented: $showFiles, allowedContentTypes: TextExtractor.pickerTypes) { result in
            model.catalog = catalogStore.all
            model.handle(fileResult: result, kind: kind)
        }
        .onChange(of: photo) { _, item in
            model.catalog = catalogStore.all
            model.handle(photo: item, kind: kind)
            photo = nil
        }
    }
}

extension View {
    func importErrorAlert(_ model: PlanImportModel) -> some View {
        alert("import.failed", isPresented: Binding(get: { model.failure != nil }, set: { if !$0 { model.failure = nil } })) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(importFailureMessageKey(model.failure))
        }
    }
}

/// Messaggio per ogni motivo di errore (stesse chiavi dell'app Android).
private func importFailureMessageKey(_ failure: TextExtractor.ExtractError?) -> LocalizedStringKey {
    switch failure {
    case .legacyOffice: return "import.failedLegacyOffice"
    case .protected: return "import.failedProtected"
    case .unsupported: return "import.failedUnsupported"
    case .tooLarge: return "import.failedTooLarge"
    default: return "import.failedMessage"
    }
}

// MARK: - Dettaglio

struct TrainingPlanDetailView: View {
    let record: TrainingPlanRecord
    @Environment(CatalogStore.self) private var catalog
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var confirmDelete = false
    @State private var deleteOnExit = false
    @Query(sort: \TrainingPlanRecord.createdAt) private var plans: [TrainingPlanRecord]
    private var review: PlanReviewStore { PlanReviewStore.shared }

    private var plan: TrainingPlan? { try? JSONDecoder().decode(TrainingPlan.self, from: record.data) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Revisione ogni due settimane: proposte in attesa ("Suggeriti") e ritorno alla versione precedente.
                if let pending = review.pending(in: plans), pending.planID == record.id {
                    PlanReviewPlanCard(review: pending, working: review.working,
                                       onApply: { _ = review.apply(pending, plans: plans) }, onDiscard: { review.discard() })
                }
                if let b = review.backup(in: plans), b.planID == record.id {
                    PlanReviewUndoCard(appliedAt: b.appliedAt) { review.restore(plans: plans) }
                }
                // Strumenti di test (da spegnere prima della pubblicazione): cronologia finta per la revisione.
                if TestTools.enabled { FakeHistoryCard() }
                if let plan {
                    ForEach(plan.days) { day in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(verbatim: day.title.isEmpty ? String(localized: "plans.review.day") : day.title).font(.headline)
                            ForEach(day.entries) { entry in
                                entryRow(entry)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassCard()
                    }
                } else {
                    Text("plans.detail.unreadable").foregroundStyle(.secondary).glassCard()
                }
                Button("history.delete", role: .destructive) { confirmDelete = true }.buttonStyle(.glass)
            }
            .padding(20)
        }
        .appScreen()
        .navigationTitle(Text(verbatim: record.name))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("plans.detail.edit") { editing = true }.disabled(plan == nil)
            }
        }
        .sheet(isPresented: $editing) {
            if let plan {
                TrainingPlanReviewView(draft: TrainingDraft(name: record.name, plan: plan, sourceText: ""), record: record)
            }
        }
        .onDisappear {
            guard deleteOnExit else { return }
            context.delete(record)
            try? context.save()
        }
        .confirmationDialog("plans.detail.deleteConfirm", isPresented: $confirmDelete, titleVisibility: .visible) {
            // Si chiude prima la schermata e si elimina dopo: evita di leggere un record gia' eliminato.
            Button("history.delete", role: .destructive) { deleteOnExit = true; dismiss() }
            Button("info.cancel", role: .cancel) { }
        }
    }

    @ViewBuilder
    private func entryRow(_ entry: PlanEntry) -> some View {
        let match = PlanAI.exercise(for: entry, in: catalog.all)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(verbatim: entry.name).font(.subheadline.bold())
                Spacer()
                if let match {
                    NavigationLink { ItemEditorView(exercise: match, switchToWorkout: true) } label: {
                        Image(systemName: "play.circle.fill").font(.title2).foregroundStyle(Theme.accent)
                    }
                    .accessibilityLabel(Text("ex.train"))
                }
            }
            Text(verbatim: entry.summary).font(.caption).foregroundStyle(.secondary)
            if let match, match.name != entry.name {
                Text("plans.detail.matched \(match.name)").font(.caption2).foregroundStyle(Theme.accentSoft)
            }
        }
    }
}

extension PlanEntry {
    /// "4 × 8–10 · 60 kg · 90 s"; serie diverse: "10 × 40 kg · 8 × 50 kg · 90 s" (? = dato mancante).
    var summary: String {
        var parts: [String] = []
        if !perSet.isEmpty {
            parts = perSet.map { p in "\(p.reps.map(String.init) ?? "?") × " + ((p.weightKg ?? 0) > 0 ? p.weightKg!.kgText : "—") }
            if let restSeconds { parts.append("\(restSeconds) s") }
            return parts.joined(separator: " · ")
        }
        if let sets {
            let reps = repsMin.map { lo in repsMax.flatMap { $0 != lo ? "\(lo)–\($0)" : nil } ?? "\(lo)" } ?? "?"
            parts.append("\(sets) × \(reps)")
        }
        if let weightKg, weightKg > 0 { parts.append(weightKg.kgText) }
        if let restSeconds { parts.append("\(restSeconds) s") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Revisione modificabile

/// L'estrazione e' euristica: prima di salvare l'utente controlla e corregge ogni riga.
struct TrainingPlanReviewView: View {
    @State var draft: TrainingDraft
    let record: TrainingPlanRecord?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(CatalogStore.self) private var catalog
    @State private var confirmMissing = false

    /// Dati che la lettura (AI + regole) non ha trovato: si evidenziano e si chiede conferma prima di importare.
    private var gaps: [PlanAI.Gap] { draft.checkMissing ? PlanAI.gaps(cleaned) : [] }

    private var cleaned: TrainingPlan {
        TrainingPlan(days: draft.plan.days.compactMap { day in
            let entries = day.entries.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
            return entries.isEmpty ? nil : PlanDay(id: day.id, title: day.title, entries: entries)
        })
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("plans.review.name", text: $draft.name)
                    Label("plans.review.check", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote).foregroundStyle(.orange)
                    if let note = draft.readNote {
                        Text(LocalizedStringKey(note)).font(.footnote).foregroundStyle(.secondary)
                    }
                    if !gaps.isEmpty {
                        Label("plans.review.missingCount \(gaps.count)", systemImage: "exclamationmark.circle.fill")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                }
                ForEach($draft.plan.days) { $day in
                    Section {
                        TextField("plans.review.dayTitle", text: $day.title).font(.headline)
                        ForEach($day.entries) { $entry in
                            EntryEditor(entry: $entry, match: PlanAI.exercise(for: entry, in: catalog.all),
                                        missing: draft.checkMissing && !entry.name.trimmingCharacters(in: .whitespaces).isEmpty
                                            ? PlanAI.missing(entry) : [])
                        }
                        .onDelete { day.entries.remove(atOffsets: $0) }
                        Button { day.entries.append(PlanEntry(name: "")) } label: {
                            Label("plans.review.addEntry", systemImage: "plus")
                        }
                        if draft.plan.days.count > 1 {
                            Button(role: .destructive) {
                                let id = day.id
                                // Rimozione differita: evita letture fuori indice dei binding della riga stessa.
                                DispatchQueue.main.async { draft.plan.days.removeAll { $0.id == id } }
                            } label: {
                                Label("plans.review.deleteDay", systemImage: "trash")
                            }
                        }
                    }
                }
                Section {
                    Button { draft.plan.days.append(PlanDay(title: "", entries: [PlanEntry(name: "")])) } label: {
                        Label("plans.review.addDay", systemImage: "calendar.badge.plus")
                    }
                }
                if !draft.sourceText.isEmpty {
                    Section {
                        DisclosureGroup("plans.review.source") {
                            Text(verbatim: draft.sourceText).font(.caption.monospaced()).textSelection(.enabled)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background { AppBackground() }
            .navigationTitle(Text("plans.review.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("info.cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("plans.review.save") { if gaps.isEmpty { save() } else { confirmMissing = true } }
                        .disabled(cleaned.days.isEmpty)
                }
            }
            .alert("plans.confirm.title", isPresented: $confirmMissing) {
                Button("plans.confirm.import") { save() }
                Button("plans.confirm.complete", role: .cancel) { }
            } message: {
                Text(missingMessage)
            }
        }
        .interactiveDismissDisabled()
    }

    /// Testo della conferma: elenco degli esercizi con i dati mancanti (al massimo 8, gli altri si contano).
    private var missingMessage: String {
        let all = gaps
        let shown = all.prefix(8)
        var lines = shown.map { "• \($0.name): \(missingText($0.missing))" }
        if all.count > shown.count { lines.append(String(localized: "plans.confirm.more \(all.count - shown.count)")) }
        return String(localized: "plans.confirm.message") + "\n\n" + lines.joined(separator: "\n") + "\n\n"
            + String(localized: "plans.confirm.question")
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(cleaned) else { return }
        let name = draft.name.trimmingCharacters(in: .whitespaces)
        let finalName = name.isEmpty ? String(localized: "plans.review.newName") : name
        if let record {
            record.name = finalName
            record.data = data
        } else {
            context.insert(TrainingPlanRecord(name: finalName, data: data))
        }
        try? context.save()
        dismiss()
    }
}

/// Testo dei dati mancanti di un esercizio: "serie, peso".
private func missingText(_ missing: [PlanAI.Missing]) -> String {
    missing.map { m -> String in
        switch m {
        case .sets: return String(localized: "plans.missing.sets")
        case .reps: return String(localized: "plans.missing.reps")
        case .weight: return String(localized: "plans.missing.weight")
        }
    }.joined(separator: ", ")
}

private struct EntryEditor: View {
    @Binding var entry: PlanEntry
    let match: CatalogExercise?
    /// Dati non trovati nella scheda importata: si evidenziano.
    var missing: [PlanAI.Missing] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("plans.review.exercise", text: $entry.name).font(.subheadline.bold())
                // Nome cambiato a mano: il collegamento al catalogo si rifa' dal nome
                .onChange(of: entry.name) { _, _ in entry.exerciseID = nil }
            if !entry.perSet.isEmpty {
                variedSets
            } else {
                HStack(spacing: 8) {
                    numberField("plans.review.sets", value: $entry.sets, missing: missing.contains(.sets))
                    numberField("plans.review.repsMin", value: $entry.repsMin, missing: missing.contains(.reps))
                    numberField("plans.review.repsMax", value: $entry.repsMax, missing: missing.contains(.reps))
                }
                HStack(spacing: 8) {
                    weightField("plans.review.weight", value: $entry.weightKg, missing: missing.contains(.weight))
                    numberField("plans.review.rest", value: $entry.restSeconds)
                }
            }
            if !missing.isEmpty {
                Text("plans.review.missingFields \(missingText(missing))").font(.caption2).foregroundStyle(.orange)
            }
            if let match {
                Text("plans.detail.matched \(match.name)").font(.caption2).foregroundStyle(Theme.accentSoft)
            } else if !entry.name.isEmpty {
                Text("plans.review.noMatch").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    /// Serie diverse (righe della scheda con lo stesso esercizio): una riga per serie con ripetizioni e peso.
    private var variedSets: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("plans.review.variedSets").font(.caption2).foregroundStyle(.secondary)
            ForEach(0..<entry.perSet.count, id: \.self) { i in
                HStack(spacing: 8) {
                    Text(verbatim: "\(i + 1)").font(.subheadline.bold()).foregroundStyle(Theme.accent).frame(width: 20)
                    numberField("plans.review.reps", value: setReps(i),
                                missing: missing.contains(.reps) && i < entry.perSet.count && entry.perSet[i].reps == nil)
                    weightField("plans.review.weight", value: setWeight(i),
                                missing: missing.contains(.weight) && i < entry.perSet.count && (entry.perSet[i].weightKg ?? 0) <= 0)
                    if entry.perSet.count > 1 {
                        Button { var l = entry.perSet; l.remove(at: i); entry = entry.withSets(l) } label: {
                            Image(systemName: "xmark.circle").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("sets.remove \(i + 1)"))
                    }
                }
            }
            .id(entry.perSet.count)
            HStack(spacing: 8) {
                Button { if let last = entry.perSet.last { entry = entry.withSets(entry.perSet + [last]) } } label: {
                    Label("sets.add", systemImage: "plus").font(.subheadline).lineLimit(1)
                }
                .buttonStyle(.borderless)
                Spacer()
                numberField("plans.review.rest", value: $entry.restSeconds)
            }
        }
    }

    // Ripetizioni e peso della serie `i` (indice controllato: le serie si possono eliminare).
    private func setReps(_ i: Int) -> Binding<Int?> {
        Binding(get: { i < entry.perSet.count ? entry.perSet[i].reps : nil },
                set: { v in guard i < entry.perSet.count else { return }; var l = entry.perSet; l[i].reps = v; entry = entry.withSets(l) })
    }
    private func setWeight(_ i: Int) -> Binding<Double?> {
        Binding(get: { i < entry.perSet.count ? entry.perSet[i].weightKg : nil },
                set: { v in guard i < entry.perSet.count else { return }; var l = entry.perSet; l[i].weightKg = v; entry = entry.withSets(l) })
    }

    private func weightField(_ title: LocalizedStringKey, value: Binding<Double?>, missing: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2)
                .foregroundStyle(missing ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
            TextField(LocalizedStringKey(missing ? "?" : "—"), value: value, format: .number).keyboardType(.decimalPad)
        }
    }

    /// missing: dato non trovato nella scheda importata, si evidenzia in arancione.
    private func numberField(_ title: LocalizedStringKey, value: Binding<Int?>, missing: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(missing ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
            TextField(LocalizedStringKey(missing ? "?" : "—"), value: value, format: .number).keyboardType(.numberPad)
        }
    }
}
