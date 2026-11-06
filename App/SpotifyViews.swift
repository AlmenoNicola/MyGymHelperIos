import SwiftUI
import MyGymHelperCore

/// Riga descrittiva di un contenuto: "Nicola · 42 brani", "Album · Artista", "Brano · Artista".
private func subtitle(_ item: SpotifyItem) -> String {
    var parts: [String] = []
    switch item.kind {
    case .playlist:
        if let d = item.detail { parts.append(d) }
        if let c = item.count { parts.append(localized("spotify.tracks %lld", c)) }
    case .album:
        parts.append(localized("spotify.album"))
        if let d = item.detail { parts.append(d) }
    case .track:
        parts.append(localized("spotify.track"))
        if let d = item.detail { parts.append(d) }
    case .artist:
        parts.append("Spotify")
    }
    return parts.joined(separator: " · ")
}

/// Immagine da internet (copertina o foto profilo); finche' non e' pronta si vede un'icona.
private struct CoverImage: View {
    let url: String?
    var size: CGFloat = 52
    var round = false
    var placeholder = "music.note"

    var body: some View {
        AsyncImage(url: url.flatMap(URL.init(string:))) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Image(systemName: placeholder).foregroundStyle(.secondary)
        }
        .frame(width: size, height: size)
        .background(Color.primary.opacity(0.1))
        .clipShape(round ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 8)))
    }
}

/// Contenuto Spotify con copertina, nome e descrizione.
struct SpotifyItemRow: View {
    let item: SpotifyItem
    var selected = false

    var body: some View {
        HStack(spacing: 12) {
            CoverImage(url: item.imageURL, round: item.kind == .artist)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: item.name).appFont(.subheadline, weight: .bold).lineLimit(1)
                Text(verbatim: subtitle(item)).appFont(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent) }
        }
        .contentShape(Rectangle())
    }
}

