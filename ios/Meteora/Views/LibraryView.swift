import SwiftUI

struct LibraryView: View {
    @Environment(AppModel.self) private var app
    private let cols = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    var body: some View {
        @Bindable var settings = app.settings
        let lib = app.library
        let f = settings.libFilter
        let lists = lib.playlists.filter { f == 0 || (f == 1) == lib.isMine($0) }
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Picker("Filtro", selection: $settings.libFilter) {
                    Text("Tutte").tag(0)
                    Text("Create da te").tag(1)
                    Text("Seguite").tag(2)
                }
                .pickerStyle(.segmented)

                if !lib.loaded {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 200)
                } else if lib.playlists.isEmpty, let err = lib.error {
                    VStack(spacing: 14) {
                        EmptyState(symbol: "exclamationmark.triangle", title: "Playlist non caricate", message: err)
                        Button("Riprova", systemImage: "arrow.clockwise") { Task { await lib.load() } }
                            .buttonStyle(.glass)
                    }
                } else {
                    LazyVGrid(columns: cols, alignment: .leading, spacing: 20) {
                        if f != 2 {
                            NavigationLink {
                                SavedView()
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(LinearGradient(colors: [app.weather.mood.color, app.weather.mood.color2],
                                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                                        .aspectRatio(1, contentMode: .fit)
                                        .overlay(Image(systemName: "heart.fill").font(.system(size: 44)).foregroundStyle(.white))
                                        .shadow(color: .black.opacity(0.25), radius: 10, y: 6)
                                    Text("Brani che ti piacciono").font(.subheadline.weight(.semibold)).lineLimit(1)
                                    Text("\(lib.saved.count)\(lib.savedHasMore ? "+" : "") brani").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        ForEach(lists) { p in
                            NavigationLink(value: p) {
                                PlaylistCard(playlist: p, mine: lib.isMine(p))
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Riproduci", systemImage: "play.fill") {
                                    Task { await app.player.playContext(p.uri, label: p.name) }
                                }
                            }
                        }
                    }
                    if lists.isEmpty && f != 0 {
                        VStack(spacing: 12) {
                            EmptyState(symbol: "square.stack", title: "Nessuna playlist qui")
                            Button("Mostra tutte") { settings.libFilter = 0 }.buttonStyle(.glass)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .background(WeatherBackground())
        .navigationTitle("Libreria")
        .navigationDestination(for: Playlist.self) { PlaylistView(playlist: $0) }
        .refreshable { await lib.load() }
    }
}

struct PlaylistView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    let playlist: Playlist

    @State private var tracks: [Track] = []
    @State private var total = 0
    @State private var loading = false
    @State private var locked = false
    @State private var errorText: String?

    var body: some View {
        let mine = app.library.isMine(playlist)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(spacing: 14) {
                    Cover(url: playlist.images?.best(640), radius: 20)
                        .frame(width: 220, height: 220)
                        .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
                    Text(playlist.name).font(.title.weight(.bold)).multilineTextAlignment(.center)
                    Text((playlist.owner?.displayName ?? "") + (mine ? " · \(playlist.count ?? 0) brani" : " · Seguita"))
                        .font(.subheadline).foregroundStyle(.secondary)
                    GlassEffectContainer(spacing: 12) {
                        HStack(spacing: 12) {
                            Button {
                                Task { await app.player.playContext(playlist.uri, label: playlist.name) }
                            } label: {
                                Label("Riproduci", systemImage: "play.fill").font(.headline).padding(.horizontal, 10).padding(.vertical, 4)
                            }
                            .buttonStyle(.glassProminent)
                            if let s = playlist.externalUrls?.spotify, let u = URL(string: s) {
                                Button { openURL(u) } label: {
                                    Image(systemName: "arrow.up.forward.app").font(.headline).padding(.vertical, 4)
                                }
                                .buttonStyle(.glass)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 10)

                if locked || !mine {
                    EmptyState(symbol: "lock.fill", title: "Elenco brani non disponibile",
                               message: "Spotify mostra i brani solo delle playlist create da te o di cui sei collaboratore. Questa la puoi comunque riprodurre con il tasto sopra.")
                } else if let errorText {
                    EmptyState(symbol: "exclamationmark.triangle", title: "Non riesco a caricare i brani", message: errorText)
                } else if tracks.isEmpty && loading {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(tracks.enumerated()), id: \.offset) { i, t in
                            TrackRow(track: t, index: i) {
                                Task { await app.player.playContext(playlist.uri, label: playlist.name, startAt: t.uri) }
                            }
                        }
                    }
                    if tracks.count < total {
                        Button("Carica altri", systemImage: "plus") { Task { await load() } }
                            .buttonStyle(.glass)
                            .frame(maxWidth: .infinity)
                            .disabled(loading)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .background(WeatherBackground())
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if mine && tracks.isEmpty { await load() }
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let r = try await app.library.playlistTracks(playlist, offset: tracks.count)
            tracks += r.tracks
            total = r.total
        } catch let e as APIError where e.code == 403 {
            locked = true
        } catch {
            errorText = error.localizedDescription
        }
    }
}

struct SavedView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let lib = app.library
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(lib.saved.enumerated()), id: \.offset) { i, t in
                    TrackRow(track: t, index: i) {
                        Task { await app.player.playList(lib.saved, at: i, label: "Brani che ti piacciono") }
                    }
                }
                if lib.savedHasMore {
                    Button("Carica altri", systemImage: "plus") { Task { await lib.loadMoreSaved() } }
                        .buttonStyle(.glass)
                        .padding(.top, 12)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .background(WeatherBackground())
        .navigationTitle("Brani che ti piacciono")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Riproduci", systemImage: "play.fill") {
                    Task { await app.player.playList(lib.saved, at: 0, label: "Brani che ti piacciono") }
                }
                .disabled(lib.saved.isEmpty)
            }
        }
    }
}

struct SearchView: View {
    @Environment(AppModel.self) private var app
    @State private var query = ""
    @State private var results: [Track] = []
    @State private var loading = false
    @State private var hasMore = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    EmptyState(symbol: "magnifyingglass", title: "Cerca qualcosa da ascoltare",
                               message: "Brani, artisti o album")
                        .padding(.top, 30)
                } else if results.isEmpty && !loading {
                    EmptyState(symbol: "music.note", title: "Nessun risultato")
                        .padding(.top, 30)
                } else {
                    ForEach(Array(results.enumerated()), id: \.offset) { i, t in
                        TrackRow(track: t, index: i) {
                            Task { await app.player.playList(results, at: i, label: "Ricerca: \(query)") }
                        }
                    }
                    if hasMore {
                        Button("Altri risultati", systemImage: "plus") { Task { await search(reset: false) } }
                            .buttonStyle(.glass)
                            .padding(.top, 12)
                            .disabled(loading)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .background(WeatherBackground())
        .navigationTitle("Cerca")
        .searchable(text: $query, prompt: "Brani, artisti, album")
        .task(id: query) {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await search(reset: true)
        }
        .overlay {
            if loading && results.isEmpty { ProgressView() }
        }
    }

    private func search(reset: Bool) async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else {
            results = []
            return
        }
        loading = true
        defer { loading = false }
        do {
            let r = try await app.library.search(q, offset: reset ? 0 : results.count)
            results = reset ? r : results + r
            hasMore = r.count == 10 && results.count < 100
        } catch {
            Toaster.shared.error(error)
        }
    }
}
