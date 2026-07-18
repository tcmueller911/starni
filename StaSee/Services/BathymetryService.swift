import Foundation
import CoreLocation
import CoreGraphics

/// Loads the embedded bathymetry grid of the Starnberger See and answers
/// depth queries for coordinates on the lake.
///
/// Grid: UInt16 row-major (north to south), depth in decimeters relative to
/// mean water level (~584,2 m NHN), 65535 = no data (land).
/// Digitized from the official Tiefenkarte Starnberger See
/// (WWA Weilheim, echo-sounding survey 09/1980, 1:25.000).
final class BathymetryService {
    struct Metadata: Decodable {
        let width: Int
        let height: Int
        let originLon: Double
        let originLat: Double
        let pixelDeg: Double
        let referenceLevelNHN: Double
        let noData: UInt16
        let maxDepthM: Double
    }

    static let shared = BathymetryService()

    let metadata: Metadata
    private let grid: [UInt16]

    private init?(bundle: Bundle = .main) {
        guard let metaURL = bundle.url(forResource: "StarnbergBathymetry", withExtension: "json"),
              let binURL = bundle.url(forResource: "StarnbergBathymetry", withExtension: "bin"),
              let metaData = try? Data(contentsOf: metaURL),
              let meta = try? JSONDecoder().decode(Metadata.self, from: metaData),
              let binData = try? Data(contentsOf: binURL),
              binData.count == meta.width * meta.height * 2 else {
            return nil
        }

        metadata = meta
        grid = binData.withUnsafeBytes { Array($0.bindMemory(to: UInt16.self)) }
    }

    // MARK: - Depth Lookup

    /// Depth in meters below mean water level (MW 584,21 m NHN) at the given
    /// coordinate, bilinearly interpolated. Returns nil outside the lake.
    func depth(at coordinate: CLLocationCoordinate2D) -> Double? {
        let fx = (coordinate.longitude - metadata.originLon) / metadata.pixelDeg - 0.5
        let fy = (metadata.originLat - coordinate.latitude) / metadata.pixelDeg - 0.5

        let x0 = Int(fx.rounded(.down)), y0 = Int(fy.rounded(.down))
        let tx = fx - Double(x0), ty = fy - Double(y0)

        var weightedSum = 0.0
        var weightTotal = 0.0
        for (dx, dy, w) in [(0, 0, (1 - tx) * (1 - ty)), (1, 0, tx * (1 - ty)),
                            (0, 1, (1 - tx) * ty), (1, 1, tx * ty)] {
            if let v = value(x: x0 + dx, y: y0 + dy), w > 0 {
                weightedSum += Double(v) * w
                weightTotal += w
            }
        }

        // Require that at least half of the interpolation weight lies on water,
        // so positions clearly on land return nil.
        guard weightTotal > 0.5 else { return nil }
        return weightedSum / weightTotal / 10.0
    }

    private func value(x: Int, y: Int) -> UInt16? {
        guard x >= 0, x < metadata.width, y >= 0, y < metadata.height else { return nil }
        let v = grid[y * metadata.width + x]
        return v == metadata.noData ? nil : v
    }

    // MARK: - Geographic Extent

    var region: (northWest: CLLocationCoordinate2D, southEast: CLLocationCoordinate2D) {
        let nw = CLLocationCoordinate2D(latitude: metadata.originLat, longitude: metadata.originLon)
        let se = CLLocationCoordinate2D(
            latitude: metadata.originLat - Double(metadata.height) * metadata.pixelDeg,
            longitude: metadata.originLon + Double(metadata.width) * metadata.pixelDeg
        )
        return (nw, se)
    }

    // MARK: - Overlay Image

    /// Renders the grid as a color-banded RGBA image for the map overlay.
    /// Depths are bilinearly upsampled so band edges follow smooth curves.
    func makeOverlayImage(upsample: Int = 4) -> CGImage? {
        let w = metadata.width * upsample
        let h = metadata.height * upsample
        var pixels = [UInt8](repeating: 0, count: w * h * 4)

        for py in 0..<h {
            let lat = metadata.originLat - (Double(py) + 0.5) / Double(upsample) * metadata.pixelDeg
            for px in 0..<w {
                let lon = metadata.originLon + (Double(px) + 0.5) / Double(upsample) * metadata.pixelDeg
                guard let d = depth(at: CLLocationCoordinate2D(latitude: lat, longitude: lon)) else { continue }
                let (r, g, b) = Self.bandColor(forDepth: d)
                let i = (py * w + px) * 4
                let alpha = 217 // ~0.85, premultiplied below
                pixels[i] = UInt8(Int(r) * alpha / 255)
                pixels[i + 1] = UInt8(Int(g) * alpha / 255)
                pixels[i + 2] = UInt8(Int(b) * alpha / 255)
                pixels[i + 3] = UInt8(alpha)
            }
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixels, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        return context.makeImage()
    }

    /// Depth bands and their colors, shared by overlay and legend.
    static let depthBands: [(upTo: Double, color: (UInt8, UInt8, UInt8))] = [
        (2,   (178, 226, 240)),
        (5,   (140, 205, 230)),
        (10,  (105, 180, 220)),
        (20,  (72, 152, 205)),
        (40,  (48, 122, 185)),
        (60,  (33, 96, 162)),
        (80,  (24, 74, 138)),
        (100, (17, 55, 112)),
        (.infinity, (11, 38, 85)),
    ]

    static func bandColor(forDepth d: Double) -> (UInt8, UInt8, UInt8) {
        for band in depthBands where d < band.upTo {
            return band.color
        }
        return depthBands.last!.color
    }
}
