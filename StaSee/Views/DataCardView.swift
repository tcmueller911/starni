import SwiftUI

struct DataCardView: View {
    let title: String
    let icon: String
    let value: String
    let unit: String
    let details: [(label: String, value: String)]
    let timestamp: Date?
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(accentColor)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(accentColor)
                Text(unit)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            if !details.isEmpty {
                Divider()
                ForEach(details, id: \.label) { detail in
                    HStack {
                        Text(detail.label)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(detail.value)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                }
            }

            if let timestamp {
                Text(timestamp, format: .dateTime.hour().minute())
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            // Mini sparkline hint bar
            MiniSparkline(color: accentColor)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

/// A decorative mini sparkline that hints at available historical data.
struct MiniSparkline: View {
    let color: Color

    // Deterministic wave shape
    private let points: [CGFloat] = [
        0.4, 0.45, 0.5, 0.6, 0.55, 0.48, 0.52, 0.65, 0.7, 0.62,
        0.55, 0.5, 0.45, 0.42, 0.48, 0.55, 0.6, 0.58, 0.52, 0.5,
        0.55, 0.62, 0.68, 0.72, 0.65, 0.58, 0.5, 0.48, 0.52, 0.58
    ]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack(alignment: .bottom) {
                // Filled area
                Path { path in
                    path.move(to: CGPoint(x: 0, y: h))
                    for (i, pt) in points.enumerated() {
                        let x = w * CGFloat(i) / CGFloat(points.count - 1)
                        let y = h * (1.0 - pt)
                        if i == 0 {
                            path.addLine(to: CGPoint(x: x, y: y))
                        } else {
                            let prevX = w * CGFloat(i - 1) / CGFloat(points.count - 1)
                            let prevY = h * (1.0 - points[i - 1])
                            let cx = (prevX + x) / 2
                            path.addCurve(
                                to: CGPoint(x: x, y: y),
                                control1: CGPoint(x: cx, y: prevY),
                                control2: CGPoint(x: cx, y: y)
                            )
                        }
                    }
                    path.addLine(to: CGPoint(x: w, y: h))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0.25), color.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                // Line on top
                Path { path in
                    for (i, pt) in points.enumerated() {
                        let x = w * CGFloat(i) / CGFloat(points.count - 1)
                        let y = h * (1.0 - pt)
                        if i == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            let prevX = w * CGFloat(i - 1) / CGFloat(points.count - 1)
                            let prevY = h * (1.0 - points[i - 1])
                            let cx = (prevX + x) / 2
                            path.addCurve(
                                to: CGPoint(x: x, y: y),
                                control1: CGPoint(x: cx, y: prevY),
                                control2: CGPoint(x: cx, y: y)
                            )
                        }
                    }
                }
                .stroke(color.opacity(0.6), lineWidth: 1.5)
            }
        }
        .frame(height: 28)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
