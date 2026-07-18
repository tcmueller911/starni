import Foundation
import MapKit

/// Live driving times Munich <-> Starnberg via MapKit directions,
/// which reflect the current traffic situation. No API key required.
actor TrafficService {
    private static let munich = CLLocationCoordinate2D(latitude: 48.1374, longitude: 11.5755)     // Marienplatz
    private static let starnberg = CLLocationCoordinate2D(latitude: 47.9983, longitude: 11.3407)  // Starnberg (See/Bahnhof)

    func fetchBothDirections() async -> (toLake: RouteETA?, toMunich: RouteETA?) {
        async let toLake = route(from: Self.munich, fromName: "M\u{00FC}nchen",
                                 to: Self.starnberg, toName: "Starnberg")
        async let toMunich = route(from: Self.starnberg, fromName: "Starnberg",
                                   to: Self.munich, toName: "M\u{00FC}nchen")
        return (await toLake, await toMunich)
    }

    private func route(from origin: CLLocationCoordinate2D, fromName: String,
                       to destination: CLLocationCoordinate2D, toName: String) async -> RouteETA? {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = .automobile
        request.requestsAlternateRoutes = false
        request.departureDate = Date()

        do {
            let response = try await MKDirections(request: request).calculate()
            guard let best = response.routes.min(by: { $0.expectedTravelTime < $1.expectedTravelTime }) else {
                return nil
            }
            return RouteETA(
                originName: fromName,
                destinationName: toName,
                travelMinutes: best.expectedTravelTime / 60.0,
                distanceKm: best.distance / 1000.0,
                routeName: best.name.isEmpty ? nil : best.name,
                timestamp: Date()
            )
        } catch {
            return nil
        }
    }
}
