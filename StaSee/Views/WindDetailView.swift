import SwiftUI

struct WindDetailView: View {
    @State private var entries: [DailyWindEntry] = []
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

    // MARK: - Sections

    @ViewBuilder
    private var pastSection: some View {
        let pastEntries = entries.filter { !$0.isForecast && !$0.isToday }
            .sorted { $0.date > $1.date }

        if !pastEntries.isEmpty {
            sectionHeader(title: "Letzte 7 Tage", icon: "clock.arrow.counterclockwise")

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
            entries = try await weatherService.fetchWindDays()
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
