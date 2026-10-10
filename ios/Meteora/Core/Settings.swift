import SwiftUI

/// Impostazioni salvate in UserDefaults.
@MainActor @Observable
final class Settings {
    @ObservationIgnored private let d = UserDefaults.standard

    var clientId: String { didSet { d.set(clientId, forKey: "clientId") } }
    var autoAdapt: Bool { didSet { d.set(autoAdapt, forKey: "autoAdapt") } }
    var intervalMin: Int { didSet { d.set(intervalMin, forKey: "intervalMin") } }
    /// Percentuale di brani dai tuoi gusti (il resto sono scoperte).
    var mixFav: Double { didSet { d.set(mixFav, forKey: "mixFav") } }
    var simulated: Mood? { didSet { d.set(simulated?.rawValue, forKey: "simulated") } }
    var useLocation: Bool { didSet { d.set(useLocation, forKey: "useLocation") } }
    var cityName: String { didSet { d.set(cityName, forKey: "cityName") } }
    var lat: Double { didSet { d.set(lat, forKey: "lat") } }
    var lon: Double { didSet { d.set(lon, forKey: "lon") } }
    var animateWeather: Bool { didSet { d.set(animateWeather, forKey: "animateWeather") } }
    var haptics: Bool { didSet { d.set(haptics, forKey: "haptics") } }
    /// 0 = sistema, 1 = scuro, 2 = chiaro
    var theme: Int { didSet { d.set(theme, forKey: "theme") } }
    /// 0 = tutte, 1 = create da te, 2 = seguite
    var libFilter: Int { didSet { d.set(libFilter, forKey: "libFilter") } }

    init() {
        d.register(defaults: [
            "autoAdapt": true, "intervalMin": 10, "mixFav": 70.0, "useLocation": true,
            "cityName": "Calimera", "lat": 40.25, "lon": 18.28, "animateWeather": true,
            "haptics": true, "theme": 1, "libFilter": 0
        ])
        clientId = d.string(forKey: "clientId") ?? ""
        autoAdapt = d.bool(forKey: "autoAdapt")
        intervalMin = d.integer(forKey: "intervalMin")
        mixFav = d.double(forKey: "mixFav")
        simulated = d.string(forKey: "simulated").flatMap(Mood.init(rawValue:))
        useLocation = d.bool(forKey: "useLocation")
        cityName = d.string(forKey: "cityName") ?? "Calimera"
        lat = d.double(forKey: "lat")
        lon = d.double(forKey: "lon")
        animateWeather = d.bool(forKey: "animateWeather")
        haptics = d.bool(forKey: "haptics")
        theme = d.integer(forKey: "theme")
        libFilter = d.integer(forKey: "libFilter")
    }

    var colorScheme: ColorScheme? {
        switch theme {
        case 1: .dark
        case 2: .light
        default: nil
        }
    }
}

/// Avvisi brevi in alto, in vetro.
@MainActor @Observable
final class Toaster {
    static let shared = Toaster()

    struct Item: Identifiable, Equatable {
        let id = UUID()
        let text: String
        let symbol: String
    }

    var current: Item?
    @ObservationIgnored private var hideTask: Task<Void, Never>?

    func show(_ text: String, symbol: String = "checkmark.circle.fill", seconds: Double = 3) {
        current = Item(text: text, symbol: symbol)
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            if !Task.isCancelled { current = nil }
        }
    }

    func error(_ e: Error) {
        show(e.localizedDescription, symbol: "exclamationmark.triangle.fill", seconds: 4.5)
    }
}

/// Gusti imparati con 👍 / 👎, separati per meteo.
@MainActor @Observable
final class LearnStore {
    private(set) var data: [String: [String: Double]]

    init() {
        if let raw = UserDefaults.standard.data(forKey: "learn"),
           let d = try? JSONDecoder().decode([String: [String: Double]].self, from: raw) {
            data = d
        } else {
            data = [:]
        }
    }

    private func save() {
        if let raw = try? JSONEncoder().encode(data) { UserDefaults.standard.set(raw, forKey: "learn") }
    }

    func value(_ key: String, mood: Mood) -> Double { data[mood.rawValue]?[key] ?? 0 }

    func feedback(_ t: Track, mood: Mood, positive: Bool) {
        var m = data[mood.rawValue] ?? [:]
        m["t:" + t.id] = positive ? 1 : -1
        for a in t.artists where !a.id.isEmpty {
            let k = "a:" + a.id
            m[k] = min(3, max(-3, (m[k] ?? 0) + (positive ? 0.5 : -0.5)))
        }
        data[mood.rawValue] = m
        save()
    }

    func learnedCount(_ mood: Mood) -> Int {
        (data[mood.rawValue] ?? [:]).keys.filter { $0.hasPrefix("t:") }.count
    }

    var totalCount: Int { Mood.allCases.reduce(0) { $0 + learnedCount($1) } }

    func reset() {
        data = [:]
        save()
    }
}
