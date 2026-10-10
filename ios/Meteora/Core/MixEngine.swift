import Foundation

/// Costruisce la coda del Meteo Mix: tuoi brani + scoperte, ordinati per affinità col meteo.
@MainActor
enum MixEngine {
    private enum Source { case fav, artist, disc }

    static func build(mood: Mood, count n: Int = 40, exclude: Set<String> = [],
                      library: LibraryStore, learn: LearnStore, favPercent: Double,
                      played: Set<String>) async -> [Track] {
        var pool: [String: (track: Track, src: Set<Source>)] = [:]
        func add(_ list: [Track], _ src: Source) {
            for t in list where !exclude.contains(t.id) {
                var e = pool[t.id] ?? (track: t, src: Set<Source>())
                e.src.insert(src)
                pool[t.id] = e
            }
        }
        add(library.topShort, .fav)
        add(library.topMedium, .fav)
        add(library.saved, .fav)
        add(library.recent, .fav)

        // Ricerche: brani dei tuoi artisti + scoperte per atmosfera.
        var reqs: [(Source, String, Int)] = []
        for a in library.topArtists.prefix(12).shuffled().prefix(3) {
            reqs.append((.artist, "artist:\"\(a.name)\"", 0))
        }
        let genres = library.topGenres
        for (i, seed) in mood.seeds.shuffled().prefix(3).enumerated() {
            let q = (i < 2 && !genres.isEmpty) ? "\(seed) genre:\"\(genres[min(i, genres.count - 1)])\"" : seed
            reqs.append((.disc, q, Int.random(in: 0...2) * 10))
        }
        await withTaskGroup(of: (Source, [Track]).self) { g in
            for (src, q, off) in reqs {
                g.addTask { @MainActor in
                    let r = (try? await library.search(q, offset: off)) ?? []
                    return (src, r)
                }
            }
            for await (src, list) in g { add(list, src) }
        }

        struct Scored { let track: Track; let score: Double; let reason: String; let fav: Bool }
        var scored: [Scored] = []
        for (_, e) in pool {
            let t = e.track
            let words = Set((t.name + " " + t.album).lowercased()
                .components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty })
            var s = Double.random(in: 0...2.5)
            let hit = mood.keywords.first { words.contains($0) }
            if hit != nil { s += 3.2 }
            let lt = learn.value("t:" + t.id, mood: mood)
            if lt < 0 { continue }
            let la = t.artists.reduce(0) { $0 + learn.value("a:" + $1.id, mood: mood) }
            if la <= -2 { continue }
            s += lt * 4 + la * 1.5
            if e.src.contains(.fav) { s += 2 }
            if e.src.contains(.artist) { s += 1.2 }
            if e.src.contains(.disc) { s += 1.5 }
            if played.contains(t.id) { s -= 6 }
            let reason: String
            if lt > 0 || la > 0.9 { reason = "Imparato" }
            else if let hit { reason = "“\(hit)”" }
            else if e.src.contains(.fav) { reason = "Preferito" }
            else if e.src.contains(.artist) { reason = "Tuo artista" }
            else { reason = "Scoperta" }
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
            out.append(t)
        }
        return out
    }
}
