import SwiftUI
import Charts

struct HistoryChartView: View {
    let metricType: MetricType
    let accentColor: Color

    @State private var dataPoints: [ChartDataPoint] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedPoint: ChartDataPoint?
    @State private var selectedRange: TimeRange = .week

    private let gkdService = GKDService()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                currentSummaryCard
                timeRangePicker
                chartSection
                statsSection
                if metricType == .waterLevel {
                    referenceNote
                }
            }
            .padding()
        }
        .navigationTitle(metricType.rawValue)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .task {
            await loadHistory()
        }
    }

    // MARK: - Summary Card

    @ViewBuilder
    private var currentSummaryCard: some View {
        if let latest = dataPoints.last {
            HStack {
                Image(systemName: metricType.icon)
                    .font(.title)
                    .foregroundStyle(accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Aktueller Wert")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(formattedValue(latest.value))
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(accentColor)
                        Text(metricType.unit)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: - Time Range Picker

    private var timeRangePicker: some View {
        Picker("Zeitraum", selection: $selectedRange) {
            ForEach(TimeRange.allCases) { range in
                Text(range.rawValue).tag(range)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: selectedRange) { _ in
            Task { await loadHistory() }
        }
    }

    // MARK: - Chart

    @ViewBuilder
    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Verlauf (\(selectedRange.rawValue))")
                .font(.headline)
                .foregroundStyle(.secondary)

            if isLoading {
                ProgressView("Lade Verlaufsdaten...")
                    .frame(maxWidth: .infinity, minHeight: 250)
            } else if let error = errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                    Text(error)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Erneut versuchen") {
                        Task { await loadHistory() }
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, minHeight: 250)
            } else {
                chartContent
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var chartContent: some View {
        let displayPoints = downsample(dataPoints, targetCount: 250)

        Chart {
            ForEach(displayPoints) { point in
                LineMark(
                    x: .value("Zeit", point.date),
                    y: .value(metricType.rawValue, point.value)
                )
                .foregroundStyle(accentColor.gradient)
                .interpolationMethod(.catmullRom)
            }

            if let selected = selectedPoint {
                RuleMark(x: .value("Auswahl", selected.date))
                    .foregroundStyle(.secondary.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, spacing: 4) {
                        VStack(spacing: 2) {
                            Text(formattedValue(selected.value) + " " + metricType.unit)
                                .font(.caption.bold())
                            Text(selected.date, format: dateFormat)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(6)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                    .foregroundStyle(.secondary.opacity(0.3))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(formattedValue(v))
                            .font(.caption2)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: xAxisStride.component, count: xAxisStride.count)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date, format: xAxisLabelFormat)
                            .font(.caption2)
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { _ in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { drag in
                                let x = drag.location.x
                                guard let date: Date = proxy.value(atX: x) else { return }
                                selectedPoint = findClosestPoint(to: date, in: displayPoints)
                            }
                            .onEnded { _ in
                                selectedPoint = nil
                            }
                    )
            }
        }
        .frame(height: 250)
    }

    // MARK: - Statistics

    @ViewBuilder
    private var statsSection: some View {
        if !dataPoints.isEmpty {
            let values = dataPoints.map(\.value)
            let minVal = values.min() ?? 0
            let maxVal = values.max() ?? 0
            let avgVal = values.reduce(0, +) / Double(values.count)

            VStack(alignment: .leading, spacing: 8) {
                Text("Statistik (\(selectedRange.rawValue))")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 0) {
                    statItem(label: "Min", value: formattedValue(minVal), unit: metricType.unit, color: .blue)
                    Divider().frame(height: 40)
                    statItem(label: "Durchschnitt", value: formattedValue(avgVal), unit: metricType.unit, color: accentColor)
                    Divider().frame(height: 40)
                    statItem(label: "Max", value: formattedValue(maxVal), unit: metricType.unit, color: .red)
                }
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func statItem(label: String, value: String, unit: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.title3.bold())
                    .foregroundStyle(color)
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Reference Note

    private var referenceNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text("Pegelnullpunktsh\u{00F6}he: 583,43 m NHN")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Data Loading

    private func loadHistory() async {
        isLoading = true
        errorMessage = nil
        selectedPoint = nil

        do {
            switch metricType {
            case .temperature:
                dataPoints = try await gkdService.fetchTemperatureHistory(days: selectedRange.days)
            case .waterLevel:
                dataPoints = try await gkdService.fetchWaterLevelHistory(days: selectedRange.days)
            case .wind:
                break // Wind uses WindDetailView
            }

            if dataPoints.isEmpty && metricType != .wind {
                errorMessage = "Keine Verlaufsdaten verfuegbar."
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Formatting Helpers

    private func formattedValue(_ value: Double) -> String {
        switch metricType {
        case .temperature: return String(format: "%.1f", value)
        case .waterLevel: return String(format: "%+.0f", value)
        case .wind: return String(format: "%.1f", value)
        }
    }

    private var dateFormat: Date.FormatStyle {
        switch selectedRange {
        case .week:
            return .dateTime.day().month().hour().minute()
        case .sixMonths, .year:
            return .dateTime.day().month(.abbreviated)
        }
    }

    private var xAxisStride: (component: Calendar.Component, count: Int) {
        switch selectedRange {
        case .week: return (.day, 1)
        case .sixMonths: return (.month, 1)
        case .year: return (.month, 2)
        }
    }

    private var xAxisLabelFormat: Date.FormatStyle {
        switch selectedRange {
        case .week:
            return .dateTime.weekday(.abbreviated).day()
        case .sixMonths:
            return .dateTime.month(.abbreviated)
        case .year:
            return .dateTime.month(.abbreviated).year(.twoDigits)
        }
    }

    // MARK: - Helpers

    private func downsample(_ points: [ChartDataPoint], targetCount: Int) -> [ChartDataPoint] {
        guard points.count > targetCount else { return points }
        let step = Double(points.count) / Double(targetCount)
        return stride(from: 0.0, to: Double(points.count), by: step).compactMap { i in
            let index = Int(i)
            guard index < points.count else { return nil }
            return points[index]
        }
    }

    private func findClosestPoint(to date: Date, in points: [ChartDataPoint]) -> ChartDataPoint? {
        points.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) })
    }
}
