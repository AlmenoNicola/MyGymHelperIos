import SwiftUI
import AVFoundation
import MyGymHelperCore

/// Voce (maschile/femminile, scelta della voce, velocita', anteprima), spiegazione dell'esercizio e musica
/// (come Audio.kt su Android). Su iPhone si comandano Apple Music e Spotify (con l'SDK Spotify).
struct AudioSettingsView: View {
    private var settings: AppSettings { AppSettings.shared }
    private var voice: VoiceEngine { VoiceEngine.shared }
    @State private var rate = AppSettings.shared.voiceRate
    @State private var cueTester: CueService?
    @AppStorage("cue.sound") private var soundOn = true
    @AppStorage("cue.voice") private var voiceOn = true
    @AppStorage("cue.haptics") private var hapticsOn = true

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                ScreenHeader(symbol: "person.wave.2.fill", title: "audio.title", subtitle: "audio.subtitle")
                cueCard
                voiceCard
                coachingCard
                musicCard
            }
            .padding(20)
        }
        .appScreen()
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { voice.applyVoice() }
        // Niente shutdown: fermerebbe la voce condivisa.
        .onDisappear { cueTester = nil }
    }

    /// Avvisi durante l'allenamento (voce, suono, vibrazione) con prova: prima erano nella scheda Allenamento.
    private var cueCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("cue.title").appFont(.headline)
            Toggle("cue.voice", isOn: $voiceOn)
            Toggle("cue.sound", isOn: $soundOn)
            Toggle("cue.haptics", isOn: $hapticsOn)
            Button {
                let tester = cueTester ?? CueService()
                tester.options = CueOptions(sound: soundOn, voice: voiceOn, haptics: hapticsOn,
                                            countReps: AppSettings.shared.voiceCountReps)
                tester.preview()
                cueTester = tester
            } label: {
                Label("cue.test", systemImage: "speaker.wave.2.fill").lineLimit(1).frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            Text("cue.testNote").appFont(.caption).foregroundStyle(.secondary)
        }
        .tint(Theme.accent)
        .glassCard()
    }

    private var voiceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("audio.voice").appFont(.headline)
            Picker("audio.voice", selection: Binding(get: { settings.voiceGender }, set: { settings.setVoiceGender($0); voice.applyVoice() })) {
                Text("audio.female").tag("female")
                Text("audio.male").tag("male")
            }
            .pickerStyle(.segmented)

            Picker("audio.voiceChoice", selection: Binding(get: { settings.voiceIdentifier }, set: { settings.setVoiceIdentifier($0); voice.applyVoice() })) {
                Text("audio.voiceAuto").tag("")
                ForEach(Array(shownVoices.enumerated()), id: \.element.id) { index, v in
                    Text(verbatim: label(for: v, number: index + 1)).tag(v.id)
                }
            }
            .pickerStyle(.menu)
            // Una voce scelta prima che ora non e' in elenco (altro genere o oltre il limite) torna su "Automatica".
            .onAppear { resetHiddenVoice() }
            .onChange(of: settings.voiceGender) { resetHiddenVoice() }
            if voice.genderApproximated {
                Text(settings.voiceGender == "male" ? "audio.noMale" : "audio.noFemale").appFont(.caption).foregroundStyle(.secondary)
            }

            Text("audio.rate").appFont(.subheadline, weight: .bold)
            HStack {
                Slider(value: $rate, in: 0.75...1.25, step: 0.05) { editing in
                    if !editing { settings.setVoiceRate(rate) }
                }
                Text(verbatim: "×" + rate.formatted(.number.precision(.fractionLength(2)))).monospacedDigit()
            }
            .tint(Theme.accent)

            Button { settings.setVoiceRate(rate); voice.preview(String(localized: "audio.previewText")) } label: {
                Label("audio.preview", systemImage: "speaker.wave.2.fill").lineLimit(1).frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            Text("audio.voiceNoteIOS").appFont(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var coachingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("audio.coaching").appFont(.headline)
            Toggle("audio.explain", isOn: Binding(get: { settings.explainExercise }, set: { settings.setExplainExercise($0) }))
            Toggle("audio.countReps", isOn: Binding(get: { settings.voiceCountReps }, set: { settings.setVoiceCountReps($0) }))
            Text("audio.coachingNote").appFont(.caption).foregroundStyle(.secondary)
        }
        .tint(Theme.accent)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    /// Con Spotify integrato spento, chi l'aveva scelto vede (e usa) "Altra app".
    private var shownMusicMode: String {
        settings.musicMode == "spotify" && !AppFlags.spotifyIntegration ? "other" : settings.musicMode
    }

    private var musicCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("music.title", systemImage: "music.note").appFont(.headline)
            Toggle("music.enabled", isOn: Binding(get: { settings.musicEnabled }, set: { settings.setMusicEnabled($0) }))
            if settings.musicEnabled {
                Picker("music.title", selection: Binding(get: { shownMusicMode }, set: { settings.setMusicMode($0) })) {
                    Text("music.appleMusic").tag("appleMusic")
                    // Spotify integrato spento per ora (AppFlags)
                    if AppFlags.spotifyIntegration { Text(verbatim: "Spotify").tag("spotify") }
                    Text("music.otherApp").tag("other")
                }
                .pickerStyle(.segmented)
                switch shownMusicMode {
                case "spotify": SpotifySection()        // accesso a Spotify, scelta di playlist/album/brani, ricerca
                case "appleMusic": Text("music.appleMusicNote").appFont(.caption).foregroundStyle(.secondary)
                default: Text("music.otherAppNote").appFont(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .tint(Theme.accent)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    /// Solo le voci del genere scelto (gia' ordinate, prima le migliori): solo una voce extra (oltre ad "Automatica"), come su Android.
    /// Le voci di genere non indicato non compaiono piu' (come su Android).
    private var shownVoices: [VoiceOption] {
        let male = settings.voiceGender == "male"
        let wanted: AVSpeechSynthesisVoiceGender = male ? .male : .female
        return Array(voice.voices.filter { $0.gender == wanted }.prefix(1))
    }

    private func resetHiddenVoice() {
        let id = settings.voiceIdentifier
        if !id.isEmpty && !shownVoices.contains(where: { $0.id == id }) {
            settings.setVoiceIdentifier(""); voice.applyVoice()
        }
    }

    /// "Voce 3 (nome) · premium": senza il genere, che e' gia' quello scelto sopra.
    private func label(for v: VoiceOption, number: Int) -> String {
        var parts = [localized("audio.voiceN %lld", number) + " (\(v.name))"]
        switch v.quality {
        case .premium: parts.append(localized("audio.premium"))
        case .enhanced: parts.append(localized("audio.enhanced"))
        default: break
        }
        return parts.joined(separator: " · ")
    }
}
