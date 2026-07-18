import SwiftUI
import MapKit

// MARK: - Overlay

final class BathymetryOverlay: NSObject, MKOverlay {
    let coordinate: CLLocationCoordinate2D
    let boundingMapRect: MKMapRect
    let image: CGImage

    init(service: BathymetryService, image: CGImage) {
        let (nw, se) = service.region
        let topLeft = MKMapPoint(nw)
        let bottomRight = MKMapPoint(se)
        boundingMapRect = MKMapRect(
            x: topLeft.x, y: topLeft.y,
            width: bottomRight.x - topLeft.x,
            height: bottomRight.y - topLeft.y
        )
        coordinate = CLLocationCoordinate2D(
            latitude: (nw.latitude + se.latitude) / 2,
            longitude: (nw.longitude + se.longitude) / 2
        )
        self.image = image
    }
}

final class BathymetryOverlayRenderer: MKOverlayRenderer {
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let overlay = overlay as? BathymetryOverlay else { return }
        let drawRect = rect(for: overlay.boundingMapRect)
        context.saveGState()
        context.translateBy(x: drawRect.minX, y: drawRect.minY)
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: 0, y: -drawRect.height)
        context.interpolationQuality = .high
        context.draw(overlay.image, in: CGRect(origin: .zero, size: drawRect.size))
        context.restoreGState()
    }
}

// MARK: - Map Representable

struct DepthMapRepresentable: UIViewRepresentable {
    let service: BathymetryService
    let overlayImage: CGImage?
    @Binding var tappedCoordinate: CLLocationCoordinate2D?
    @Binding var centerOnUserTrigger: Int

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.mapType = .mutedStandard
        mapView.pointOfInterestFilter = .excludingAll
        mapView.showsCompass = true

