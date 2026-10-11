import Foundation

/// Genere e BPM dei brani, ricavati da servizi gratuiti:
/// - Deezer: BPM del brano (via codice ISRC) e genere dell'album
/// - MusicBrainz: generi dell'artista (più precisi)
/// Spotify non fornisce più questi dati alle app personali.
struct TrackInfo: Codable, Hashable {
    var bpm: Int
    var genre: String
}

enum GenreProfile {
    static let italian: [String: String] = [
        "Pop": "Pop", "Rap/Hip Hop": "Hip hop", "Reggaeton": "Reggaeton", "Rock": "Rock", "Dance": "Dance",
        "R&B": "R&B", "Alternative": "Indie", "Christian": "Cristiana", "Electro": "Elettronica", "Folk": "Folk",
        "Reggae": "Reggae", "Jazz": "Jazz", "Country": "Country", "Salsa": "Salsa", "Traditional Mexicano": "Messicana",
        "Classical": "Classica", "Films/Games": "Colonne sonore", "Metal": "Metal", "Soul & Funk": "Soul & Funk",
        "African Music": "Afro", "Asian Music": "Asiatica", "Blues": "Blues", "Brazilian Music": "Brasiliana",
        "Cumbia": "Cumbia", "Indian Music": "Indiana", "Kids": "Bambini", "Latin Music": "Latina"
    ]

    static let query: [String: String] = [
        "Pop": "pop", "Rap/Hip Hop": "hip hop", "Reggaeton": "reggaeton", "Rock": "rock", "Dance": "dance",
        "R&B": "r&b", "Alternative": "indie", "Electro": "electronic", "Folk": "folk", "Reggae": "reggae",
        "Jazz": "jazz", "Country": "country", "Salsa": "salsa", "Classical": "piano", "Films/Games": "soundtrack",
        "Metal": "metal", "Soul & Funk": "soul", "African Music": "afrobeats", "Blues": "blues",
        "Brazilian Music": "bossa nova", "Cumbia": "cumbia", "Latin Music": "latin"
    ]

    struct P {
        let bpm: ClosedRange<Double>
        let flavors: [String]
        let weights: [String: Double]
    }

