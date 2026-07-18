import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = LakeViewModel()
    @State private var showingInfo = false
    // UI-test hooks: launch with "-openDepthMap" / "-openWind" to jump straight to a subview.
    @State private var showingDepthMap = ProcessInfo.processInfo.arguments.contains("-openDepthMap")
    @State private var showingWind = ProcessInfo.processInfo.arguments.contains("-openWind")

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
            .navigationDestination(isPresented: $showingDepthMap) {
                DepthMapView(waterLevel: viewModel.waterLevel)
            }
            .navigationDestination(isPresented: $showingWind) {
                WindDetailView()
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

        NavigationLink {
            DepthMapView(waterLevel: viewModel.waterLevel)
        } label: {
            depthMapCard
        }
        .buttonStyle(.plain)

        if viewModel.trafficToLake != nil || viewModel.trafficToMunich != nil {
            trafficCard
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

    private var depthMapCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "map.fill")
                .font(.title2)
                .foregroundStyle(.indigo)
            VStack(alignment: .leading, spacing: 2) {
                Text("Tiefenkarte")
                    .font(.headline)
                Text("Wassertiefe an deiner Position \u{2013} live auf dem See")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var trafficCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "car.fill")
                    .font(.title2)
                    .foregroundStyle(.mint)
                Text("Anfahrt")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Aktuelle Verkehrslage")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if let eta = viewModel.trafficToLake {
                trafficRow(eta)
            }
            if viewModel.trafficToLake != nil && viewModel.trafficToMunich != nil {
                Divider()
            }
            if let eta = viewModel.trafficToMunich {
                trafficRow(eta)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func trafficRow(_ eta: RouteETA) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(eta.originName)
                        .font(.subheadline.bold())
                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(eta.destinationName)
                        .font(.subheadline.bold())
                }
                Text(String(format: "%.0f km%@", eta.distanceKm,
                            eta.routeName.map { " \u{00FC}ber \($0)" } ?? ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(String(format: "%.0f Min.", eta.travelMinutes))
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(trafficColor(eta))
        }
    }

    private func trafficColor(_ eta: RouteETA) -> Color {
        switch eta.congestionColor {
        case "green": return .green
        case "orange": return .orange
        default: return .red
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
