import Foundation
import AuthenticationServices
import CryptoKit
import UIKit

struct Tokens: Codable {
    var access: String
    var refresh: String?
    var expiry: Date
}

enum AuthError: LocalizedError {
    case cancelled, noCode, noClientId, failed(String)

    var errorDescription: String? {
        switch self {
        case .cancelled: "Accesso annullato"
        case .noCode: "Risposta di Spotify non valida"
        case .noClientId: "Inserisci prima il Client ID"
        case .failed(let m): m
        }
    }
}

final class AuthPresenter: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            if let w = scenes.flatMap(\.windows).first(where: \.isKeyWindow) { return w }
            if let s = scenes.first { return UIWindow(windowScene: s) }
            return ASPresentationAnchor()
        }
    }
}

/// Accesso a Spotify con OAuth PKCE. La pagina callback.html su GitHub Pages
/// rimanda a meteora://callback, che ASWebAuthenticationSession intercetta.
@MainActor @Observable
final class SpotifyAuth {
    static let redirectURI = "https://davidefanizza-dotcom.github.io/meteora/callback.html"
    static let scopes = "user-read-email user-read-private user-read-playback-state user-modify-playback-state user-read-currently-playing user-top-read user-library-read user-library-modify user-read-recently-played playlist-read-private playlist-read-collaborative"

    private(set) var isLoggedIn = false

    @ObservationIgnored private var tokens: Tokens?
    @ObservationIgnored private let presenter = AuthPresenter()
    @ObservationIgnored private var session: ASWebAuthenticationSession?
    @ObservationIgnored private var refreshing: Task<String, Error>?
    @ObservationIgnored private let clientId: () -> String

    init(clientId: @escaping () -> String) {
        self.clientId = clientId
        if let d = Keychain.read("tokens"), let t = try? JSONDecoder().decode(Tokens.self, from: d) {
            tokens = t
            isLoggedIn = true
        }
    }

    private func store(_ t: Tokens?) {
        tokens = t
        if let t, let d = try? JSONEncoder().encode(t) { Keychain.write("tokens", d) } else { Keychain.delete("tokens") }
        isLoggedIn = t != nil
    }

    func login() async throws {
        let cid = clientId().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cid.isEmpty else { throw AuthError.noClientId }
        let verifier = Self.randomString(64)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL

        var c = URLComponents(string: "https://accounts.spotify.com/authorize")!
        c.queryItems = [
            URLQueryItem(name: "client_id", value: cid),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "scope", value: Self.scopes)
        ]
        guard let url = c.url else { throw AuthError.failed("Indirizzo di accesso non valido") }

        let callback: URL = try await withCheckedThrowingContinuation { cont in
            let s = ASWebAuthenticationSession(url: url, callbackURLScheme: "meteora") { u, e in
                if let u {
                    cont.resume(returning: u)
                } else {
                    let err: Error = e ?? AuthError.cancelled
                    let cancelled = (err as? ASWebAuthenticationSessionError)?.code == .canceledLogin
                    cont.resume(throwing: cancelled ? AuthError.cancelled : err)
                }
            }
            s.presentationContextProvider = presenter
            s.prefersEphemeralWebBrowserSession = false
            session = s
            if !s.start() {
                cont.resume(throwing: AuthError.failed("Impossibile aprire l'accesso a Spotify"))
            }
        }

        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let err = items.first(where: { $0.name == "error" })?.value { throw AuthError.failed("Spotify: \(err)") }
        guard let code = items.first(where: { $0.name == "code" })?.value else { throw AuthError.noCode }
        let t = try await tokenRequest([
            "client_id": cid,
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": Self.redirectURI,
            "code_verifier": verifier
        ], previousRefresh: nil)
        store(t)
    }

    func accessToken() async throws -> String {
        guard let t = tokens else { throw APIError.notLoggedIn }
        if t.expiry.timeIntervalSinceNow > 60 { return t.access }
        if let r = refreshing { return try await r.value }
        guard let rt = t.refresh else { store(nil); throw APIError.notLoggedIn }
        let cid = clientId()
        let task = Task { [self] () throws -> String in
            defer { refreshing = nil }
            do {
                let nt = try await tokenRequest(["client_id": cid, "grant_type": "refresh_token", "refresh_token": rt], previousRefresh: rt)
                store(nt)
                return nt.access
            } catch let e as AuthError {
                store(nil)
                throw e
            }
        }
        refreshing = task
        return try await task.value
    }

    func invalidate() {
        if var t = tokens { t.expiry = .distantPast; tokens = t }
    }

    func logout() { store(nil) }

    private func tokenRequest(_ params: [String: String], previousRefresh: String?) async throws -> Tokens {
        var r = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        r.httpMethod = "POST"
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        r.httpBody = params
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)
        let (d, resp) = try await URLSession.shared.data(for: r)
        struct TR: Decodable {
            let access_token: String
            let refresh_token: String?
            let expires_in: Int
        }
        guard (resp as? HTTPURLResponse)?.statusCode == 200, let tr = try? JSONDecoder().decode(TR.self, from: d) else {
            let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
            let msg = obj?["error_description"] as? String
            throw AuthError.failed(msg ?? "Accesso a Spotify non riuscito")
        }
        return Tokens(access: tr.access_token, refresh: tr.refresh_token ?? previousRefresh,
                      expiry: Date().addingTimeInterval(Double(tr.expires_in)))
    }

    private static func randomString(_ n: Int) -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
        return String((0..<n).map { _ in chars.randomElement()! })
    }
}

extension Data {
    var base64URL: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

enum Keychain {
    private static func base(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "meteora",
         kSecAttrAccount as String: key]
    }

    static func write(_ key: String, _ data: Data) {
        SecItemDelete(base(key) as CFDictionary)
        var q = base(key)
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }

    static func read(_ key: String) -> Data? {
        var q = base(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    static func delete(_ key: String) {
        SecItemDelete(base(key) as CFDictionary)
    }
}