    /// Per ogni meteo: BPM ideali e quanto è adatto ogni genere (negativo = da evitare).
    static func profile(_ m: Mood) -> P {
        switch m {
        case .sole: P(bpm: 100...130, flavors: ["summer", "happy", "sunny", "feel good"],
                      weights: ["Pop": 2, "Dance": 2, "Soul & Funk": 2, "Reggaeton": 1.5, "Latin Music": 1.5, "Reggae": 1.5, "Brazilian Music": 1, "Electro": 1, "Rap/Hip Hop": 0.5, "Rock": 0.5, "Alternative": 0.5, "Metal": -2, "Classical": -1.5, "Blues": -0.5])
        case .caldo: P(bpm: 90...125, flavors: ["summer", "tropical", "beach", "party"],
                       weights: ["Reggaeton": 3, "Latin Music": 2.5, "Salsa": 2, "Cumbia": 2, "Reggae": 2, "Brazilian Music": 2, "African Music": 2, "Dance": 1.5, "Pop": 1, "Soul & Funk": 1, "Rap/Hip Hop": 0.5, "Metal": -2, "Classical": -2, "Folk": -1, "Blues": -1])
        case .nuvoloso: P(bpm: 75...110, flavors: ["chill", "mellow", "soft", "calm"],
                          weights: ["Alternative": 2, "Pop": 1.5, "Folk": 1.5, "R&B": 1.5, "Soul & Funk": 1, "Electro": 1, "Jazz": 1, "Rap/Hip Hop": 0.5, "Metal": -1.5, "Reggaeton": -1, "Salsa": -1, "Dance": -0.5])
        case .pioggia: P(bpm: 60...95, flavors: ["rainy day", "acoustic", "sad", "slow"],
                         weights: ["Folk": 2.5, "Alternative": 2, "Jazz": 2, "Classical": 2, "R&B": 2, "Blues": 2, "Soul & Funk": 1.5, "Films/Games": 1, "Pop": 0.5, "Dance": -2, "Reggaeton": -2.5, "Latin Music": -1.5, "Salsa": -2, "Cumbia": -2, "Brazilian Music": -1, "Metal": -1.5, "African Music": -1])
        case .temporale: P(bpm: 110...170, flavors: ["epic", "intense", "dark", "power"],
                           weights: ["Rock": 3, "Metal": 3, "Films/Games": 2, "Rap/Hip Hop": 1.5, "Electro": 1.5, "Alternative": 1.5, "Reggaeton": -1.5, "Folk": -1, "Jazz": -1, "Latin Music": -1.5, "Salsa": -2, "Cumbia": -2])
        case .neve: P(bpm: 60...100, flavors: ["winter", "cozy", "calm", "warm"],
                      weights: ["Classical": 3, "Jazz": 2, "Folk": 2, "Films/Games": 1.5, "Soul & Funk": 1, "Blues": 1, "Pop": 1, "Alternative": 1, "Dance": -2, "Reggaeton": -2, "Metal": -2, "Latin Music": -1.5, "Salsa": -2])
        case .nebbia: P(bpm: 55...100, flavors: ["ambient", "dreamy", "atmospheric", "ethereal"],
                        weights: ["Films/Games": 2.5, "Electro": 2, "Alternative": 2, "Classical": 2, "Folk": 1, "Jazz": 1, "Pop": 0.3, "Dance": -2, "Reggaeton": -2.5, "Latin Music": -2, "Salsa": -2, "Metal": -1])
        case .notte: P(bpm: 70...115, flavors: ["night", "late night", "midnight", "city lights"],
                       weights: ["R&B": 3, "Electro": 2, "Rap/Hip Hop": 2, "Soul & Funk": 1.5, "Jazz": 1.5, "Pop": 1, "Dance": 1, "Alternative": 1, "Folk": -1, "Country": -1.5, "Salsa": -1])
        case .vento: P(bpm: 100...140, flavors: ["road trip", "driving", "free", "highway"],
                       weights: ["Rock": 2.5, "Alternative": 2.5, "Pop": 1.5, "Country": 1.5, "Folk": 1.5, "Electro": 1, "Dance": 0.5, "Classical": -1, "Reggaeton": -0.5])
        }
    }

    /// Etichette MusicBrainz → famiglie di genere.
    static let tagMap: [(NSRegularExpression, String)] = [
        ("reggaeton|urbano|dembow", "Reggaeton"), ("salsa", "Salsa"), ("cumbia", "Cumbia"),
        ("latin|bachata|merengue|spanish pop", "Latin Music"), ("metal", "Metal"),
        ("hip hop|hip-hop|\\brap\\b|trap|drill|grime", "Rap/Hip Hop"), ("r&b|rnb|rhythm and blues|neo soul", "R&B"),
        ("soul|funk|disco|motown", "Soul & Funk"), ("house|techno|edm|eurodance|trance|\\bdance\\b|club", "Dance"),
        ("electronic|electronica|ambient|synthwave|downtempo|trip hop|lo-fi|lofi|chillout|idm|synth", "Electro"),
        ("alternative|indie|shoegaze|dream pop|post-rock|emo\\b|grunge", "Alternative"), ("punk|rock", "Rock"),
        ("folk|singer-songwriter|singer songwriter|acoustic|cantautor", "Folk"), ("jazz|swing|bossa", "Jazz"),
        ("classical|composer|orchestral|opera|^baroque$|romantic era|^piano$", "Classical"), ("blues", "Blues"),
        ("country|americana|bluegrass", "Country"), ("reggae|dancehall|\\bska\\b", "Reggae"),
        ("afrobeat|amapiano|^afro", "African Music"), ("soundtrack|film score|video game|\\bscore\\b", "Films/Games"),
        ("k-pop|j-pop|c-pop|anime", "Asian Music"), ("brazil|\\bmpb\\b|samba|forr[oó]", "Brazilian Music"),
        ("\\bpop\\b", "Pop")
    ].compactMap { p, g in (try? NSRegularExpression(pattern: p, options: [.caseInsensitive])).map { ($0, g) } }
}

