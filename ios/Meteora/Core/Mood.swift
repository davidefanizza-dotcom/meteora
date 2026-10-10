import SwiftUI

/// Atmosfere musicali derivate dal meteo.
enum Mood: String, CaseIterable, Codable, Identifiable, Hashable {
    case sole, caldo, nuvoloso, pioggia, temporale, neve, nebbia, notte, vento

    var id: String { rawValue }

    var name: String {
        switch self {
        case .sole: "Sole"
        case .caldo: "Caldo"
        case .nuvoloso: "Nuvoloso"
        case .pioggia: "Pioggia"
        case .temporale: "Temporale"
        case .neve: "Neve"
        case .nebbia: "Nebbia"
        case .notte: "Notte serena"
        case .vento: "Vento"
        }
    }

    var desc: String {
        switch self {
        case .sole: "Luce piena, energia positiva"
        case .caldo: "Afa, ritmi estivi e tropicali"
        case .nuvoloso: "Toni morbidi, ascolto rilassato"
        case .pioggia: "Malinconia, acustico e lo-fi"
        case .temporale: "Intensità, suoni potenti"
        case .neve: "Atmosfere ovattate e calde"
        case .nebbia: "Sognante, sospeso, ambient"
        case .notte: "Neon, luci di città e stelle"
        case .vento: "Libertà, strada, movimento"
        }
    }

    var symbol: String {
        switch self {
        case .sole: "sun.max.fill"
        case .caldo: "thermometer.sun.fill"
        case .nuvoloso: "cloud.sun.fill"
        case .pioggia: "cloud.rain.fill"
        case .temporale: "cloud.bolt.rain.fill"
        case .neve: "cloud.snow.fill"
        case .nebbia: "cloud.fog.fill"
        case .notte: "moon.stars.fill"
        case .vento: "wind"
        }
    }

    var color: Color { Color(hex: hexA) }
    var color2: Color { Color(hex: hexB) }

    private var hexA: UInt32 {
        switch self {
        case .sole: 0xFFAE1F
        case .caldo: 0xFF7A2E
        case .nuvoloso: 0x8AA4C8
        case .pioggia: 0x4AA3FF
        case .temporale: 0x9B6BFF
        case .neve: 0xA9D8FF
        case .nebbia: 0xB8B1C6
        case .notte: 0x6D7BFF
        case .vento: 0x3FD6B5
        }
    }

    private var hexB: UInt32 {
        switch self {
        case .sole: 0xFF6A3D
        case .caldo: 0xFF2E63
        case .nuvoloso: 0x5B6B9C
        case .pioggia: 0x3A5BD9
        case .temporale: 0x4A2FB0
        case .neve: 0x6F9FD8
        case .nebbia: 0x7D7A9C
        case .notte: 0xB05CFF
        case .vento: 0x2A8FD9
        }
    }

    /// Parole che, se presenti nel titolo o nell'album, avvicinano un brano a questo meteo.
    var keywords: [String] {
        switch self {
        case .sole: ["sun", "sunny", "sunshine", "summer", "sole", "estate", "happy", "good", "shine", "light", "golden", "day", "dance", "beach", "mare", "smile", "sorriso", "alive", "vibe", "vibes"]
        case .caldo: ["hot", "heat", "fire", "fuoco", "caldo", "tropical", "tropicale", "fiesta", "summer", "estate", "beach", "latino", "bailando", "sweat", "sabbia", "sand"]
        case .nuvoloso: ["cloud", "clouds", "nuvole", "grey", "gray", "sky", "cielo", "dream", "float", "soft", "calm", "slow", "blue", "sunday", "domenica", "lazy"]
        case .pioggia: ["rain", "raining", "rainy", "pioggia", "piove", "tears", "lacrime", "cry", "alone", "solo", "sad", "blue", "memories", "ricordi", "window", "finestra", "slow", "umbrella", "ombrello", "grey", "storm"]
        case .temporale: ["storm", "thunder", "tempesta", "tuono", "lightning", "fulmine", "fire", "dark", "rage", "burn", "wild", "chaos", "war", "power", "hurricane"]
        case .neve: ["snow", "neve", "winter", "inverno", "cold", "freddo", "christmas", "natale", "white", "ice", "frozen", "quiet", "december", "dicembre", "warm"]
        case .nebbia: ["fog", "nebbia", "mist", "haze", "ghost", "dream", "sogno", "lost", "echo", "ambient", "shadow", "ombra", "silence", "silenzio", "fade"]
        case .notte: ["night", "notte", "moon", "luna", "stars", "stelle", "star", "midnight", "mezzanotte", "dream", "late", "city", "neon", "lights", "dark", "sleep", "dormire"]
        case .vento: ["wind", "vento", "free", "libero", "fly", "volare", "run", "correre", "road", "strada", "away", "wild", "air", "aria", "highway"]
        }
    }

    /// Ricerche usate per le nuove scoperte.
    var seeds: [String] {
        switch self {
        case .sole: ["feel good", "summer", "happy", "sunshine pop", "good vibes"]
        case .caldo: ["tropical", "reggaeton", "latin summer", "summer party", "afrobeat"]
        case .nuvoloso: ["chill", "indie chill", "mellow", "soft pop", "chillhop"]
        case .pioggia: ["rainy day", "acoustic", "lofi", "sad songs", "piano"]
        case .temporale: ["epic", "dark", "rock", "intense", "cinematic"]
        case .neve: ["winter", "cozy", "acoustic winter", "piano", "calm"]
        case .nebbia: ["ambient", "dreamy", "atmospheric", "dream pop", "shoegaze"]
        case .notte: ["night drive", "late night", "midnight", "synthwave", "r&b night"]
        case .vento: ["road trip", "indie rock", "driving", "alt rock", "travel"]
        }
    }

    /// Codici meteo WMO di Open-Meteo → atmosfera.
    static func from(code: Int, isDay: Bool, temp: Double, wind: Double) -> Mood {
        if code >= 95 { return .temporale }
        if (71...77).contains(code) || code == 85 || code == 86 { return .neve }
        if code == 45 || code == 48 { return .nebbia }
        if (51...67).contains(code) || (80...82).contains(code) { return .pioggia }
        if wind >= 35 { return .vento }
        if !isDay && code <= 2 { return .notte }
        if temp >= 30 && code <= 2 { return .caldo }
        if code <= 1 { return .sole }
        if !isDay { return .notte }
        return .nuvoloso
    }
}

enum WMO {
    static func text(_ code: Int) -> String {
        switch code {
        case 0: "Sereno"
        case 1: "Quasi sereno"
        case 2: "Parzialmente nuvoloso"
        case 3: "Coperto"
        case 45, 48: "Nebbia"
        case 51, 53, 55: "Pioviggine"
        case 56, 57: "Pioviggine gelata"
        case 61: "Pioggia leggera"
        case 63: "Pioggia"
        case 65: "Pioggia forte"
        case 66, 67: "Pioggia gelata"
        case 71: "Neve leggera"
        case 73: "Neve"
        case 75: "Neve forte"
        case 77: "Granelli di neve"
        case 80, 81: "Rovesci"
        case 82: "Rovesci violenti"
        case 85, 86: "Rovesci di neve"
        case 95: "Temporale"
        case 96, 99: "Temporale con grandine"
        default: "—"
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

func formatTime(_ ms: Double) -> String {
    let s = max(0, Int(ms / 1000))
    return "\(s / 60):" + String(format: "%02d", s % 60)
}
