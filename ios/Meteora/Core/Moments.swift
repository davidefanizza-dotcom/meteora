import Foundation
import AVFoundation

/// Un pezzo di canzone: dal secondo `start` al secondo `end` (in millisecondi).
/// Stesso formato della versione web/PC, così il backup si importa da una all'altra.
struct MomentItem: Codable, Hashable, Identifiable {
    var id: String
    var trackId: String
    var uri: String
    var name: String
    var artists: [ArtistRef]
    var album: String?
    var img: String?
    var trackDur: Int?
    var start: Int
    var end: Int
    var label: String?

    var length: Int { end - start }
    var imageURL: URL? { img.flatMap(URL.init(string:)) }
    var artistLine: String { artists.map(\.name).joined(separator: ", ") }

    var asTrack: Track {
        Track(id: trackId, uri: uri, name: name, artists: artists, album: album ?? "", imageURL: imageURL, durationMs: trackDur ?? end)
    }
}

struct MomentList: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var items: [MomentItem]
    var repeatOn: Bool?
    var created: Double?

    enum CodingKeys: String, CodingKey { case id, name, items, created, repeatOn = "repeat" }

    var totalMs: Int { items.reduce(0) { $0 + $1.length } }
    var covers: [URL] {
        var seen = Set<String>()
        return items.compactMap(\.img).filter { seen.insert($0).inserted }.prefix(4).compactMap(URL.init(string:))
    }
}

struct Backup: Codable {
    var meteora: Int = 2
    var moments: [MomentList]?
}

@MainActor @Observable
final class MomentsStore {
    var lists: [MomentList] = []
    var lastListId: String? {
        didSet { UserDefaults.standard.set(lastListId, forKey: "momLast") }
    }

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("momenti.json")
    }

    init() {
        lastListId = UserDefaults.standard.string(forKey: "momLast")
        if let d = try? Data(contentsOf: Self.fileURL), let l = try? JSONDecoder().decode([MomentList].self, from: d) {
            lists = l
        }
    }

    func save() {
        if let d = try? JSONEncoder().encode(lists) { try? d.write(to: Self.fileURL, options: .atomic) }
    }

    static func newId() -> String { String(UUID().uuidString.prefix(12)).lowercased() }

    func list(_ id: String) -> MomentList? { lists.first { $0.id == id } }

    @discardableResult
    func createList(_ name: String) -> String {
        let l = MomentList(id: Self.newId(), name: name, items: [], repeatOn: false, created: Date().timeIntervalSince1970 * 1000)
        lists.insert(l, at: 0)
        save()
        return l.id
    }

    func add(_ item: MomentItem, to listId: String) {
        guard let i = lists.firstIndex(where: { $0.id == listId }) else { return }
        lists[i].items.append(item)
        lastListId = listId
        save()
    }

    func update(_ item: MomentItem, in listId: String) {
        guard let i = lists.firstIndex(where: { $0.id == listId }),
              let k = lists[i].items.firstIndex(where: { $0.id == item.id }) else { return }
        lists[i].items[k] = item
        save()
    }

    func remove(itemAt k: Int, from listId: String) {
        guard let i = lists.firstIndex(where: { $0.id == listId }) else { return }
        lists[i].items.remove(at: k)
        save()
    }

    func move(in listId: String, from: IndexSet, to: Int) {
        guard let i = lists.firstIndex(where: { $0.id == listId }) else { return }
        lists[i].items.move(fromOffsets: from, toOffset: to)
        save()
    }

    func rename(_ listId: String, to name: String) {
        guard let i = lists.firstIndex(where: { $0.id == listId }) else { return }
        lists[i].name = name
        save()
    }

    func setRepeat(_ listId: String, _ on: Bool) {
        guard let i = lists.firstIndex(where: { $0.id == listId }) else { return }
        lists[i].repeatOn = on
        save()
    }

    func delete(_ listId: String) {
        lists.removeAll { $0.id == listId }
        save()
    }

    func exportData(_ only: [MomentList]? = nil) -> Data? {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? enc.encode(Backup(moments: only ?? lists))
    }

    /// Unisce un backup (anche quello della versione web/PC). Ritorna quanti momenti ha aggiunto.
    func importData(_ data: Data) throws -> Int {
        let b = try JSONDecoder().decode(Backup.self, from: data)
        var n = 0
        for l in b.moments ?? [] {
            if let i = lists.firstIndex(where: { $0.id == l.id }) {
                let ids = Set(lists[i].items.map(\.id))
                for it in l.items where !ids.contains(it.id) {
                    lists[i].items.append(it)
                    n += 1
                }
            } else {
                lists.append(l)
                n += l.items.count
            }
        }
        save()
        return n
    }
}

/// Tiene sveglia l'app a schermo bloccato riproducendo silenzio (mixato con Spotify):
/// così Meteora può passare da un momento all'altro e far avanzare il Meteo Mix.
@MainActor
final class KeepAlive {
    static let shared = KeepAlive()
    private var player: AVAudioPlayer?

    func start() {
        guard player == nil else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            let p = try AVAudioPlayer(data: Self.silence())
            p.numberOfLoops = -1
            p.volume = 0
            p.play()
            player = p
        } catch {}
    }

    func stop() {
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// 1 secondo di silenzio in WAV (mono, 8 kHz, 16 bit).
    private static func silence() -> Data {
        let rate: UInt32 = 8000, samples = rate
        let dataSize = samples * 2
        var d = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + dataSize)
        d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1); u32(rate); u32(rate * 2); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(dataSize)
        d.append(Data(count: Int(dataSize)))
        return d
    }
}