@MainActor
private final class Counter {
    var next = 0, finished = 0, fails = 0, extra = 0
}

@MainActor @Observable
final class AnalysisStore {
    private(set) var tracks: [String: TrackInfo] = [:]
    private(set) var albums: [Int: String] = [:]
    private(set) var artists: [String: [String: Double]] = [:]
    var busy = false
    var done = 0
    var total = 0

    @ObservationIgnored private var dzStamps: [Date] = []
    @ObservationIgnored private var mbLast = Date.distantPast
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    private struct Disk: Codable {
        var tracks: [String: TrackInfo]
        var albums: [Int: String]
        var artists: [String: [String: Double]]
    }

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("analisi.json")
    }

    init() {
        if let d = try? Data(contentsOf: Self.fileURL), let disk = try? JSONDecoder().decode(Disk.self, from: d) {
            tracks = disk.tracks
            albums = disk.albums
            artists = disk.artists
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            let disk = Disk(tracks: tracks, albums: albums, artists: artists)
            if let d = try? JSONEncoder().encode(disk) { try? d.write(to: Self.fileURL, options: .atomic) }
        }
    }

    // MARK: - Rete

    private func deezer(_ path: String, retry: Int = 0) async throws -> [String: Any]? {
        // Massimo 40 richieste ogni 5 secondi.
        while true {
            let now = Date()
            dzStamps = dzStamps.filter { now.timeIntervalSince($0) < 5 }
            if dzStamps.count < 40 { break }
            try await Task.sleep(for: .seconds(5 - now.timeIntervalSince(dzStamps[0]) + 0.05))
        }
        dzStamps.append(Date())
        guard let url = URL(string: "https://api.deezer.com" + path) else { return nil }
        let (data, _) = try await URLSession.shared.data(from: url)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let err = obj?["error"] as? [String: Any] {
            if (err["code"] as? Int) == 4 && retry < 3 {
                try await Task.sleep(for: .seconds(2.5))
                return try await deezer(path, retry: retry + 1)
            }
            return nil
        }
        return obj
    }

    private func musicBrainz(_ name: String) async throws -> [String: Any]? {
        let wait = 1.15 - Date().timeIntervalSince(mbLast)
        if wait > 0 { try await Task.sleep(for: .seconds(wait)) }
        mbLast = Date()
        var c = URLComponents(string: "https://musicbrainz.org/ws/2/artist/")!
        c.queryItems = [URLQueryItem(name: "fmt", value: "json"), URLQueryItem(name: "limit", value: "3"),
                        URLQueryItem(name: "query", value: "artist:\"\(name.replacingOccurrences(of: "\"", with: ""))\"")]
        var req = URLRequest(url: c.url!)
        req.setValue("Meteora/1.0 (https://davidefanizza-dotcom.github.io/meteora)", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        if (resp as? HTTPURLResponse)?.statusCode == 503 {
            try await Task.sleep(for: .seconds(2))
            return try await musicBrainz(name)
        }
        return try JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    // MARK: - Analisi

    private static func cleanTitle(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "\\s*[\\(\\[].*?[\\)\\]]", with: "", options: .regularExpression)
        if let r = t.range(of: " - ") { t = String(t[..<r.lowerBound]) }
        return t.trimmingCharacters(in: .whitespaces)
    }

    private func analyzeTrack(_ t: Track) async throws {
        if tracks[t.id] != nil { return }
        var d: [String: Any]?
        if let isrc = t.isrc, !isrc.isEmpty {
            d = try await deezer("/track/isrc:\(isrc.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? isrc)")
        }
        if d?["id"] == nil {
            let artist = t.artists.first?.name ?? ""
            let title = Self.cleanTitle(t.name)
            let q = "\(artist) \(title)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            if let sr = try await deezer("/search/track?limit=5&q=\(q)"),
               let list = sr["data"] as? [[String: Any]] {
                let a6 = String(artist.lowercased().prefix(6)), t8 = String(title.lowercased().prefix(8))
                let hit = list.first {
                    (($0["artist"] as? [String: Any])?["name"] as? String ?? "").lowercased().contains(a6) &&
                    ($0["title"] as? String ?? "").lowercased().contains(t8)
                }
                if let id = hit?["id"] as? Int { d = try await deezer("/track/\(id)") }
            }
        }
        var info = TrackInfo(bpm: 0, genre: "")
        if let d, d["id"] != nil {
            info.bpm = Int(((d["bpm"] as? Double) ?? Double(d["bpm"] as? Int ?? 0)).rounded())
            if let albumId = (d["album"] as? [String: Any])?["id"] as? Int {
                if albums[albumId] == nil {
                    let a = try await deezer("/album/\(albumId)")
                    let names = ((a?["genres"] as? [String: Any])?["data"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
                    albums[albumId] = names.first { $0 != "All" } ?? ""
                }
                info.genre = albums[albumId] ?? ""
            }
        }
        tracks[t.id] = info
    }

    private func analyzeArtist(_ a: ArtistRef) async throws {
        guard !a.id.isEmpty, artists[a.id] == nil else { return }
        let j = try await musicBrainz(a.name)
        let list = j?["artists"] as? [[String: Any]] ?? []
        let low = a.name.lowercased()
        let match = list.first { ($0["name"] as? String)?.lowercased() == low && ($0["score"] as? Int ?? 0) >= 90 }
            ?? list.first { ($0["score"] as? Int ?? 0) >= 98 }
        var prof: [String: Double] = [:]
        var tot = 0.0
        for tag in match?["tags"] as? [[String: Any]] ?? [] {
            let name = (tag["name"] as? String ?? "").lowercased()
            let w = max(0.5, Double(tag["count"] as? Int ?? 0))
            let range = NSRange(name.startIndex..., in: name)
            let hits = Set(GenreProfile.tagMap.filter { $0.0.firstMatch(in: name, range: range) != nil }.map(\.1))
            guard !hits.isEmpty else { continue }
            for h in hits {
                prof[h, default: 0] += w / Double(hits.count)
                tot += w / Double(hits.count)
            }
        }
        if tot > 0 { for k in prof.keys { prof[k] = ((prof[k]! / tot) * 100).rounded() / 100 } }
        artists[a.id] = prof
    }

    /// Analizza i brani (4 alla volta). Quelli falliti per rete non vengono salvati.
    func analyze(_ list: [Track], progress: (@MainActor (Int, Int) -> Void)? = nil) async {
        var seen = Set<String>()
        let todo = list.filter { tracks[$0.id] == nil && seen.insert($0.id).inserted }
        guard !todo.isEmpty else { return }
        let c = Counter()
        await withTaskGroup(of: Void.self) { g in
            for _ in 0..<4 {
                g.addTask { @MainActor in
                    while c.next < todo.count && c.fails < 6 {
                        let t = todo[c.next]
                        c.next += 1
                        do { try await self.analyzeTrack(t) } catch { c.fails += 1 }
                        c.finished += 1
                        progress?(c.finished, todo.count)
                    }
                }
            }
        }
        scheduleSave()
    }

    func analyzeArtists(_ list: [Track], progress: (@MainActor (Int, Int) -> Void)? = nil) async {
        var seen = Set<String>()
        let todo = list.compactMap(\.artists.first).filter { !$0.id.isEmpty && artists[$0.id] == nil && seen.insert($0.id).inserted }
        var fails = 0
        for (i, a) in todo.enumerated() {
            if fails > 4 { break }
            do { try await analyzeArtist(a) } catch { fails += 1 }
            progress?(i + 1, todo.count)
            if i % 10 == 9 { scheduleSave() }
        }
        scheduleSave()
    }

    func analyzeLibrary(_ favorites: [Track]) async {
        guard !busy else { return }
        busy = true
        defer { busy = false; total = 0 }
        let p = Counter()
        let upd: @MainActor () -> Void = { [weak self] in
            self?.done = p.next + p.finished
            self?.total = p.fails + p.extra
        }
        async let x: Void = analyze(favorites) { d, t in p.next = d; p.fails = t; upd() }
        async let y: Void = analyzeArtists(favorites) { d, t in p.finished = d; p.extra = t; upd() }
        _ = await (x, y)
    }

    /// Copertina di un brano da Deezer (per gli elenchi che non la includono).
    func coverURL(for t: Track) async -> URL? {
        let q = "\(t.artists.first?.name ?? "") \(Self.cleanTitle(t.name))".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let sr = try? await deezer("/search/track?limit=1&q=\(q)"),
              let first = (sr["data"] as? [[String: Any]])?.first,
              let album = first["album"] as? [String: Any],
              let c = album["cover_medium"] as? String else { return nil }
        return URL(string: c)
    }

    // MARK: - Punteggi

    /// Generi del brano: dell'artista (MusicBrainz) se noti, altrimenti dell'album (Deezer).
    func genres(_ t: Track) -> [String: Double]? {
        if let id = t.artists.first?.id, let p = artists[id], !p.isEmpty { return p }
        if let g = tracks[t.id]?.genre, !g.isEmpty { return [g: 1] }
        return nil
    }

    func mainGenre(_ t: Track) -> String? {
        genres(t)?.max { $0.value < $1.value }?.key
    }

    func label(_ t: Track) -> String? {
        guard let g = mainGenre(t) else { return nil }
        let name = GenreProfile.italian[g] ?? g
        if let b = tracks[t.id]?.bpm, b > 0 { return "\(name) · \(b) BPM" }
        return name
    }

    func userGenres(_ favorites: [Track]) -> [String: Double] {
        var c: [String: Double] = [:]
        var n = 0.0
        for t in favorites {
            guard let g = genres(t) else { continue }
            for (k, v) in g { c[k, default: 0] += v }
            n += 1
        }
        guard n > 0 else { return [:] }
        return c.mapValues { $0 / n }
    }

    /// Generi giusti per il meteo, pesati sui tuoi gusti.
    func moodGenres(_ m: Mood, favorites: [Track]) -> [String] {
        let w = GenreProfile.profile(m).weights
        let u = userGenres(favorites)
        return w.filter { $0.value > 0 }
            .map { ($0.key, $0.value * (u.isEmpty ? 1 : 0.25 + (u[$0.key] ?? 0) * 4)) }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    private static func bpmFit(_ b: Double, _ r: ClosedRange<Double>) -> Double {
        var c = [b]
        if b > 135 { c.append(b / 2) }
        if b < 75 { c.append(b * 2) }
        return c.map { x in r.contains(x) ? 1 : 1 - min(1, min(abs(x - r.lowerBound), abs(x - r.upperBound)) / 25) }.max() ?? 0
    }

    /// Affinità col meteo; nil = genere da escludere.
    func fit(_ t: Track, _ m: Mood) -> Double? {
        let p = GenreProfile.profile(m)
        let info = tracks[t.id]
        let ap = t.artists.first.flatMap { artists[$0.id] } ?? [:]
        if info == nil && ap.isEmpty { return -0.6 }
        var g = 0.0, known = false
        if !ap.isEmpty {
            known = true
            for (k, share) in ap {
                let w = p.weights[k] ?? 0
                if share >= 0.35 && w <= -1.5 { return nil }
                g += share * w
            }
        }
        if let ag = info?.genre, !ag.isEmpty {
            let w = p.weights[ag] ?? 0
            if !known && w <= -1.5 { return nil }
            g = known ? g * 0.7 + w * 0.3 : w
            known = true
        }
        var s = known ? g * 1.6 : -0.4
        if let b = info?.bpm, b > 0 { s += Self.bpmFit(Double(b), p.bpm) * 1.5 - 0.6 }
        return s
    }
}
