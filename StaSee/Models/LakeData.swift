import Foundation

// MARK: - Constants

enum StarnbergerSee {
    /// Pegelnullpunktsh\u{00F6}he in meters NHN
    static let pegelnullpunkt: Double = 583.43
}

// MARK: - Time Range

enum TimeRange: String, CaseIterable, Identifiable {
    case week = "1 Woche"
    case sixMonths = "6 Monate"
    case year = "12 Monate"

    var id: String { rawValue }

    var days: Int {
        switch self {
        case .week: return 7
        case .sixMonths: return 183
        case .year: return 365
        }
    }
}

// MARK: - Current Data

struct WindData {
    let speedKmh: Double
    let directionDegrees: Double
    let gustsKmh: Double
    let timestamp: Date

    var directionText: String {
        let directions = ["N", "NNO", "NO", "ONO", "O", "OSO", "SO", "SSO",
                          "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let index = Int((directionDegrees + 11.25) / 22.5) % 16
        return directions[index]
    }
}

struct WaterTemperature {
    let temperatureCelsius: Double
    let timestamp: Date
}

struct WaterLevel {
    /// Water level in cm relative to Pegelnullpunkt (583,43 m NHN)
    let levelCm: Double
    let timestamp: Date
}

// MARK: - Historical Data

struct ChartDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
    let secondaryValue: Double?

    init(date: Date, value: Double, secondaryValue: Double? = nil) {
        self.date = date
        self.value = value
        self.secondaryValue = secondaryValue
    }
}

// MARK: - Daily Wind

struct DailyWindEntry: Identifiable {
    let id = UUID()
    let date: Date
    let maxSpeedKmh: Double
    let maxGustsKmh: Double
    let directionDegrees: Double
    let isForecast: Bool

    var directionText: String {
        let directions = ["N", "NNO", "NO", "ONO", "O", "OSO", "SO", "SSO",
                          "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let index = Int((directionDegrees + 11.25) / 22.5) % 16
        return directions[index]
    }

    var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }
}

// MARK: - Metric Type

enum MetricType: String, Identifiable {
    case temperature = "Wassertemperatur"
    case waterLevel = "Wasserstand"
    case wind = "Wind"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .temperature: return "thermometer.medium"
        case .waterLevel: return "water.waves"
        case .wind: return "wind"
        }
    }

    var unit: String {
        switch self {
        case .temperature: return "\u{00B0}C"
        case .waterLevel: return "cm"
        case .wind: return "km/h"
        }
    }
}

// MARK: - API Response Models

struct OpenMeteoResponse: Codable {
    let current: CurrentWeather?
    let hourly: HourlyWeather?
    let daily: DailyWeather?

    struct CurrentWeather: Codable {
        let time: String
        let windSpeed10m: Double
        let windDirection10m: Double
        let windGusts10m: Double

        enum CodingKeys: String, CodingKey {
            case time
            case windSpeed10m = "wind_speed_10m"
            case windDirection10m = "wind_direction_10m"
            case windGusts10m = "wind_gusts_10m"
        }
    }

    struct HourlyWeather: Codable {
        let time: [String]
        let windSpeed10m: [Double]
        let windGusts10m: [Double]?

        enum CodingKeys: String, CodingKey {
            case time
            case windSpeed10m = "wind_speed_10m"
            case windGusts10m = "wind_gusts_10m"
        }
    }

    struct DailyWeather: Codable {
        let time: [String]
        let windSpeed10mMax: [Double?]
        let windGusts10mMax: [Double?]?
        let windDirection10mDominant: [Double?]?

        enum CodingKeys: String, CodingKey {
            case time
            case windSpeed10mMax = "wind_speed_10m_max"
            case windGusts10mMax = "wind_gusts_10m_max"
            case windDirection10mDominant = "wind_direction_10m_dominant"
        }
    }
}
