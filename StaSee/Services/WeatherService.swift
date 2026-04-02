import Foundation

actor WeatherService {
    private let forecastURL = "https://api.open-meteo.com/v1/forecast"
    private let latitude = 47.9
    private let longitude = 11.3

    // MARK: - Current Wind

    func fetchWindData() async throws -> WindData {
        var components = URLComponents(string: forecastURL)!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "wind_speed_10m,wind_direction_10m,wind_gusts_10m"),
            URLQueryItem(name: "timezone", value: "Europe/Berlin")
        ]

        let (data, response) = try await URLSession.shared.data(from: components.url!)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ServiceError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)

        guard let current = decoded.current else {
            throw ServiceError.noDataAvailable
        }

        let timestamp = Self.parseISO8601(current.time) ?? Date()

        return WindData(
            speedKmh: current.windSpeed10m,
            directionDegrees: current.windDirection10m,
            gustsKmh: current.windGusts10m,
            timestamp: timestamp
        )
    }

    // MARK: - Daily Wind (past 7 + forecast 7)

    func fetchWindDays() async throws -> [DailyWindEntry] {
        var components = URLComponents(string: forecastURL)!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "daily", value: "wind_speed_10m_max,wind_gusts_10m_max,wind_direction_10m_dominant"),
            URLQueryItem(name: "past_days", value: "7"),
            URLQueryItem(name: "forecast_days", value: "7"),
            URLQueryItem(name: "timezone", value: "Europe/Berlin")
        ]

        let (data, response) = try await URLSession.shared.data(from: components.url!)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ServiceError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)

        guard let daily = decoded.daily else {
            throw ServiceError.noDataAvailable
        }

        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        dayFormatter.timeZone = TimeZone(identifier: "Europe/Berlin")

        let today = Calendar.current.startOfDay(for: Date())

        var entries: [DailyWindEntry] = []
        for i in 0..<daily.time.count {
            guard let date = dayFormatter.date(from: daily.time[i]),
                  let speed = daily.windSpeed10mMax[safe: i] ?? nil,
                  let gusts = daily.windGusts10mMax?[safe: i] ?? nil else { continue }
            let direction = (daily.windDirection10mDominant?[safe: i] ?? nil) ?? 0

            entries.append(DailyWindEntry(
                date: date,
                maxSpeedKmh: speed,
                maxGustsKmh: gusts,
                directionDegrees: direction,
                isForecast: date > today
            ))
        }

        return entries
    }

    // MARK: - Helpers

    private static func parseISO8601(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        return formatter.date(from: string)
    }
}

// MARK: - Error Response

struct OpenMeteoErrorResponse: Codable {
    let error: Bool
    let reason: String
}

enum ServiceError: LocalizedError {
    case invalidResponse
    case parsingFailed
    case noDataAvailable

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Ungueltige Server-Antwort"
        case .parsingFailed: return "Daten konnten nicht gelesen werden"
        case .noDataAvailable: return "Keine aktuellen Daten verfuegbar"
        }
    }
}

extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
