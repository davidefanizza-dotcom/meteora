import Foundation
import UIKit

enum PlayMode { case none, meteo, list, context, moments }

/// Comanda la riproduzione sull'app Spotify (Spotify Connect) e gestisce la coda del Meteo Mix.
@MainActor @Observable
final class PlayerController {
    // Stato corrente
    var current: Track?
    var isPlaying = false
    var progressMs = 0
    var durationMs = 0
    var deviceName: String?
    var deviceId: String?
    var lastSync = Date()

    // Coda
    var mode: PlayMode = .none
    var queue: [Track] = []
    var idx = -1
    var mood: Mood?
    var contextLabel = ""
    var contextURI: String?
    var spotifyQueue: [Track] = []
    var building = false
    var buildProgress: (done: Int, total: Int)?

    // Momenti
    var moments: [MomentItem] = []
    var momentListId: String?
    var momentRepeat = false
    var currentMoment: MomentItem? { mode == .moments ? moments[safe: idx] : nil }
    var previewing: String?

    var liked: [String: Bool] = [:]

    @ObservationIgnored private let api: SpotifyAPI
    @ObservationIgnored private let library: LibraryStore
    @ObservationIgnored private let weather: WeatherService
    @ObservationIgnored private let settings: Settings
    @ObservationIgnored private let learn: LearnStore
    @ObservationIgnored private let analysis: AnalysisStore
    @ObservationIgnored private var momentStarted = Date.distantPast
    @ObservationIgnored private var watchTask: Task<Void, Never>?
    @ObservationIgnored private var preview: (trackId: String, end: Int)?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var queuedNextId: String?
    @ObservationIgnored private var pending: (() async -> Void)?
    @ObservationIgnored private var played = Set<String>()
    @ObservationIgnored private var advancing = false

    init(api: SpotifyAPI, library: LibraryStore, weather: WeatherService, settings: Settings, learn: LearnStore, analysis: AnalysisStore) {
        self.analysis = analysis
        self.api = api
        self.library = library
        self.weather = weather
        self.settings = settings
        self.learn = learn
    }

    /// Posizione stimata in questo istante.
    var position: Int {
        guard isPlaying else { return progressMs }
        return min(durationMs, progressMs + Int(Date().timeIntervalSince(lastSync) * 1000))
    }

    var upcoming: [Track] {
        guard mode == .meteo, idx + 1 < queue.count else { return [] }
        return Array(queue[(idx + 1)...])
    }

    var upcomingMoments: [MomentItem] {
        guard mode == .moments, idx + 1 < moments.count else { return [] }
        return Array(moments[(idx + 1)...])
    }

    var currentMood: Mood { mode == .meteo ? (mood ?? weather.mood) : weather.mood }

    // MARK: - Ciclo di aggiornamento

