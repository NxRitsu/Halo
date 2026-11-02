import Foundation

/// Minimal client for the Open-Meteo forecast API (https://open-meteo.com/en/docs).
///
/// It needs no key. Only the coordinates are sent, rounded to two decimals: about 1 km, which is
/// finer than the weather models and coarse enough not to point at a building. Requests identify
/// Halo with a User-Agent that links to the repository.
struct OpenMeteoClient: Sendable {
    static let websiteURL = URL(string: "https://open-meteo.com")!
    static let licenseURL = URL(string: "https://creativecommons.org/licenses/by/4.0/")!

    enum ServiceError: Error {
        case unavailable
    }

    private struct Response: Decodable {
        struct Current: Decodable {
            var temperature_2m: Double
            var weather_code: Int
            var is_day: Int
        }

        struct Daily: Decodable {
            var temperature_2m_max: [Double]
            var temperature_2m_min: [Double]
        }

        var current: Current
        var daily: Daily
    }

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.httpCookieStorage = nil
        // The last report is saved on disk by `WeatherCache`.
        configuration.urlCache = nil
        configuration.httpAdditionalHeaders = [
            "User-Agent": "\(AppInfo.name)/\(AppInfo.version) (\(AppInfo.repositoryURL.absoluteString))",
        ]
        return URLSession(configuration: configuration)
    }()

    func report(latitude: Double, longitude: Double) async throws -> WeatherReport {
        guard var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast") else {
            throw ServiceError.unavailable
        }
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.2f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.2f", longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "forecast_days", value: "1"),
            // Decides where the day of the minimum and maximum starts and ends.
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        guard let url = components.url else { throw ServiceError.unavailable }

        let (data, response) = try await session.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw ServiceError.unavailable }
        return try Self.report(from: data, fetchedAt: .now)
    }

    static func report(from data: Data, fetchedAt: Date) throws -> WeatherReport {
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let maximum = decoded.daily.temperature_2m_max.first,
              let minimum = decoded.daily.temperature_2m_min.first
        else { throw ServiceError.unavailable }
        return WeatherReport(
            temperature: decoded.current.temperature_2m,
            code: decoded.current.weather_code,
            isDay: decoded.current.is_day != 0,
            minimum: minimum,
            maximum: maximum,
            fetchedAt: fetchedAt
        )
    }
}

/// The last report, in Application Support.
struct WeatherCache: Sendable {
    private var fileURL: URL {
        URL.applicationSupportDirectory
            .appending(path: AppInfo.name, directoryHint: .isDirectory)
            .appending(path: "Weather.json")
    }

    func load() -> WeatherReport? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(WeatherReport.self, from: data)
    }

    func store(_ report: WeatherReport) {
        guard let data = try? JSONEncoder().encode(report) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    func remove() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
