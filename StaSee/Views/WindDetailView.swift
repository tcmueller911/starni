import SwiftUI
import Charts

struct WindDetailView: View {
    @State private var entries: [DailyWindEntry] = []
    @State private var hourly: [HourlyWindEntry] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let weatherService = WeatherService()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if isLoading {
                    ProgressView("Lade Winddaten...")
                        .frame(maxWidth: .infinity, minHeight: 300)
                } else if let error = errorMessage {
                    errorView(error)
                } else {
                    hourlySection
                    pastSection
                    forecastSection
                }
            }
            .padding()
        }
        .navigationTitle("Wind")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .task {
            await loadData()
        }
    }

    // MARK: - Hourly (today)

    @ViewBuilder
    private var hourlySection: some View {
        let calendar = Calendar.current
        let todayHours = hourly.filter { calendar.isDateInToday($0.date) }

        if !todayHours.isEmpty {
            sectionHeader(title: "Windverlauf heute", icon: "clock")

            VStack(alignment: .leading, spacing: 12) {
                Chart {
                    ForEach(todayHours) { h in
                        AreaMark(
                            x: .value("Zeit", h.date),
                            y: .value("Wind", h.speedKmh)
                        )
                        .foregroundStyle(
                            LinearGradient(colors: [.teal.opacity(0.35), .teal.opacity(0.05)],
                                           startPoint: .top, endPoint: .bottom)
                        )
                        .interpolationMethod(.catmullRom)

                        LineMark(
                            x: .value("Zeit", h.date),
                            y: .value("Wind", h.speedKmh)
                        )
                        .foregroundStyle(.teal)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.catmullRom)

                        LineMark(
                            x: .value("Zeit", h.date),
                            y: .value("Boeen", h.gustsKmh),
                            series: .value("Serie", "Boeen")
                        )
                        .foregroundStyle(.orange.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .interpolationMethod(.catmullRom)
                    }

                    RuleMark(x: .value("Jetzt", Date()))
                        .foregroundStyle(.secondary.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .annotation(position: .topLeading, alignment: .leading) {
                            Text("Jetzt")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: 4)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.hour())
                    }
                }
                .chartYAxisLabel("km/h")
                .frame(height: 190)

                // legend
                HStack(spacing: 16) {
                    HStack(spacing: 5) {
                        Rectangle().fill(.teal).frame(width: 16, height: 3).clipShape(Capsule())
                        Text("Wind").font(.caption2).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 5) {
                        Rectangle().fill(.orange.opacity(0.7)).frame(width: 16, height: 3).clipShape(Capsule())
                        Text("Boeen").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                // direction arrows every 3 hours
                let arrowHours = todayHours.enumerated().filter { $0.offset % 3 == 0 }.map(\.element)
                HStack(spacing: 0) {
                    ForEach(arrowHours) { h in
                        VStack(spacing: 3) {
                            Image(systemName: "location.north.fill")
                                .font(.caption)
                                .foregroundStyle(.teal)
                                .rotationEffect(.degrees(h.directionDegrees))
                            Text(h.date, format: .dateTime.hour())
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .opacity(h.isPast ? 0.45 : 1.0)
                    }
                }
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var pastSection: some View {
        let pastEntries = entries.filter { !$0.isForecast && !$0.isToday }
            .sorted { $0.date > $1.date }

        if !pastEntries.isEmpty {
            sectionHeader(title: "Letzte 7 Tage", icon: "clock.arrow.circlepath")

            ForEach(pastEntries) { entry in
                WindDayCard(entry: entry)
            }
        }
    }

    @ViewBuilder
    private var forecastSection: some View {
        let todayAndFuture = entries.filter { $0.isForecast || $0.isToday }
            .sorted { $0.date < $1.date }

        if !todayAndFuture.isEmpty {
            sectionHeader(title: "Vorhersage", icon: "arrow.forward.circle")

            ForEach(todayAndFuture) { entry in
                WindDayCard(entry: entry)
            }
        }
    }

    private func sectionHeader(title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.headline)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Erneut versuchen") {
                Task { await loadData() }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }

    // MARK: - Data

    private func loadData() async {
        isLoading = true
        errorMessage = nil

        do {
            async let daysResult = weatherService.fetchWindDays()
            async let hourlyResult = weatherService.fetchHourlyWind()
            entries = try await daysResult
            hourly = (try? await hourlyResult) ?? []
            if entries.isEmpty {
                errorMessage = "Keine Winddaten verfuegbar."
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

// MARK: - Day Card

struct WindDayCard: View {
    let entry: DailyWindEntry

    private var dayLabel: String {
        if entry.isToday { return "Heute" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "EEEE"
        return formatter.string(from: entry.date).capitalized
    }

    private var dateLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "d. MMM"
        return formatter.string(from: entry.date)
    }

    private var windIntensityColor: Color {
        switch entry.maxSpeedKmh {
        case ..<15: return .teal
        case 15..<30: return .cyan
        case 30..<50: return .orange
        default: return .red
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            // Direction arrow
            ZStack {
                Circle()
                    .fill(windIntensityColor.opacity(0.15))
                    .frame(width: 46, height: 46)
                Image(systemName: "location.north.fill")
                    .font(.title3)
                    .foregroundStyle(windIntensityColor)
                    .rotationEffect(.degrees(entry.directionDegrees))
            }

            // Day + date
            VStack(alignment: .leading, spacing: 2) {
                Text(dayLabel)
                    .font(.subheadline.bold())
                    .foregroundStyle(entry.isToday ? .primary : .primary)
                Text(dateLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 80, alignment: .leading)

            Spacer()

            // Wind values
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "wind")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.0f km/h", entry.maxSpeedKmh))
                        .font(.subheadline.bold().monospacedDigit())
                }

                HStack(spacing: 4) {
                    Text("Boeen")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.0f km/h", entry.maxGustsKmh))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            // Direction label
            Text(entry.directionText)
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(windIntensityColor)
                .frame(width: 32)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(.regularMaterial)
                .overlay {
                    if entry.isToday {
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(windIntensityColor.opacity(0.4), lineWidth: 1.5)
                    }
                }
        }
    }
}
