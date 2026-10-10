import SwiftUI

struct NowPlayingView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var scrub: Double?

    var body: some View {
        let p = app.player
        let mood = p.currentMood
        ZStack {
            // Sfondo: copertina sfocata
            Color.black.ignoresSafeArea()
            Cover(url: p.current?.largeImageURL ?? p.current?.imageURL, radius: 0)
                .scaleEffect(1.6)
                .blur(radius: 70)
                .saturation(1.6)
                .opacity(0.75)
                .ignoresSafeArea()
            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 22) {
                    header(p, mood: mood)

                    Cover(url: p.current?.largeImageURL ?? p.current?.imageURL, radius: 22)
                        .aspectRatio(1, contentMode: .fit)
                        .frame(maxWidth: 440)
                        .shadow(color: .black.opacity(0.45), radius: 30, y: 18)
                        .scaleEffect(p.isPlaying ? 1 : 0.9)
                        .animation(.spring(duration: 0.5, bounce: 0.35), value: p.isPlaying)
                        .id(p.current?.id)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))

                    titleRow(p)
                    progress(p)
                    controls(p)

                    HStack {
                        Text("Va bene con **\(mood.name)**?")
                            .font(.subheadline)
                        Spacer()
                        if let t = p.current {
                            Button { p.feedback(t, positive: false) } label: {
                                Image(systemName: "hand.thumbsdown").font(.title3)
                            }
                            .buttonStyle(.glass)
                            .buttonBorderShape(.circle)
                            Button { p.feedback(t, positive: true) } label: {
                                Image(systemName: "hand.thumbsup").font(.title3)
                            }
                            .buttonStyle(.glass)
                            .buttonBorderShape(.circle)
                        }
                    }
                    .padding(.leading, 18)
                    .padding(.trailing, 8)
                    .padding(.vertical, 8)
                    .glassEffect(.regular, in: .rect(cornerRadius: 24))

                    upNext(p)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 30)
                .animation(.smooth, value: p.current?.id)
            }
            .scrollIndicators(.hidden)
        }
        .environment(\.colorScheme, .dark)
        .task(id: p.current?.id) {
            if p.mode != .meteo { await p.loadSpotifyQueue() }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: p.current?.id) { _, _ in app.settings.haptics }
    }

    private func header(_ p: PlayerController, mood: Mood) -> some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down").font(.headline).frame(width: 24, height: 24)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            Spacer()
            VStack(spacing: 2) {
                Text(p.mode == .meteo ? "METEO MIX" : "IN RIPRODUZIONE DA")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                if p.mode == .meteo {
                    Label(mood.name, systemImage: mood.symbol)
                        .font(.footnote.weight(.semibold))
                        .symbolRenderingMode(.multicolor)
                } else {
                    Text(p.contextLabel.isEmpty ? (p.deviceName ?? "Spotify") : p.contextLabel)
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                }
            }
            Spacer()
            Button {
                if let id = p.current?.id, let u = URL(string: "https://open.spotify.com/track/\(id)") { openURL(u) }
            } label: {
                Image(systemName: "arrow.up.forward.app").font(.headline).frame(width: 24, height: 24)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
        }
        .padding(.top, 8)
    }

    private func titleRow(_ p: PlayerController) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(p.current?.name ?? "—")
                    .font(.title.weight(.bold))
                    .lineLimit(1)
                Text(p.current?.artistLine ?? "")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if let t = p.current {
                let isLiked = p.liked[t.id] == true
                Button { Task { await p.toggleLike(t) } } label: {
                    Image(systemName: isLiked ? "heart.fill" : "heart")
                        .font(.title2)
                        .foregroundStyle(isLiked ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.bounce, value: isLiked)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func progress(_ p: PlayerController) -> some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let dur = Double(max(p.durationMs, 1))
            let pos = scrub ?? Double(p.position)
            VStack(spacing: 4) {
                Slider(value: Binding(get: { pos }, set: { scrub = $0 }), in: 0...dur) { editing in
                    if !editing, let s = scrub {
                        Task { await p.seek(Int(s)) }
                        scrub = nil
                    }
                }
                HStack {
                    Text(formatTime(pos))
                    Spacer()
                    Text("-" + formatTime(dur - pos))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
    }

    private func controls(_ p: PlayerController) -> some View {
        GlassEffectContainer(spacing: 24) {
            HStack(spacing: 30) {
                Button { Task { await p.previous() } } label: {
                    Image(systemName: "backward.fill").font(.title).frame(width: 40, height: 40)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)

                Button { Task { await p.toggle() } } label: {
                    Image(systemName: p.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 34, weight: .bold))
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 62, height: 62)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)

                Button { Task { await p.next() } } label: {
                    Image(systemName: "forward.fill").font(.title).frame(width: 40, height: 40)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func upNext(_ p: PlayerController) -> some View {
        let meteo = p.mode == .meteo
        let list = meteo ? Array(p.upcoming.prefix(8)) : p.spotifyQueue
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(meteo ? "PROSSIMI NEL MIX" : "PROSSIMI IN CODA")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 6)
                ForEach(Array(list.enumerated()), id: \.offset) { i, t in
                    TrackRow(track: t, index: i, showReason: meteo) {
                        Task {
                            if meteo { await p.playAt(p.idx + 1 + i) } else { await p.playFromSpotifyQueue(t) }
                        }
                    }
                }
            }
            .padding(12)
            .glassEffect(.regular, in: .rect(cornerRadius: 24))
        }
    }
}
