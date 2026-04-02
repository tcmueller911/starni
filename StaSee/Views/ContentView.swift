import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = LakeViewModel()
    @State private var showingInfo = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if viewModel.isLoading && viewModel.lastUpdate == nil {
                        loadingView
                    } else if let error = viewModel.errorMessage, viewModel.lastUpdate == nil {
                        errorView(error)
                    } else {
                        dataCards
                    }
                }
                .padding()
            }
            .refreshable {
                await viewModel.loadData()
            }
            .navigationTitle("Starnberger See")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        showingInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                }
            }
            .sheet(isPresented: $showingInfo) {
                InfoView()
            }
        }
        .task {
            await viewModel.loadData()
            viewModel.startAutoRefresh()
        }
    }

    @ViewBuilder
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Lade aktuelle Daten...")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.slash")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Erneut versuchen") {
                Task { await viewModel.loadData() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }

    @ViewBuilder
    private var dataCards: some View {
        if let temp = viewModel.waterTemperature {
            let color = temperatureColor(temp.temperatureCelsius)
            NavigationLink {
                HistoryChartView(metricType: .temperature, accentColor: color)
            } label: {
                DataCardView(
                    title: "Wassertemperatur",
                    icon: "thermometer.medium",
                    value: String(format: "%.1f", temp.temperatureCelsius),
                    unit: "\u{00B0}C",
                    details: [],
                    timestamp: temp.timestamp,
                    accentColor: color,
                )
            }
            .buttonStyle(.plain)
        }

        if let level = viewModel.waterLevel {
            NavigationLink {
                HistoryChartView(metricType: .waterLevel, accentColor: .blue)
            } label: {
                DataCardView(
                    title: "Wasserstand",
                    icon: "water.waves",
                    value: String(format: "%+.0f", level.levelCm),
                    unit: "cm",
                    details: [
                        (label: "Pegel-Nullpunkt", value: "583,43 m NHN")
                    ],
                    timestamp: level.timestamp,
                    accentColor: .blue,
                )
            }
            .buttonStyle(.plain)
        }

        if let wind = viewModel.windData {
            NavigationLink {
                WindDetailView()
            } label: {
                DataCardView(
                    title: "Wind",
                    icon: "wind",
                    value: String(format: "%.1f", wind.speedKmh),
                    unit: "km/h",
                    details: [
                        (label: "Richtung", value: "\(wind.directionText) (\(Int(wind.directionDegrees))\u{00B0})"),
                        (label: "Boeen", value: String(format: "%.1f km/h", wind.gustsKmh))
                    ],
                    timestamp: wind.timestamp,
                    accentColor: .teal,
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func temperatureColor(_ temp: Double) -> Color {
        switch temp {
        case ..<10: return .blue
        case 10..<18: return .cyan
        case 18..<22: return .green
        case 22...: return .orange
        default: return .blue
        }
    }
}
