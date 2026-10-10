import Foundation

enum APIError: LocalizedError {
    case notLoggedIn
    case rateLimited(Int)
    case status(Int, String)

    var errorDescription: String? {
        switch self {
        case .notLoggedIn: "Non sei collegato a Spotify"
        case .rateLimited(let s): "Spotify ha limitato le richieste: riprova tra \(max(1, s / 60)) min"
        case .status(_, let m): m
        }
    }

    var code: Int {
        if case .status(let c, _) = self { return c }
        return 0
    }
}

@MainActor
final class SpotifyAPI {
    let auth: SpotifyAuth
    private var blockedUntil = Date.distantPast
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    init(auth: SpotifyAuth) { self.auth = auth }

    var isBlocked: Bool { Date() < blockedUntil }

    private func raw(_ method: String, _ path: String, query: [String: String] = [:], body: [String: Any]? = nil) async throws -> Data? {
        if isBlocked { throw APIError.rateLimited(Int(blockedUntil.timeIntervalSinceNow)) }
        guard var comps = URLComponents(string: "https://api.spotify.com/v1" + path) else {
            throw APIError.status(0, "Richiesta non valida")
        }
        if !query.isEmpty {
            comps.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = comps.url else { throw APIError.status(0, "Richiesta non valida") }

        for attempt in 0..<3 {
            let token = try await auth.accessToken()
            var req = URLRequest(url: url)
            req.httpMethod = method
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            if let body {
                req.httpBody = try JSONSerialization.data(withJSONObject: body)
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            } else if method != "GET" {
                req.httpBody = Data()
            }
            let (data, resp) = try await URLSession.shared.data(for: req)
            let http = resp as? HTTPURLResponse
            let code = http?.statusCode ?? 0

            if code == 401 && attempt == 0 {
                auth.invalidate()
                continue
            }
            if code == 429 {
                let ra = Int(http?.value(forHTTPHeaderField: "Retry-After") ?? "2") ?? 2
                if ra <= 8 {
                    try await Task.sleep(for: .seconds(ra))
                    continue
                }
                blockedUntil = Date().addingTimeInterval(Double(ra))
                throw APIError.rateLimited(ra)
            }
            if code == 204 || code == 202 { return nil }
            if !(200..<300).contains(code) {
                let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                let msg = (obj?["error"] as? [String: Any])?["message"] as? String
                throw APIError.status(code, msg ?? "Errore \(code)")
            }
            return data.isEmpty ? nil : data
        }
        throw APIError.status(0, "Spotify non risponde")
    }

    func get<T: Decodable>(_ path: String, _ query: [String: String] = [:]) async throws -> T {
        guard let d = try await raw("GET", path, query: query) else { throw APIError.status(204, "Nessun dato") }
        return try decoder.decode(T.self, from: d)
    }

    func getOptional<T: Decodable>(_ path: String, _ query: [String: String] = [:]) async throws -> T? {
        guard let d = try await raw("GET", path, query: query) else { return nil }
        return try decoder.decode(T.self, from: d)
    }

    func send(_ method: String, _ path: String, _ query: [String: String] = [:], body: [String: Any]? = nil) async throws {
        _ = try await raw(method, path, query: query, body: body)
    }
}