        let (nw, se) = service.region
        let center = CLLocationCoordinate2D(
            latitude: (nw.latitude + se.latitude) / 2,
            longitude: (nw.longitude + se.longitude) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: (nw.latitude - se.latitude) * 1.25,
            longitudeDelta: (se.longitude - nw.longitude) * 1.25
        )
        mapView.setRegion(MKCoordinateRegion(center: center, span: span), animated: false)

        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap(_:)))
        mapView.addGestureRecognizer(tap)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        if let image = overlayImage, !context.coordinator.overlayAdded {
            mapView.addOverlay(BathymetryOverlay(service: service, image: image))
            context.coordinator.overlayAdded = true
        }

        if centerOnUserTrigger != context.coordinator.lastCenterTrigger {
            context.coordinator.lastCenterTrigger = centerOnUserTrigger
            if let userLocation = mapView.userLocation.location {
                mapView.setCenter(userLocation.coordinate, animated: true)
            }
        }

        context.coordinator.syncPin(on: mapView, coordinate: tappedCoordinate)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        private let parent: DepthMapRepresentable
        var overlayAdded = false
        var lastCenterTrigger = 0
        private var pin: MKPointAnnotation?

        init(_ parent: DepthMapRepresentable) {
            self.parent = parent
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let mapView = gesture.view as? MKMapView else { return }
            let coordinate = mapView.convert(gesture.location(in: mapView),
                                             toCoordinateFrom: mapView)
            parent.tappedCoordinate = coordinate
        }

        func syncPin(on mapView: MKMapView, coordinate: CLLocationCoordinate2D?) {
            if let coordinate {
                if let pin {
                    if pin.coordinate.latitude != coordinate.latitude ||
                        pin.coordinate.longitude != coordinate.longitude {
                        pin.coordinate = coordinate
                    }
                } else {
                    let annotation = MKPointAnnotation()
                    annotation.coordinate = coordinate
                    mapView.addAnnotation(annotation)
                    pin = annotation
                }
            } else if let existing = pin {
                mapView.removeAnnotation(existing)
                pin = nil
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if overlay is BathymetryOverlay {
                return BathymetryOverlayRenderer(overlay: overlay)
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}

// MARK: - Depth Map Screen

struct DepthMapView: View {
    let waterLevel: WaterLevel?

    @StateObject private var locationManager = LocationManager()
    @State private var overlayImage: CGImage?
    @State private var tappedCoordinate: CLLocationCoordinate2D?
    @State private var centerOnUserTrigger = 0
    @State private var showingLegend = false

    private let service = BathymetryService.shared

    /// Offset applied to grid depths so they match the current lake level.
    private var levelCorrectionM: Double {
        guard let level = waterLevel, let service else { return 0 }
        let currentNHN = StarnbergerSee.pegelnullpunkt + level.levelCm / 100.0
        return currentNHN - service.metadata.referenceLevelNHN
    }

    var body: some View {
        Group {
            if let service {
                ZStack(alignment: .bottom) {
                    DepthMapRepresentable(
                        service: service,
                        overlayImage: overlayImage,
                        tappedCoordinate: $tappedCoordinate,
                        centerOnUserTrigger: $centerOnUserTrigger
                    )
                    .ignoresSafeArea(edges: .bottom)

                    VStack(alignment: .leading, spacing: 0) {
                        if showingLegend {
                            legend
                                .padding(.bottom, 8)
                        }
                        depthCard(service: service)
                    }
                    .padding()
                }
            } else {
                ContentUnavailableCompat()
            }
        }
        .navigationTitle("Tiefenkarte")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    showingLegend.toggle()
                } label: {
                    Image(systemName: "list.bullet.rectangle")
                }
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    centerOnUserTrigger += 1
                } label: {
                    Image(systemName: "location")
                }
            }
        }
        .onAppear {
            locationManager.requestAuthorization()
            locationManager.start()
            if overlayImage == nil, let service {
                Task.detached(priority: .userInitiated) {
                    let image = service.makeOverlayImage()
                    await MainActor.run {
                        overlayImage = image
                    }
                }
            }
        }
        .onDisappear {
            locationManager.stop()
        }
    }

    // MARK: - Depth Card

    private func depthCard(service: BathymetryService) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            row(
                icon: "location.fill",
                iconColor: .blue,
                title: "Deine Position",
                depth: locationManager.location.flatMap { service.depth(at: $0.coordinate) },
                emptyText: emptyPositionText
            )

            if let tapped = tappedCoordinate {
                Divider()
                HStack(alignment: .top) {
                    row(
                        icon: "mappin",
                        iconColor: .red,
                        title: "Angetippte Position",
                        depth: service.depth(at: tapped),
                        emptyText: "Keine Tiefendaten (Land)"
                    )
                    Spacer()
                    Button {
                        tappedCoordinate = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            HStack {
                Image(systemName: "water.waves")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if waterLevel != nil {
                    Text(String(format: "Inkl. Wasserstand-Korrektur (%+.1f m zum Mittelwasser)", levelCorrectionM))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Aktueller Wasserstand nicht verfuegbar \u{2013} Tiefen beziehen sich auf Mittelwasser")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text("Basis: amtliche Tiefenkarte (Echolot 1980) \u{2013} keine Seekarte, nicht zur Navigation geeignet.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var emptyPositionText: String {
        switch locationManager.authorizationStatus {
        case .denied, .restricted:
            return "Standortzugriff deaktiviert"
        case .notDetermined:
            return "Warte auf Standortfreigabe..."
        default:
            return locationManager.location == nil
                ? "Suche GPS-Signal..."
                : "Nicht auf dem See"
        }
    }

    private func row(icon: String, iconColor: Color, title: String,
                     depth: Double?, emptyText: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(iconColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let depth {
                    let corrected = max(0, depth + levelCorrectionM)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(String(format: "%.1f", corrected))
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                        Text("m")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(emptyText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Legend

    private var legend: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Wassertiefe")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            HStack(spacing: 0) {
                ForEach(Array(BathymetryService.depthBands.enumerated()), id: \.offset) { _, band in
                    Rectangle()
                        .fill(Color(
                            red: Double(band.color.0) / 255,
                            green: Double(band.color.1) / 255,
                            blue: Double(band.color.2) / 255
                        ))
                        .frame(height: 12)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            HStack {
                Text("0 m")
                Spacer()
                Text("20 m")
                Spacer()
                Text("60 m")
                Spacer()
                Text(">100 m")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: 280)
    }
}

/// Fallback if the bundled bathymetry data cannot be loaded.
private struct ContentUnavailableCompat: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "map")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Tiefendaten konnten nicht geladen werden.")
                .foregroundStyle(.secondary)
        }
    }
}
