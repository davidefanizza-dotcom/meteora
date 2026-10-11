import Foundation

/// Costruisce la coda del Meteo Mix: tuoi brani + scoperte, filtrati e ordinati
/// per genere e BPM adatti al meteo (vedi AnalysisStore).
@MainActor
enum MixEngine {
    private enum Source { case fav, artist, disc }

    static func build(mood: Mood, count n: Int = 40, exclude: Set<String> = [],
                      library: LibraryStore, learn: LearnStore, analysis: AnalysisStore, favPercent: Double,
                      played: Set<String>, progress: (@MainActor (Int, Int) -> Void)? = nil) async -> [Track] {
        let profile = GenreProfile.profile(mood)
        let favorites = library.favorites
        var pool: [String: (track: Track, src: Set<Source>)] = [:]
        func add(_ list: [Track], _ src: Source) {
            for t in list where !exclude.contains(t.id) {
                var e = pool[t.id] ?? (track: t, src: Set<Source>())
                e.src.insert(src)
                pool[t.id] = e
            }
        }
        add(favorites, .fav)

        // Artisti tuoi il cui genere va bene con questo meteo.
        var byArtist: [String: (name: String, count: [String: Int])] = [:]
        for t in favorites {
            guard let a = t.artists.first, !a.id.isEmpty, let g = analysis.mainGenre(t) else { continue }
            var e = byArtist[a.id] ?? (a.name, [:])
            e.count[g, default: 0] += 1
            byArtist[a.id] = e
        }
        let goodArtists = byArtist.values.compactMap { e -> String? in
            guard let g = e.count.max(by: { $0.value < $1.value })?.key else { return nil }
            return (profile.weights[g] ?? 0) >= 1 ? e.name : nil
        }
        let artistNames = goodArtists.isEmpty ? library.topArtists.prefix(12).map(\.name) : goodArtists

        var reqs: [(Source, String, Int)] = []
        for name in artistNames.shuffled().prefix(2) { reqs.append((.artist, "artist:\"\(name)\"", 0)) }
        let genres = analysis.moodGenres(mood, favorites: favorites)
        for g in genres.prefix(3).shuffled() {
            let q = "\(GenreProfile.query[g] ?? g) \(profile.flavors.randomElement() ?? "")"
            reqs.append((.disc, q, Int.random(in: 0...2) * 10))
        }
        if let seed = mood.seeds.randomElement() { reqs.append((.disc, seed, Int.random(in: 0...2) * 10)) }

        await withTaskGroup(of: (Source, [Track]).self) { g in
            for (src, q, off) in reqs {
                g.addTask { @MainActor in ((src, (try? await library.search(q, offset: off)) ?? [])) }
            }
            for await (src, list) in g { add(list, src) }
        }

        await analysis.analyze(pool.values.map(\.track), progress: progress)

        struct Scored { let track: Track; let score: Double; let reason: String; let fav: Bool }
        var scored: [Scored] = []
        for (_, e) in pool {
            let t = e.track
            let lt = learn.value("t:" + t.id, mood: mood)
            if lt < 0 { continue }
            let la = t.artists.reduce(0) { $0 + learn.value("a:" + $1.id, mood: mood) }
            if la <= -2 { continue }
            let f = analysis.fit(t, mood)
            if f == nil && lt <= 0 { continue }
            var s = Double.random(in: 0...1.5) + (f ?? 0)
            let words = Set((t.name + " " + t.album).lowercased()
                .components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty })
            let hit = mood.keywords.first { words.contains($0) }
            if hit != nil { s += 2.5 }
            s += lt * 4 + la * 1.5
            if e.src.contains(.fav) { s += 1.2 }
            if e.src.contains(.artist) { s += 0.8 }
            if e.src.contains(.disc) { s += 0.6 }
            if played.contains(t.id) { s -= 6 }
            let reason: String
            if lt > 0 || la > 0.9 { reason = "Imparato" }
            else if let l = analysis.label(t) { reason = l }
            else if let hit { reason = "“\(hit)”" }
            else if e.src.contains(.disc) { reason = "Scoperta" }
            else { reason = "Preferito" }
            scored.append(Scored(track: t, score: s, reason: reason,
                                 fav: e.src.contains(.fav) || e.src.contains(.artist)))
        }
        scored.sort { $0.score > $1.score }

        let favs = scored.filter(\.fav), disc = scored.filter { !$0.fav }
        let nFav = Int((Double(n) * favPercent / 100).rounded())
        var out: [Track] = [], perArtist: [String: Int] = [:]
        var fi = 0, di = 0, cf = 0, cd = 0

        func take(_ arr: [Scored], _ idx: inout Int) -> Scored? {
            while idx < arr.count {
                let x = arr[idx]
                idx += 1
                let a = x.track.artists.first?.id ?? ""
                if perArtist[a, default: 0] >= 2 { continue }
                perArtist[a, default: 0] += 1
                return x
            }
            return nil
        }

        while out.count < n && (fi < favs.count || di < disc.count) {
            let wantFav = cf < nFav && (cd >= n - nFav || Double(cf) / Double(max(nFav, 1)) <= Double(cd) / Double(max(n - nFav, 1)))
            var x: Scored?
            if wantFav {
                x = take(favs, &fi)
                if x != nil { cf += 1 } else { x = take(disc, &di); if x != nil { cd += 1 } }
            } else {
                x = take(disc, &di)
                if x != nil { cd += 1 } else { x = take(favs, &fi); if x != nil { cf += 1 } }
            }
            guard let x else { break }
            var t = x.track
            t.reason = x.reason
            t.mood = mood
            t.discovery = !x.fav
            out.append(t)
        }
        return out
    }
}