    func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.poll()
                var wait: Double = self.isPlaying ? 4 : 15
                if self.isPlaying, self.durationMs > 0 {
                    let left = Double(self.durationMs - self.position) / 1000
                    if left > 0 { wait = min(wait, left + 0.8) }
                }
                try? await Task.sleep(for: .seconds(wait))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func becameActive() {
        startPolling()
        if let p = pending {
            pending = nil
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                await p()
            }
        }
    }

    func poll() async {
        guard !api.isBlocked else { return }
        do {
            let s: PlaybackState? = try await api.getOptional("/me/player")
            apply(s)
        } catch {}
    }

    private func apply(_ s: PlaybackState?) {
        guard let s, let t = Track(s.item) else {
            if s == nil { isPlaying = false }
            return
        }
        let old = current
        let oldLeft = durationMs - position

        // Avanzamento della coda del Meteo Mix
        if mode == .meteo {
            if let q = queuedNextId, t.id == q {
                idx += 1
                queuedNextId = nil
            } else if let cur = queue[safe: idx], old?.id == cur.id, t.id != cur.id, oldLeft < 6000, !advancing {
                // Brano finito senza la coda pronta: passa al prossimo del mix.
                Task { await next() }
            }
        }

        current = t
        isPlaying = s.isPlaying ?? false
        progressMs = s.progressMs ?? 0
        durationMs = t.durationMs
        lastSync = Date()
        deviceId = s.device?.id
        deviceName = s.device?.name

        if old?.id != t.id { Task { await checkLiked(t.id) } }

        // Mette in coda su Spotify il prossimo brano del mix poco prima della fine.
        if mode == .meteo, isPlaying, queuedNextId == nil,
           let cur = queue[safe: idx], cur.id == t.id,
           durationMs - progressMs < 25000,
           let nxt = queue[safe: idx + 1] {
            queuedNextId = nxt.id
            Task {
                var q = ["uri": nxt.uri]
                if let d = deviceId { q["device_id"] = d }
                do { try await api.send("POST", "/me/player/queue", q) } catch { queuedNextId = nil }
            }
        }
    }

    // MARK: - Dispositivo

    private func findDevice() async -> String? {
        guard let d: DevicesResp = try? await api.get("/me/player/devices") else { return nil }
        let pick = d.devices.first { $0.isActive == true }
            ?? d.devices.first { $0.type == "Smartphone" }
            ?? d.devices.first
        return pick?.id
    }

    private func play(_ body: [String: Any]) async {
        guard let dev = await findDevice() else {
            // Nessun dispositivo: apre l'app Spotify e riprova al ritorno.
            pending = { [weak self] in await self?.play(body) }
            Toaster.shared.show("Apro Spotify: torna qui e parte la musica", symbol: "arrow.up.forward.app.fill", seconds: 4)
            if let u = URL(string: "spotify:") { await UIApplication.shared.open(u) }
            return
        }
        do {
            try await api.send("PUT", "/me/player/play", ["device_id": dev], body: body)
            queuedNextId = nil
            updateKeepAlive()
            try? await Task.sleep(for: .milliseconds(700))
            await poll()
        } catch let e as APIError where e.code == 404 {
            pending = { [weak self] in await self?.play(body) }
            Toaster.shared.show("Spotify non è attivo: lo apro io", symbol: "arrow.up.forward.app.fill")
            if let u = URL(string: "spotify:") { await UIApplication.shared.open(u) }
        } catch let e as APIError where e.code == 403 {
            Toaster.shared.show("Serve Spotify Premium per comandare la riproduzione", symbol: "exclamationmark.triangle.fill", seconds: 5)
        } catch {
            Toaster.shared.error(error)
        }
    }

    // MARK: - Comandi

    func startMix() async {
        guard library.loaded else {
            Toaster.shared.show("Sto ancora caricando la tua musica…", symbol: "music.note")
            return
        }
        building = true
        defer { building = false }
        let m = weather.mood
        let list = await MixEngine.build(mood: m, library: library, learn: learn, analysis: analysis, favPercent: settings.mixFav, played: played) { [weak self] d, t in self?.buildProgress = (d, t) }
        buildProgress = nil
        guard !list.isEmpty else {
            Toaster.shared.show("Nessun brano trovato, riprova", symbol: "exclamationmark.triangle.fill")
            return
        }
        mode = .meteo
        queue = list
        idx = -1
        mood = m
        contextLabel = "Meteo Mix · \(m.name)"
        contextURI = nil
        await playAt(0)
    }

    func regenerate() async {
        guard mode == .meteo else { await startMix(); return }
        await adapt(to: weather.mood)
        Toaster.shared.show("Coda rigenerata per \(weather.mood.name)", symbol: "arrow.clockwise")
    }

    func moodChanged(to m: Mood) {
        guard mode == .meteo, settings.autoAdapt, let old = mood, old != m else { return }
        Toaster.shared.show("Il meteo è cambiato: \(old.name) → \(m.name). Adatto la coda", symbol: m.symbol, seconds: 4.5)
        Task { await adapt(to: m) }
    }

    private func adapt(to m: Mood) async {
        building = true
        defer { building = false }
        let keep = Array(queue.prefix(max(0, idx + 1)))
        let list = await MixEngine.build(mood: m, exclude: Set(keep.map(\.id)), library: library, learn: learn,
                                         analysis: analysis, favPercent: settings.mixFav, played: played)
        queue = keep + list
        mood = m
        contextLabel = "Meteo Mix · \(m.name)"
    }

    func playAt(_ i: Int) async {
        guard let t = queue[safe: i] else { return }
        idx = i
        played.insert(t.id)
        await play(["uris": [t.uri]])
    }

    func playList(_ tracks: [Track], at i: Int, label: String) async {
        guard tracks.indices.contains(i) else { return }
        mode = .list
        queue = tracks
        idx = i
        mood = nil
        contextLabel = label
        contextURI = nil
        let start = max(0, i - 20)
        let slice = Array(tracks[start..<min(tracks.count, start + 60)])
        await play(["uris": slice.map(\.uri), "offset": ["position": i - start]])
    }

    func playContext(_ uri: String, label: String, startAt trackURI: String? = nil) async {
        mode = .context
        queue = []
        idx = -1
        mood = nil
        contextLabel = label
        contextURI = uri
        var body: [String: Any] = ["context_uri": uri]
        if let trackURI { body["offset"] = ["uri": trackURI] }
        await play(body)
    }

    func toggle() async {
        guard current != nil else {
            await startMix()
            return
        }
        let wasPlaying = isPlaying
        progressMs = position
        lastSync = Date()
        isPlaying.toggle()
        do {
            if wasPlaying {
                try await api.send("PUT", "/me/player/pause", deviceQuery)
            } else if await findDevice() == nil {
                isPlaying = false
                await play([:])
            } else {
                try await api.send("PUT", "/me/player/play", deviceQuery)
            }
        } catch {
            isPlaying = wasPlaying
            Toaster.shared.error(error)
        }
    }

    func next() async {
        if mode == .moments {
            await momentNext()
            return
        }
        advancing = true
        defer { advancing = false }
        if mode == .meteo {
            if idx + 1 >= queue.count - 3 {
                let more = await MixEngine.build(mood: weather.mood, count: 25, exclude: Set(queue.map(\.id)),
                                                 library: library, learn: learn, analysis: analysis, favPercent: settings.mixFav, played: played)
                queue += more
            }
            if queuedNextId != nil {
                // Il prossimo è già nella coda di Spotify: basta saltare.
                do { try await api.send("POST", "/me/player/next", deviceQuery) } catch { Toaster.shared.error(error) }
                try? await Task.sleep(for: .milliseconds(700))
                await poll()
                return
            }
            if idx + 1 < queue.count {
                await playAt(idx + 1)
                return
            }
        }
        do { try await api.send("POST", "/me/player/next", deviceQuery) } catch { Toaster.shared.error(error) }
        try? await Task.sleep(for: .milliseconds(700))
        await poll()
    }

    func previous() async {
        if mode == .moments, let it = currentMoment {
            if position - it.start > 3000 { await seek(it.start) } else { await playMomentAt(max(0, idx - 1)) }
            return
        }
        if position > 3000 {
            await seek(0)
            return
        }
        if mode == .meteo, idx > 0 {
            await playAt(idx - 1)
            return
        }
        do { try await api.send("POST", "/me/player/previous", deviceQuery) } catch { Toaster.shared.error(error) }
        try? await Task.sleep(for: .milliseconds(700))
        await poll()
    }

    func seek(_ ms: Int) async {
        progressMs = ms
        lastSync = Date()
        var q = deviceQuery
        q["position_ms"] = "\(ms)"
        try? await api.send("PUT", "/me/player/seek", q)
    }

    private var deviceQuery: [String: String] {
        if let d = deviceId { return ["device_id": d] }
        return [:]
    }

    func addNext(_ t: Track) async {
        if mode == .meteo {
            var x = t
            x.reason = "Aggiunto da te"
            x.mood = weather.mood
            queue.insert(x, at: min(queue.count, idx + 1))
            Toaster.shared.show("Aggiunto dopo il brano attuale", symbol: "text.line.first.and.arrowtriangle.forward")
        } else {
            var q = deviceQuery
            q["uri"] = t.uri
            do {
                try await api.send("POST", "/me/player/queue", q)
                Toaster.shared.show("Aggiunto in coda", symbol: "text.line.last.and.arrowtriangle.forward")
            } catch {
                Toaster.shared.error(error)
            }
        }
    }

    func loadSpotifyQueue() async {
        guard let r: QueueResp = try? await api.get("/me/player/queue") else { return }
        var seen = Set<String>()
        if let id = current?.id { seen.insert(id) }
        spotifyQueue = Array((r.queue ?? []).compactMap { Track($0) }.filter { seen.insert($0.id).inserted }.prefix(10))
    }

    func playFromSpotifyQueue(_ t: Track) async {
        if mode == .list, let k = queue.firstIndex(where: { $0.id == t.id }) {
            await playList(queue, at: k, label: contextLabel)
        } else if mode == .context, let ctx = contextURI {
            await playContext(ctx, label: contextLabel, startAt: t.uri)
        } else {
            await play(["uris": [t.uri]])
        }
    }

    // MARK: - Momenti

    func playMoments(_ list: MomentList, at i: Int = 0, shuffle: Bool = false) async {
        guard !list.items.isEmpty else { return }
        mode = .moments
        moments = shuffle ? list.items.shuffled() : list.items
        queue = moments.map(\.asTrack)
        momentListId = list.id
        momentRepeat = list.repeatOn ?? false
        mood = nil
        contextLabel = "Momenti · \(list.name)"
        contextURI = nil
        await playMomentAt(i)
    }

    func playMomentAt(_ i: Int) async {
        guard let it = moments[safe: i] else { return }
        idx = i
        preview = nil
        previewing = nil
        momentStarted = Date()
        await play(["uris": [it.uri], "position_ms": it.start])
        ensureWatcher()
    }

    private func momentNext() async {
        guard !advancing else { return }
        advancing = true
        defer { advancing = false }
        var n = idx + 1
        if n >= moments.count {
            if momentRepeat {
                n = 0
            } else {
                if isPlaying { await toggle() }
                Toaster.shared.show("Fine dei momenti", symbol: "scissors")
                mode = .list
                updateKeepAlive()
                return
            }
        }
        await playMomentAt(n)
    }

    /// Anteprima dall'editor: suona il brano da `start` e si ferma a `end`.
    func previewMoment(_ t: Track, start: Int, end: Int) async {
        if mode == .moments { mode = .list }
        preview = (t.id, end)
        previewing = t.id
        momentStarted = Date()
        await play(["uris": [t.uri], "position_ms": start])
        ensureWatcher()
    }

    private func ensureWatcher() {
        guard watchTask == nil else { return }
        watchTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.mode != .moments && self.preview == nil {
                    self.watchTask = nil
                    return
                }
                await self.watchStep()
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    private func watchStep() async {
        guard isPlaying, let cur = current else { return }
        let since = Date().timeIntervalSince(momentStarted)
        guard since > 1.5 else { return }
        let pos = position
        if let p = preview, cur.id == p.trackId, pos >= p.end {
            preview = nil
            previewing = nil
            await toggle()
            return
        }
        guard mode == .moments, !advancing, let it = currentMoment else { return }
        if cur.id != it.trackId {
            if since > 8 {
                mode = .list
                updateKeepAlive()
            }
            return
        }
        if pos >= it.end - 150 { await momentNext() }
    }

    /// A schermo bloccato l'app resta attiva solo per Meteo Mix e Momenti (se l'opzione è attiva).
    func updateKeepAlive() {
        if settings.keepAwake && (mode == .meteo || mode == .moments) {
            KeepAlive.shared.start()
        } else {
            KeepAlive.shared.stop()
        }
    }

    var keepsRunningInBackground: Bool { settings.keepAwake && (mode == .meteo || mode == .moments) }

    // MARK: - Mi piace e gusti per meteo

    func checkLiked(_ id: String) async {
        let uri = "spotify:track:\(id)"
        if let r: [Bool] = try? await api.get("/me/library/contains", ["uris": uri]) {
            liked[id] = r.first ?? false
        }
    }

    func toggleLike(_ t: Track) async {
        let on = !(liked[t.id] ?? false)
        liked[t.id] = on
        do {
            try await api.send(on ? "PUT" : "DELETE", "/me/library", ["uris": t.uri])
            Toaster.shared.show(on ? "Aggiunto ai brani che ti piacciono" : "Rimosso dai preferiti", symbol: on ? "heart.fill" : "heart.slash")
        } catch {
            liked[t.id] = !on
            Toaster.shared.error(error)
        }
    }

    func feedback(_ t: Track, positive: Bool) {
        let m = t.mood ?? currentMood
        learn.feedback(t, mood: m, positive: positive)
        if positive {
            Toaster.shared.show("Segnato: perfetto con \(m.name)", symbol: "hand.thumbsup.fill")
            return
        }
        Toaster.shared.show("Non lo proporrò più con \(m.name)", symbol: "hand.thumbsdown.fill")
        guard mode == .meteo, let i = queue.firstIndex(where: { $0.id == t.id }) else { return }
        if i == idx {
            Task { await next() }
        } else if i > idx {
            queue.remove(at: i)
        }
    }

    func reset() {
        stopPolling()
        KeepAlive.shared.stop()
        current = nil
        isPlaying = false
        mode = .none
        queue = []
        idx = -1
    }
}
