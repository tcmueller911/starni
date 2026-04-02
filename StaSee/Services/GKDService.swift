import Foundation

actor GKDService {
    private let stationID = "16663002"
    private let baseURL = "https://www.gkd.bayern.de/de/seen"

    // MARK: - Current Values

    func fetchWaterTemperature() async throws -> WaterTemperature {
        let today = Self.todayString()
        let urlString = "\(baseURL)/wassertemperatur/isar/starnberg-\(stationID)/messwerte/tabelle?beginn=\(today)&ende=\(today)"

        let html = try await fetchHTML(from: urlString)
        return try parseTemperature(from: html)
    }

    func fetchWaterLevel() async throws -> WaterLevel {
        let today = Self.todayString()
        let urlString = "\(baseURL)/wasserstand/isar/starnberg-\(stationID)/messwerte/tabelle?beginn=\(today)&ende=\(today)"

        let html = try await fetchHTML(from: urlString)
        return try parseWaterLevel(from: html)
    }

    // MARK: - Historical Values

    func fetchTemperatureHistory(days: Int = 7) async throws -> [ChartDataPoint] {
        let (start, end) = Self.dateRange(days: days)
        let urlString = "\(baseURL)/wassertemperatur/isar/starnberg-\(stationID)/messwerte/tabelle?beginn=\(start)&ende=\(end)"

        let html = try await fetchHTML(from: urlString)
        let isDailyFormat = detectDailyFormat(html: html)
        let rows = extractAllTableRows(from: html)

        if isDailyFormat {
            // Daily format: date (dd.MM.yyyy), avg, max, min
            return rows.compactMap { (dateStr, valueStr) in
                guard let value = parseGermanDouble(valueStr),
                      let date = parseGKDDate(dateStr) else { return nil }
                // Filter out implausible temperature values
                guard value > -10.0 && value < 40.0 else { return nil }
                return ChartDataPoint(date: date, value: value)
            }.reversed()
        } else {
            // 15-min format: date (dd.MM.yyyy HH:mm), value
            return rows.compactMap { (dateStr, valueStr) in
                guard let value = parseGermanDouble(valueStr),
                      let date = parseGKDDate(dateStr) else { return nil }
                guard value > -10.0 && value < 40.0 else { return nil }
                return ChartDataPoint(date: date, value: value)
            }.reversed()
        }
    }

    func fetchWaterLevelHistory(days: Int = 7) async throws -> [ChartDataPoint] {
        let (start, end) = Self.dateRange(days: days)
        let urlString = "\(baseURL)/wasserstand/isar/starnberg-\(stationID)/messwerte/tabelle?beginn=\(start)&ende=\(end)"

        let html = try await fetchHTML(from: urlString)
        let rows = extractAllTableRows(from: html)

        let points: [ChartDataPoint] = rows.compactMap { (dateStr, valueStr) in
            guard let rawMeters = parseGermanDouble(valueStr),
                  let date = parseGKDDate(dateStr) else { return nil }
            // Filter out invalid readings (e.g. 0.00 m NHN from sensor errors)
            guard rawMeters > 580.0 && rawMeters < 590.0 else { return nil }
            let relativeCm = (rawMeters - StarnbergerSee.pegelnullpunkt) * 100.0
            return ChartDataPoint(date: date, value: relativeCm)
        }.reversed()

        // For large datasets (6/12 months), aggregate to daily averages
        if days > 14 && points.count > 2000 {
            return aggregateToDailyAverages(points)
        }

        return points
    }

    // MARK: - Network

    private func fetchHTML(from urlString: String) async throws -> String {
        guard let url = URL(string: urlString) else {
            throw ServiceError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        request.setValue("de-DE,de;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.timeoutInterval = 60 // longer timeout for large responses

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ServiceError.invalidResponse
        }

        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw ServiceError.parsingFailed
        }

        return html
    }

    // MARK: - Format Detection

    /// GKD switches to daily format for longer periods (>~2 weeks for temperature).
    /// Daily format has dates without time (dd.MM.yyyy) and multiple value columns.
    private func detectDailyFormat(html: String) -> Bool {
        // Check the header for "Maximum" or "Minimum" columns (only present in daily mode)
        return html.contains("Maximum") && html.contains("Minimum")
    }

    // MARK: - Parsing (single row)

    private func parseTemperature(from html: String) throws -> WaterTemperature {
        guard let (dateString, valueString) = extractFirstTableRow(from: html) else {
            throw ServiceError.noDataAvailable
        }

        guard let temp = parseGermanDouble(valueString),
              let timestamp = parseGKDDate(dateString) else {
            throw ServiceError.parsingFailed
        }

        return WaterTemperature(temperatureCelsius: temp, timestamp: timestamp)
    }

    private func parseWaterLevel(from html: String) throws -> WaterLevel {
        guard let (dateString, valueString) = extractFirstTableRow(from: html) else {
            throw ServiceError.noDataAvailable
        }

        guard let rawMeters = parseGermanDouble(valueString),
              let timestamp = parseGKDDate(dateString) else {
            throw ServiceError.parsingFailed
        }

        let relativeCm = (rawMeters - StarnbergerSee.pegelnullpunkt) * 100.0
        return WaterLevel(levelCm: relativeCm, timestamp: timestamp)
    }

    // MARK: - HTML Table Parsing

    private func extractFirstTableRow(from html: String) -> (date: String, value: String)? {
        let rows = extractAllTableRows(from: html)
        return rows.first
    }

    private func extractAllTableRows(from html: String) -> [(date: String, value: String)] {
        guard let tbodyRange = html.range(of: "<tbody>"),
              let tbodyEndRange = html.range(of: "</tbody>") else { return [] }

        let tbody = String(html[tbodyRange.upperBound..<tbodyEndRange.lowerBound])
        var results: [(String, String)] = []

        let rowParts = tbody.components(separatedBy: "<tr")
        for part in rowParts {
            guard part.contains("<td") else { continue }

            let tdValues = extractTdValues(from: part)
            guard tdValues.count >= 2 else { continue }

            let dateStr = tdValues[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let valueStr = tdValues[1].trimmingCharacters(in: .whitespacesAndNewlines)

            if !dateStr.isEmpty && !valueStr.isEmpty {
                results.append((dateStr, valueStr))
            }
        }

        return results
    }

    private func extractTdValues(from rowHTML: String) -> [String] {
        var values: [String] = []
        var remaining = rowHTML

        while let tdStart = remaining.range(of: "<td") {
            let afterTdTag = remaining[tdStart.lowerBound...]
            guard let contentStart = afterTdTag.range(of: ">"),
                  let contentEnd = remaining[contentStart.upperBound...].range(of: "</td>") else {
                break
            }
            let content = String(remaining[contentStart.upperBound..<contentEnd.lowerBound])
            values.append(content)
            remaining = String(remaining[contentEnd.upperBound...])
        }

        return values
    }

    // MARK: - Daily Aggregation

    /// Aggregates 15-min data points into daily averages for smoother long-term charts.
    private func aggregateToDailyAverages(_ points: [ChartDataPoint]) -> [ChartDataPoint] {
        let calendar = Calendar.current
        var dailyBuckets: [DateComponents: [Double]] = [:]
        var bucketOrder: [DateComponents] = []

        for point in points {
            let components = calendar.dateComponents([.year, .month, .day], from: point.date)
            if dailyBuckets[components] == nil {
                bucketOrder.append(components)
            }
            dailyBuckets[components, default: []].append(point.value)
        }

        return bucketOrder.compactMap { components in
            guard let values = dailyBuckets[components],
                  let date = calendar.date(from: components) else { return nil }
            let avg = values.reduce(0, +) / Double(values.count)
            return ChartDataPoint(date: date, value: avg)
        }
    }

    // MARK: - Utilities

    private func parseGermanDouble(_ string: String) -> Double? {
        let cleaned = string.replacingOccurrences(of: ",", with: ".")
        return Double(cleaned)
    }

    /// Parses both "dd.MM.yyyy HH:mm" (15-min) and "dd.MM.yyyy" (daily) formats.
    private func parseGKDDate(_ string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.timeZone = TimeZone(identifier: "Europe/Berlin")

        // Try 15-min format first (with time)
        if trimmed.count > 10 {
            formatter.dateFormat = "dd.MM.yyyy HH:mm"
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }

        // Fall back to daily format (no time)
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter.date(from: trimmed)
    }

    private static func todayString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy"
        formatter.timeZone = TimeZone(identifier: "Europe/Berlin")
        return formatter.string(from: Date())
    }

    private static func dateRange(days: Int) -> (start: String, end: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy"
        formatter.timeZone = TimeZone(identifier: "Europe/Berlin")

        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -days, to: end) ?? end

        return (formatter.string(from: start), formatter.string(from: end))
    }
}
