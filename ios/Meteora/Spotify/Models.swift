import Foundation

// MARK: - Risposte grezze della Web API (decodificate con convertFromSnakeCase)

struct SImage: Codable, Hashable {
    let url: String
    let width: Int?
    let height: Int?
}

struct SArtist: Codable, Hashable {
    let id: String?
    let name: String
    let genres: [String]?
    let images: [SImage]?
}

struct SAlbum: Codable, Hashable {
    let name: String?
    let images: [SImage]?
}

struct STrack: Codable, Hashable {
    let id: String?
    let uri: String?
    let name: String?
    let artists: [SArtist]?
    let album: SAlbum?
    let durationMs: Int?
    let type: String?
}

struct Paging<T: Codable>: Codable {
    let items: [T]
    let next: String?
    let total: Int?
}

struct TotalRef: Codable, Hashable { let total: Int? }
struct Owner: Codable, Hashable { let id: String?; let displayName: String? }
struct ExternalURLs: Codable, Hashable { let spotify: String? }

struct Playlist: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let uri: String
    let images: [SImage]?
    let owner: Owner?
    let collaborative: Bool?
    let items: TotalRef?      // nome nuovo (feb 2026)
    let tracks: TotalRef?     // nome vecchio, deprecato
    let externalUrls: ExternalURLs?

    var count: Int? { items?.total ?? tracks?.total }
    var cover: URL? { images?.best(300) }
}

struct PlaylistItem: Codable { let item: STrack?; let track: STrack? }
struct SavedTrack: Codable { let track: STrack? }
struct PlayHistory: Codable { let track: STrack? }

struct Device: Codable, Hashable, Identifiable {
    let id: String?
    let name: String
    let type: String?
    let isActive: Bool?
}

struct DevicesResp: Codable { let devices: [Device] }
struct PlayContext: Codable { let uri: String? }

struct PlaybackState: Codable {
    let device: Device?
    let progressMs: Int?
    let isPlaying: Bool?
    let item: STrack?
    let context: PlayContext?
}

struct QueueResp: Codable {
    let currentlyPlaying: STrack?
    let queue: [STrack]?
}

struct SearchResp: Codable { let tracks: Paging<STrack>? }

struct UserProfile: Codable {
    let id: String
    let displayName: String?
    let images: [SImage]?
}

extension Array where Element == SImage {
    func best(_ size: Int) -> URL? {
        let s = sorted { ($0.width ?? 0) < ($1.width ?? 0) }
        let p = s.first { ($0.width ?? 0) >= size } ?? s.last
        return p.flatMap { URL(string: $0.url) }
    }
}

// MARK: - Modello usato dall'app

struct ArtistRef: Codable, Hashable {
    let id: String
    let name: String
}

struct Track: Codable, Hashable, Identifiable {
    let id: String
    let uri: String
    let name: String
    let artists: [ArtistRef]
    let album: String
    let imageURL: URL?
    let largeImageURL: URL?
    let durationMs: Int
    var reason: String? = nil
    var mood: Mood? = nil

    var artistLine: String { artists.map(\.name).joined(separator: ", ") }

    init?(_ s: STrack?) {
        guard let s, let id = s.id, let name = s.name, (s.type ?? "track") == "track" else { return nil }
        self.id = id
        self.uri = s.uri ?? "spotify:track:\(id)"
        self.name = name
        self.artists = (s.artists ?? []).map { ArtistRef(id: $0.id ?? "", name: $0.name) }
        self.album = s.album?.name ?? ""
        self.imageURL = s.album?.images?.best(300)
        self.largeImageURL = s.album?.images?.best(640)
        self.durationMs = s.durationMs ?? 0
    }
}
