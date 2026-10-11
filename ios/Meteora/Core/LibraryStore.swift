import Foundation

/// I dati Spotify dell'utente: profilo, preferiti, ascolti recenti, playlist.
@MainActor @Observable
final class LibraryStore {
    var me: UserProfile?
    var topArtists: [SArtist] = []
    var topShort: [Track] = []
    var topMedium: [Track] = []
    var saved: [Track] = []
    var savedHasMore = false
    var recent: [Track] = []
    var playlists: [Playlist] = []
    var loaded = false
    var loading = false
    var error: String?

    @ObservationIgnored let api: SpotifyAPI

    init(api: SpotifyAPI) { self.api = api }

    func load() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        error = nil

        do {
            me = try await api.get("/me")
        } catch {
            self.error = error.localizedDescription
            Toaster.shared.error(error)
            return
        }

        async let a: Paging<SArtist>? = fetch("/me/top/artists", ["limit": "20", "time_range": "short_term"])
        async let s: Paging<STrack>? = fetch("/me/top/tracks", ["limit": "50", "time_range": "short_term"])
        async let m: Paging<STrack>? = fetch("/me/top/tracks", ["limit": "50", "time_range": "medium_term"])
        async let sv: Paging<SavedTrack>? = fetch("/me/tracks", ["limit": "50"])
        async let r: Paging<PlayHistory>? = fetch("/me/player/recently-played", ["limit": "50"])
        async let pl: Paging<Playlist?>? = fetch("/me/playlists", ["limit": "50"])

        let (ra, rs, rm, rsv, rr, rpl) = await (a, s, m, sv, r, pl)
        topArtists = ra?.items ?? []
        topShort = (rs?.items ?? []).compactMap { Track($0) }
        topMedium = (rm?.items ?? []).compactMap { Track($0) }
        saved = (rsv?.items ?? []).compactMap { Track($0.track) }
        savedHasMore = rsv?.next != nil
        var seen = Set<String>()
        recent = (rr?.items ?? []).compactMap { Track($0.track) }.filter { seen.insert($0.id).inserted }
        playlists = (rpl?.items ?? []).compactMap { $0 }
        loaded = true
        if let error { Toaster.shared.show(error, symbol: "exclamationmark.triangle.fill", seconds: 5) }
    }

    private func fetch<T: Decodable>(_ path: String, _ q: [String: String]) async -> T? {
        do {
            return try await api.get(path, q)
        } catch {
            if self.error == nil { self.error = error.localizedDescription }
            return nil
        }
    }

    /// Tutti i brani che conosci (preferiti, salvati, recenti), senza doppioni.
    var favorites: [Track] {
        var seen = Set<String>()
        return (topShort + topMedium + saved + recent).filter { seen.insert($0.id).inserted }
    }

    func isMine(_ p: Playlist) -> Bool {
        (p.owner?.id != nil && p.owner?.id == me?.id) || (p.collaborative ?? false)
    }

    func playlistTracks(_ p: Playlist, offset: Int) async throws -> (tracks: [Track], total: Int) {
        let q = ["limit": "50", "offset": "\(offset)"]
        let page: Paging<PlaylistItem>
        do {
            page = try await api.get("/playlists/\(p.id)/items", q)
        } catch let e as APIError where e.code == 404 {
            page = try await api.get("/playlists/\(p.id)/tracks", q)
        }
        let tracks = page.items.compactMap { Track($0.item ?? $0.track) }
        return (tracks, page.total ?? tracks.count)
    }

    /// Brani di una playlist seguita: prima la playlist completa (campo "tracks"),
    /// poi l'elenco del riquadro ufficiale di Spotify (open.spotify.com/embed).
    func followedTracks(_ p: Playlist) async -> [Track]? {
        struct PL: Decodable { let tracks: Paging<PlaylistItem>? }
        let fields = "tracks(total,next,items(track(id,uri,name,duration_ms,type,artists(id,name),album(name,images),external_ids)))"
        if let r: PL = try? await api.get("/playlists/\(p.id)", ["fields": fields]),
           let items = r.tracks?.items {
            let t = items.compactMap { Track($0.item ?? $0.track) }
            if !t.isEmpty { return t }
        }
        guard let url = URL(string: "https://open.spotify.com/embed/playlist/\(p.id)") else { return nil }
        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1",
                     forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let html = String(data: data, encoding: .utf8),
              let r1 = html.range(of: "<script id=\"__NEXT_DATA__\" type=\"application/json\">"),
              let r2 = html.range(of: "</script>", range: r1.upperBound..<html.endIndex),
              let obj = try? JSONSerialization.jsonObject(with: Data(html[r1.upperBound..<r2.lowerBound].utf8)) as? [String: Any],
              let props = obj["props"] as? [String: Any], let page = props["pageProps"] as? [String: Any],
              let state = page["state"] as? [String: Any], let d = state["data"] as? [String: Any],
              let entity = d["entity"] as? [String: Any], let list = entity["trackList"] as? [[String: Any]]
        else { return nil }
        let tracks = list.compactMap { x -> Track? in
            guard let uri = x["uri"] as? String, uri.hasPrefix("spotify:track:"), let title = x["title"] as? String else { return nil }
            let id = String(uri.dropFirst("spotify:track:".count))
            let artist = x["subtitle"] as? String ?? ""
            let dur = (x["duration"] as? Int) ?? Int(x["duration"] as? Double ?? 0)
            return Track(id: id, uri: uri, name: title, artists: [ArtistRef(id: "", name: artist)], album: "", imageURL: nil, durationMs: dur)
        }
        return tracks.isEmpty ? nil : tracks
    }

    func loadMoreSaved() async {
        do {
            let page: Paging<SavedTrack> = try await api.get("/me/tracks", ["limit": "50", "offset": "\(saved.count)"])
            saved += page.items.compactMap { Track($0.track) }
            savedHasMore = page.next != nil
        } catch {
            Toaster.shared.error(error)
        }
    }

    func search(_ q: String, offset: Int) async throws -> [Track] {
        let r: SearchResp = try await api.get("/search", ["q": q, "type": "track", "limit": "10", "offset": "\(offset)"])
        return (r.tracks?.items ?? []).compactMap { Track($0) }
    }

    /// Generi dei tuoi artisti preferiti (Spotify li sta dismettendo: possono arrivare vuoti).
    var topGenres: [String] {
        var c: [String: Int] = [:]
        for (i, a) in topArtists.enumerated() {
            for g in a.genres ?? [] { c[g, default: 0] += 20 - i }
        }
        return c.sorted { $0.value > $1.value }.map(\.key)
    }
}
