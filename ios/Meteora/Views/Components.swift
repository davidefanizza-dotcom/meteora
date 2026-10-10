import SwiftUI

/// Copertina con cache (URLCache condivisa).
struct Cover: View {
    let url: URL?
    var radius: CGFloat = 10

    var body: some View {
        AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.25))) { phase in
            switch phase {
            case .success(let img):
                img.resizable().scaledToFill()
            default:
                Rectangle().fill(.quaternary)
                    .overlay(Image(systemName: "music.note").foregroundStyle(.secondary))
            }
        }
        .clipShape(.rect(cornerRadius: radius))
    }
}

/// Sfondo animato in base al meteo.
struct WeatherBackground: View {
    @Environment(AppModel.self) private var app
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let m = app.weather.mood
        ZStack {
            (scheme == .dark ? Color.black : Color(white: 0.96))
            RadialGradient(colors: [m.color.opacity(scheme == .dark ? 0.55 : 0.35), .clear],
                           center: .topLeading, startRadius: 10, endRadius: 520)
            RadialGradient(colors: [m.color2.opacity(scheme == .dark ? 0.45 : 0.3), .clear],
                           center: .bottomTrailing, startRadius: 10, endRadius: 560)
            if app.settings.animateWeather && !reduceMotion {
                WeatherParticles(mood: m, dark: scheme == .dark)
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 1.2), value: m)
    }
}

struct WeatherParticles: View {
    let mood: Mood
    let dark: Bool

