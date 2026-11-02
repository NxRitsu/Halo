import Foundation

/// The weather at the time of `fetchedAt`. Temperatures are in degrees Celsius.
///
/// This is what gets saved on disk. It deliberately doesn't hold the coordinates it was asked for.
struct WeatherReport: Codable, Equatable, Sendable {
    var temperature: Double
    /// WMO weather interpretation code, as Open-Meteo reports it.
    var code: Int
    var isDay: Bool
    var minimum: Double
    var maximum: Double
    var fetchedAt: Date

    var condition: WeatherCondition { WeatherCondition(code: code) }
    var symbol: String { condition.symbol(isDay: isDay) }
}

/// The WMO weather codes, grouped by what they look like.
enum WeatherCondition: Equatable {
    case clear, partlyCloudy, overcast, fog, drizzle, rain, heavyRain, freezingRain, snow, thunderstorm, unknown

    init(code: Int) {
        switch code {
        case 0, 1: self = .clear
        case 2: self = .partlyCloudy
        case 3: self = .overcast
        case 45, 48: self = .fog
        case 51, 53, 55: self = .drizzle
        case 61, 63, 80, 81: self = .rain
        case 65, 82: self = .heavyRain
        case 56, 57, 66, 67: self = .freezingRain
        case 71, 73, 75, 77, 85, 86: self = .snow
        case 95, 96, 99: self = .thunderstorm
        default: self = .unknown
        }
    }

    func symbol(isDay: Bool) -> String {
        switch self {
        case .clear: isDay ? "sun.max.fill" : "moon.stars.fill"
        case .partlyCloudy: isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case .overcast: "cloud.fill"
        case .fog: "cloud.fog.fill"
        case .drizzle: "cloud.drizzle.fill"
        case .rain: "cloud.rain.fill"
        case .heavyRain: "cloud.heavyrain.fill"
        case .freezingRain: "cloud.sleet.fill"
        case .snow: "cloud.snow.fill"
        case .thunderstorm: "cloud.bolt.rain.fill"
        case .unknown: "thermometer.medium"
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .clear: "Clear sky"
        case .partlyCloudy: "Partly cloudy"
        case .overcast: "Overcast"
        case .fog: "Fog"
        case .drizzle: "Drizzle"
        case .rain: "Rain"
        case .heavyRain: "Heavy rain"
        case .freezingRain: "Freezing rain"
        case .snow: "Snow"
        case .thunderstorm: "Thunderstorm"
        case .unknown: "Unknown"
        }
    }
}

enum WeatherStatus: Equatable {
    case disabled
    case starting
    case active
    case denied
    /// Location Services are turned off for the whole Mac.
    case locationOff
    case locationNotFound
    case unavailable(retryAt: Date)
}

/// Unit of the temperatures on screen.
enum TemperatureUnit: String, CaseIterable, Identifiable {
    /// Follows System Settings → General → Language & Region.
    case system
    case celsius
    case fahrenheit

    var id: String { rawValue }

    /// A whole number of degrees, without the letter of the unit.
    func text(celsius: Double) -> String {
        let value = usesFahrenheit ? celsius * 9 / 5 + 32 : celsius
        return "\(Int(value.rounded()))°"
    }

    private var usesFahrenheit: Bool {
        switch self {
        case .celsius: false
        case .fahrenheit: true
        case .system:
            // There's no public API for this setting. Without it, the region decides.
            switch UserDefaults.standard.string(forKey: "AppleTemperatureUnit") {
            case "Fahrenheit": true
            case "Celsius": false
            default: Locale.current.measurementSystem == .us
            }
        }
    }
}
