import Foundation
import SwiftUI

@MainActor
final class LakeViewModel: ObservableObject {
    @Published var waterTemperature: WaterTemperature?
    @Published var waterLevel: WaterLevel?
    @Published var windData: WindData?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastUpdate: Date?

    private let weatherService = WeatherService()
    private let gkdService = GKDService()
    private var refreshTimer: Timer?

    func loadData() async {
        isLoading = true
        errorMessage = nil

        async let tempResult = gkdService.fetchWaterTemperature()
        async let levelResult = gkdService.fetchWaterLevel()
        async let windResult = weatherService.fetchWindData()

        do {
            waterTemperature = try await tempResult
        } catch {
            print("Temperatur-Fehler: \(error.localizedDescription)")
        }

        do {
            waterLevel = try await levelResult
        } catch {
            print("Wasserstand-Fehler: \(error.localizedDescription)")
        }

        do {
            windData = try await windResult
        } catch {
            print("Wind-Fehler: \(error.localizedDescription)")
        }

        if waterTemperature == nil && waterLevel == nil && windData == nil {
            errorMessage = "Keine Daten verfuegbar. Bitte Internetverbindung pruefen."
        } else {
            lastUpdate = Date()
        }

        isLoading = false
    }

    func startAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.loadData()
            }
        }
    }

    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
}