/// Parte Spotify della scheda "Voce e musica": account (accesso/uscita), musica scelta (dalle playlist o dalla
/// ricerca) e, senza accesso, il link da incollare. Come SpotifySection su Android.
struct SpotifySection: View {
    private var spotify: SpotifyService { SpotifyService.shared }
    private var settings: AppSettings { AppSettings.shared }
    @State private var link = AppSettings.shared.spotifyChoice == nil ? AppSettings.shared.spotifyURI : ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !spotify.configured {
                Text("music.spotifyMissing").appFont(.caption).foregroundStyle(.secondary)
            } else {
                account
                Text("spotify.chosen").appFont(.subheadline, weight: .semibold)
                if let choice = settings.spotifyChoice {
                    SpotifyItemRow(item: choice, selected: true)
                } else if !settings.spotifyURI.isEmpty {
                    Text(verbatim: settings.spotifyURI).appFont(.caption).foregroundStyle(.secondary).lineLimit(1)
                } else {
                    Text("spotify.noChoice").appFont(.caption).foregroundStyle(.secondary)
                }
                if spotify.loggedIn {
                    NavigationLink { SpotifyPickerView() } label: {
                        Label(settings.spotifyChoice == nil ? LocalizedStringKey("spotify.choose") : LocalizedStringKey("spotify.change"),
                              systemImage: "music.note.list")
                            .lineLimit(1).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    if settings.spotifyChoice != nil || !settings.spotifyURI.isEmpty {
                        Button("spotify.clear") { settings.setSpotifyChoice(nil) }.appFont(.footnote)
                    }
                } else {
                    linkField          // senza accesso si puo' ancora incollare il link, come su Android
                }
                Text("music.spotifyNote").appFont(.caption).foregroundStyle(.secondary)
            }
        }
        .alert("Spotify", isPresented: Binding(get: { spotify.errorKey != nil }, set: { if !$0 { spotify.errorKey = nil } })) {
            Button("OK") { spotify.errorKey = nil }
        } message: {
            Text(LocalizedStringKey(spotify.errorKey ?? ""))
        }
    }

    @ViewBuilder private var account: some View {
        if spotify.loggedIn {
            HStack(spacing: 12) {
                CoverImage(url: spotify.user?.imageURL, size: 44, round: true, placeholder: "person.fill")
                VStack(alignment: .leading, spacing: 2) {
                    Text("spotify.loggedAs").appFont(.caption).foregroundStyle(.secondary)
                    Text(verbatim: spotify.user?.name ?? "…").appFont(.headline).lineLimit(1)
                    if let user = spotify.user {
                        Text(verbatim: user.premium ? "Spotify Premium" : "Spotify Free").appFont(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Button("spotify.logout") { spotify.logout() }.appFont(.subheadline)
            }
            if let user = spotify.user, !user.premium {
                Text("spotify.freeNote").appFont(.caption).foregroundStyle(.secondary)
            }
        } else {
            Button { Task { await spotify.login() } } label: {
                Label("spotify.login", systemImage: "person.crop.circle.badge.checkmark")
                    .appFont(.headline).frame(maxWidth: .infinity).padding(.vertical, 4)
            }
            .buttonStyle(.glassProminent).tint(Theme.accent)
            .disabled(spotify.busy)
            Text("spotify.loginNote").appFont(.caption).foregroundStyle(.secondary)
        }
        if spotify.busy { ProgressView().frame(maxWidth: .infinity) }
    }

    private var linkField: some View {
        let valid = link.isEmpty || SpotifyLinks.toURI(link) != nil
        return VStack(alignment: .leading, spacing: 4) {
            TextField("music.playlist", text: $link)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onChange(of: link) { _, v in
                    let text = v.trimmingCharacters(in: .whitespaces)
                    if text.isEmpty || SpotifyLinks.toURI(text) != nil { settings.setSpotifyLink(text) }
                }
            Text(valid ? LocalizedStringKey("music.playlistHint") : LocalizedStringKey("music.playlistInvalid"))
                .appFont(.caption).foregroundStyle(valid ? Color.secondary : Color.red)
        }
    }
}

/// Scelta della musica da Spotify: le playlist dell'utente oppure la ricerca (playlist, album, brani).
/// Il tocco su un contenuto lo sceglie e torna indietro. Come SpotifyPickerScreen su Android.
struct SpotifyPickerView: View {
    private var spotify: SpotifyService { SpotifyService.shared }
    private var settings: AppSettings { AppSettings.shared }
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var playlists: [SpotifyItem]?
    @State private var loadingPlaylists = true
    @State private var results: SpotifySearchResult?
    @State private var searching = false

    private var isSearching: Bool { query.trimmingCharacters(in: .whitespaces).count >= 2 }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                ScreenHeader(symbol: "music.note.list", title: "spotify.choose", subtitle: "spotify.pickerSubtitle")
                if !spotify.loggedIn {
                    Text("spotify.needLogin").appFont(.callout).frame(maxWidth: .infinity, alignment: .leading).glassCard()
                } else {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("spotify.search", text: $query).autocorrectionDisabled()
                    }
                    .padding(12)
                    .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                    if isSearching { searchResults } else { myPlaylists }
                }
            }
            .padding(20)
        }
        .appScreen()
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard spotify.loggedIn else { return }
            playlists = await spotify.playlists()
            loadingPlaylists = false
        }
        .task(id: query) {
            // Ricerca dopo una breve pausa nella scrittura
            results = nil
            guard isSearching else { searching = false; return }
            searching = true
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            results = await spotify.search(query)
            searching = false
        }
    }

    @ViewBuilder private var myPlaylists: some View {
        if loadingPlaylists {
            ProgressView().padding()
        } else if let list = playlists, !list.isEmpty {
            section("spotify.myPlaylists", list)
        } else {
            Text("spotify.noPlaylists").appFont(.callout).frame(maxWidth: .infinity, alignment: .leading).glassCard()
        }
    }

    @ViewBuilder private var searchResults: some View {
        if searching {
            ProgressView().padding()
        } else if let r = results, !r.isEmpty {
            if !r.playlists.isEmpty { section("spotify.playlists", r.playlists) }
            if !r.albums.isEmpty { section("spotify.albums", r.albums) }
            if !r.tracks.isEmpty { section("spotify.songs", r.tracks) }
        } else {
            Text("spotify.noResults").appFont(.callout).frame(maxWidth: .infinity, alignment: .leading).glassCard()
        }
    }

    private func section(_ title: LocalizedStringKey, _ items: [SpotifyItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).appFont(.headline)
            ForEach(items) { item in
                Button {
                    settings.setSpotifyChoice(item)
                    dismiss()
                } label: {
                    SpotifyItemRow(item: item, selected: item.uri == settings.spotifyURI)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(padding: 16)
    }
}