    private struct P { let x, y, speed, size, phase: Double }
    private static let seeds: [P] = (0..<140).map { _ in
        P(x: .random(in: 0...1), y: .random(in: 0...1), speed: .random(in: 0.5...1.5),
          size: .random(in: 0.4...1.6), phase: .random(in: 0...6.28))
    }

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSinceReferenceDate
                let ink: Color = dark ? .white : Color(red: 0.2, green: 0.3, blue: 0.5)
                let W = size.width, H = size.height
                switch mood {
                case .pioggia, .temporale:
                    let n = mood == .temporale ? 140 : 100
                    for p in Self.seeds.prefix(n) {
                        let y = (p.y * (H + 60) + t * 420 * p.speed).truncatingRemainder(dividingBy: H + 60) - 30
                        let x = (p.x * (W + 80) - y * 0.22).truncatingRemainder(dividingBy: W + 80)
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: y))
                        path.addLine(to: CGPoint(x: x - 4 * p.size, y: y + 16 * p.size))
                        ctx.stroke(path, with: .color(ink.opacity(0.12 + 0.2 * p.size / 1.6)), lineWidth: 1.2)
                    }
                    if mood == .temporale {
                        let cycle = t.truncatingRemainder(dividingBy: 7)
                        if cycle < 0.12 || (cycle > 0.22 && cycle < 0.3) {
                            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.purple.opacity(0.12)))
                        }
                    }
                case .neve:
                    for p in Self.seeds.prefix(110) {
                        let y = (p.y * (H + 20) + t * 40 * p.speed).truncatingRemainder(dividingBy: H + 20) - 10
                        let x = p.x * W + sin(t * 0.8 + p.phase) * 14
                        let r = 1.2 + p.size * 1.5
                        ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r * 2, height: r * 2)),
                                 with: .color((dark ? Color.white : Color(red: 0.5, green: 0.6, blue: 0.8)).opacity(0.7)))
                    }
                case .notte:
                    for p in Self.seeds.prefix(120) {
                        let a = 0.25 + 0.6 * abs(sin(t * p.speed + p.phase))
                        let r = 0.5 + p.size * 0.8
                        ctx.fill(Path(ellipseIn: CGRect(x: p.x * W, y: p.y * H * 0.85, width: r * 2, height: r * 2)),
                                 with: .color(ink.opacity(a)))
                    }
                case .vento:
                    for p in Self.seeds.prefix(36) {
                        let len = 60 + p.size * 90
                        let x = (p.x * (W + 400) + t * 260 * p.speed).truncatingRemainder(dividingBy: W + 400) - 200
                        let y = p.y * H
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: y))
                        path.addQuadCurve(to: CGPoint(x: x + len, y: y), control: CGPoint(x: x + len / 2, y: y - 6))
                        ctx.stroke(path, with: .linearGradient(Gradient(colors: [ink.opacity(0), ink.opacity(0.18), ink.opacity(0)]),
                                                               startPoint: CGPoint(x: x, y: y), endPoint: CGPoint(x: x + len, y: y)),
                                   lineWidth: 1.4)
                    }
                case .nuvoloso, .nebbia:
                    let n = mood == .nebbia ? 7 : 5
                    for p in Self.seeds.prefix(n) {
                        let r = 180 + p.size * 160
                        let x = (p.x * (W + 2 * r) + t * 10 * p.speed).truncatingRemainder(dividingBy: W + 2 * r) - r
                        let y = (mood == .nebbia ? 0.35 + p.y * 0.65 : p.y * 0.6) * H
                        ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                                 with: .radialGradient(Gradient(colors: [ink.opacity(mood == .nebbia ? 0.08 : 0.06), ink.opacity(0)]),
                                                       center: CGPoint(x: x, y: y), startRadius: 0, endRadius: r))
                    }
                case .sole, .caldo:
                    let col: Color = mood == .caldo ? Color(red: 1, green: 0.55, blue: 0.3) : Color(red: 1, green: 0.82, blue: 0.47)
                    for p in Self.seeds.prefix(34) {
                        let y = (p.y * (H + 20) - t * 18 * p.speed).truncatingRemainder(dividingBy: H + 20)
                        let yy = y < 0 ? y + H + 20 : y
                        let x = p.x * W + sin(t * 0.5 + p.phase) * 10
                        let r = 1 + p.size * 1.6
                        ctx.fill(Path(ellipseIn: CGRect(x: x, y: yy, width: r * 2, height: r * 2)),
                                 with: .color(col.opacity(0.25 + 0.35 * abs(sin(t + p.phase)))))
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Riga brano con menu, feedback per meteo ed equalizzatore sul brano attivo.
struct TrackRow: View {
    @Environment(AppModel.self) private var app
    let track: Track
    let index: Int
    var showReason = false
    var showFeedback = false
    var dimmed = false
    let onPlay: () -> Void

    var body: some View {
        let p = app.player
        let isCurrent = p.current?.id == track.id
        HStack(spacing: 12) {
            ZStack {
                if isCurrent {
                    Image(systemName: "waveform")
                        .symbolEffect(.variableColor.iterative, isActive: p.isPlaying)
                        .foregroundStyle(.tint)
                } else {
                    Text("\(index + 1)").foregroundStyle(.secondary).monospacedDigit()
                }
            }
            .font(.footnote)
            .frame(width: 24)

            Cover(url: track.imageURL, radius: 6)
                .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if showReason, let r = track.reason {
                        Text(r)
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(.tint.opacity(r == "Preferito" || r == "Tuo artista" ? 0.12 : 0.22), in: .capsule)
                    }
                    Text(track.artistLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)

            if showFeedback {
                Button { p.feedback(track, positive: false) } label: {
                    Image(systemName: "hand.thumbsdown")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                Button { p.feedback(track, positive: true) } label: {
                    Image(systemName: "hand.thumbsup")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }

            Menu {
                TrackMenu(track: track, onPlay: onPlay)
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 30, height: 36)
                    .contentShape(.rect)
            }
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .opacity(dimmed ? 0.45 : 1)
        .contentShape(.rect)
        .onTapGesture {
            if isCurrent { Task { await p.toggle() } } else { onPlay() }
        }
        .contextMenu {
            TrackMenu(track: track, onPlay: onPlay)
        } preview: {
            VStack(alignment: .leading, spacing: 8) {
                Cover(url: track.largeImageURL ?? track.imageURL, radius: 12).frame(width: 260, height: 260)
                Text(track.name).font(.headline)
                Text(track.artistLine).foregroundStyle(.secondary)
            }
            .padding()
        }
    }
}

struct TrackMenu: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    let track: Track
    let onPlay: () -> Void

    var body: some View {
        let p = app.player
        let m = p.currentMood
        Button("Riproduci", systemImage: "play.fill", action: onPlay)
        Button("Riproduci dopo", systemImage: "text.line.first.and.arrowtriangle.forward") {
            Task { await p.addNext(track) }
        }
        Divider()
        Button("Perfetta con \(m.name)", systemImage: "hand.thumbsup") { p.feedback(track, positive: true) }
        Button("Non con \(m.name)", systemImage: "hand.thumbsdown") { p.feedback(track, positive: false) }
        Divider()
        Button(p.liked[track.id] == true ? "Togli da Mi piace" : "Aggiungi a Mi piace",
               systemImage: p.liked[track.id] == true ? "heart.slash" : "heart") {
            Task { await p.toggleLike(track) }
        }
        Button("Apri su Spotify", systemImage: "arrow.up.forward.app") {
            if let u = URL(string: "https://open.spotify.com/track/\(track.id)") { openURL(u) }
        }
    }
}

struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.title2.weight(.bold))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    var message: String? = nil

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 40))
                .foregroundStyle(.tint)
                .symbolEffect(.breathe)
            Text(title).font(.headline)
            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }
}
