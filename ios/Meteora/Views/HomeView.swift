import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var app

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 0..<6: return "Buonanotte"
        case 6..<13: return "Buongiorno"
        case 13..<18: return "Buon pomeriggio"
        default: return "Buonasera"
        }
    }

    var body: some View {
        let lib = app.library
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                WeatherCard()

                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(title: "I tuoi brani del momento")
                    if !lib.loaded {
                        ProgressView().frame(maxWidth: .infinity, minHeight: 160)
                    } else if lib.topShort.isEmpty {
                        Text("Ascolta un po' di musica e qui compariranno i tuoi preferiti.")
                            .foregroundStyle(.secondary)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: 16) {
                                ForEach(Array(lib.topShort.prefix(14).enumerated()), id: \.offset) { i, t in
                                    TrackCard(track: t) {
                                        Task { await app.player.playList(lib.topShort, at: i, label: "I tuoi brani del momento") }
                                    }
                                }
                            }
                            .scrollTargetLayout()
                        }
                        .scrollTargetBehavior(.viewAligned)
                        .scrollClipDisabled()
                    }
                }

                if !lib.recent.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "Ascoltati di recente")
                        let rec = Array(lib.recent.prefix(8))
                        ForEach(Array(rec.enumerated()), id: \.offset) { i, t in
                            TrackRow(track: t, index: i) {
                                Task { await app.player.playList(rec, at: i, label: "Ascoltati di recente") }
                            }
                        }
                    }
                }

                if !lib.playlists.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader(title: "Le tue playlist")
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: 16) {
                                ForEach(lib.playlists.prefix(14)) { p in
                                    NavigationLink(value: p) {
                                        PlaylistCard(playlist: p, mine: lib.isMine(p))
                                            .frame(width: 150)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .scrollTargetLayout()
                        }
                        .scrollTargetBehavior(.viewAligned)
                        .scrollClipDisabled()
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .background(WeatherBackground())
        .navigationTitle(greeting)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Impostazioni", systemImage: "gearshape") { app.showSettings = true }
            }
        }
        .navigationDestination(for: Playlist.self) { PlaylistView(playlist: $0) }
        .refreshable {
            await app.weather.refresh()
            await app.library.load()
        }
    }
}

struct WeatherCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let w = app.weather
        let m = w.mood
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                Image(systemName: m.symbol)
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 52))
                    .symbolEffect(.breathe, options: .repeating)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 64)
                VStack(alignment: .leading, spacing: 3) {
                    Label(w.place, systemImage: "location.fill")
                        .font(.caption.weight(.bold))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                    Text(w.temp.map { "\(m.name) · \($0)°" } ?? m.name)
                        .font(.title2.weight(.bold))
                        .contentTransition(.numericText())
                    Text(m.desc)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Button {
                app.tab = .meteo
                Task { await app.player.startMix() }
            } label: {
                Label("Meteo Mix", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .disabled(app.player.building)
        }
        .padding(20)
        .glassEffect(.regular.tint(m.color.opacity(0.18)), in: .rect(cornerRadius: 28))
        .animation(.smooth, value: m)
    }
}

struct TrackCard: View {
    let track: Track
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Cover(url: track.imageURL, radius: 14)
                    .frame(width: 150, height: 150)
                    .shadow(color: .black.opacity(0.25), radius: 10, y: 6)
                Text(track.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(track.artistLine).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(width: 150, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}

struct PlaylistCard: View {
    let playlist: Playlist
    let mine: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Cover(url: playlist.cover, radius: 14)
                .aspectRatio(1, contentMode: .fit)
                .shadow(color: .black.opacity(0.25), radius: 10, y: 6)
            Text(playlist.name).font(.subheadline.weight(.semibold)).lineLimit(1)
            Text(mine ? "\(playlist.count ?? 0) brani" : "Seguita · \(playlist.owner?.displayName ?? "")")
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}
