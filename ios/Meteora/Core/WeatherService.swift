import Foundation
import CoreLocation

struct HourForecast: Identifiable, Hashable {
    let id: String
    let label: String
    let temp: Int
    let mood: Mood
}

struct CityResult: Identifiable, Hashable {
    let id: String
    let name: String
    let detail: String
    let lat: Double
    let lon: Double
}

/// Meteo da Open-Meteo (gratuito, senza chiave) e posizione dal GPS.
@MainActor @Observable
final class WeatherService {
    var real: Mood = .nuvoloso
    var temp: Int?
    var feels: Int?
    var code = 3
    var wind = 0
    var place: String
    var hours: [HourForecast] = []
    var updated: Date?
    var loading = false

    @ObservationIgnored let settings: Settings
    @ObservationIgnored private let manager = CLLocationManager()

    init(settings: Settings) {
        self.settings = settings
        self.place = settings.cityName
    }

    var mood: Mood { settings.simulated ?? real }
    var conditionText: String { WMO.text(code) }

    /// Prima ora in cui l'atmosfera cambia.
    var nextChange: HourForecast? {
        var prev = real
        for h in hours {
            if h.mood != prev { return h }
            prev = h.mood
        }
        return nil
    }

    func refreshIfStale() async {
        if let u = updated, Date().timeIntervalSince(u) < Double(settings.intervalMin * 60) { return }
        await refresh()
    }

    func refresh() async {
        loading = true
        defer { loading = false }
        var lat = settings.lat, lon = settings.lon, name = settings.cityName

        if settings.useLocation, let loc = await locate() {
            lat = loc.coordinate.latitude
            lon = loc.coordinate.longitude
            name = await placeName(loc) ?? "La tua posizione"
            settings.lat = lat
            settings.lon = lon
            settings.cityName = name
        }

        let s = "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current=temperature_2m,apparent_temperature,weather_code,is_day,wind_speed_10m&hourly=temperature_2m,weather_code,is_day,wind_speed_10m&forecast_hours=13&timezone=auto"
        guard let url = URL(string: s),
              let res = try? await URLSession.shared.data(from: url),
              let r = try? JSONDecoder().decode(OMResp.self, from: res.0) else {
            Toaster.shared.show("Meteo non disponibile, riprovo più tardi", symbol: "cloud.slash.fill")
            return
        }
        let c = r.current
        temp = Int(c.temperature_2m.rounded())
        feels = Int(c.apparent_temperature.rounded())
        code = c.weather_code
        wind = Int(c.wind_speed_10m.rounded())
        place = name
        real = Mood.from(code: c.weather_code, isDay: c.is_day == 1, temp: c.temperature_2m, wind: c.wind_speed_10m)

        let h = r.hourly
        var out: [HourForecast] = []
        for i in h.time.indices.dropFirst() {
            guard i < h.temperature_2m.count, i < h.weather_code.count, i < h.is_day.count, i < h.wind_speed_10m.count else { break }
            let m = Mood.from(code: h.weather_code[i], isDay: h.is_day[i] == 1, temp: h.temperature_2m[i], wind: h.wind_speed_10m[i])
            let label = String(h.time[i].suffix(5))
            out.append(HourForecast(id: h.time[i], label: label, temp: Int(h.temperature_2m[i].rounded()), mood: m))
        }
        hours = Array(out.prefix(12))
        updated = Date()
    }

    func searchCity(_ q: String) async -> [CityResult] {
        let enc = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
        guard let url = URL(string: "https://geocoding-api.open-meteo.com/v1/search?count=8&language=it&name=\(enc)"),
              let res = try? await URLSession.shared.data(from: url),
              let r = try? JSONDecoder().decode(GeoResp.self, from: res.0) else { return [] }
        return (r.results ?? []).map {
            CityResult(id: "\($0.id)", name: $0.name,
                       detail: [$0.admin1, $0.country].compactMap { $0 }.joined(separator: ", "),
                       lat: $0.latitude, lon: $0.longitude)
        }
    }

    private func locate() async -> CLLocation? {
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted { return nil }
        return await withTaskGroup(of: CLLocation?.self) { g in
            g.addTask {
                do {
                    for try await u in CLLocationUpdate.liveUpdates() {
                        if let l = u.location { return l }
                        if u.authorizationDenied || u.authorizationDeniedGlobally { return nil }
                    }
                } catch {}
                return nil
            }
            g.addTask {
                try? await Task.sleep(for: .seconds(15))
                return nil
            }
            let first = await g.next() ?? nil
            g.cancelAll()
            return first
        }
    }

    private func placeName(_ loc: CLLocation) async -> String? {
        let marks = try? await CLGeocoder().reverseGeocodeLocation(loc)
        return marks?.first?.locality ?? marks?.first?.name
    }
}

private struct OMResp: Decodable {
    struct Current: Decodable {
        let temperature_2m: Double
        let apparent_temperature: Double
        let weather_code: Int
        let is_day: Int
        let wind_speed_10m: Double
    }
    struct Hourly: Decodable {
        let time: [String]
        let temperature_2m: [Double]
        let weather_code: [Int]
        let is_day: [Int]
        let wind_speed_10m: [Double]
    }
    let current: Current
    let hourly: Hourly
}

private struct GeoResp: Decodable {
    struct R: Decodable {
        let id: Int
        let name: String
        let latitude: Double
        let longitude: Double
        let admin1: String?
        let country: String?
    }
    let results: [R]?
}
