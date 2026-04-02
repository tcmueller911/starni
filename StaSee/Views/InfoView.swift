import SwiftUI

struct InfoView: View {
    @Environment(\.dismiss) private var dismiss

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    appHeader
                    dataSourcesCard
                    developerCard
                    Spacer(minLength: 40)
                }
                .padding()
            }
            .navigationTitle("Info")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }

    // MARK: - App Header

    private var appHeader: some View {
        VStack(spacing: 12) {
            // App Icon representation
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        LinearGradient(
                            colors: [.blue, .cyan, .teal],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)

                Image(systemName: "water.waves")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(.white)
            }

            Text("Starni")
                .font(.title.bold())

            Text("Version \(appVersion) (\(buildNumber))")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("Starnberger See \u{2013} Live-Daten")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Data Sources

    private var dataSourcesCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Datenquellen", systemImage: "server.rack")
                .font(.headline)
                .foregroundStyle(.secondary)

            sourceRow(
                icon: "thermometer.medium",
                color: .blue,
                title: "Wassertemperatur",
                source: "GKD Bayern",
                detail: "Gewaesserkundlicher Dienst Bayern\nBayerisches Landesamt fuer Umwelt",
                url: "https://www.gkd.bayern.de"
            )

            Divider()

            sourceRow(
                icon: "water.waves",
                color: .cyan,
                title: "Wasserstand",
                source: "GKD Bayern",
                detail: "Gewaesserkundlicher Dienst Bayern\nPegelnullpunktsh\u{00F6}he: 583,43 m NHN",
                url: "https://www.gkd.bayern.de"
            )

            Divider()

            sourceRow(
                icon: "wind",
                color: .teal,
                title: "Winddaten",
                source: "Open-Meteo",
                detail: "Freie Wetter-API\nKeine Registrierung erforderlich",
                url: "https://open-meteo.com"
            )

            Divider()

            Text("Alle Daten werden direkt von den offiziellen Quellen abgerufen. Die Aktualisierung erfolgt automatisch alle 15 Minuten.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func sourceRow(icon: String, color: Color, title: String, source: String, detail: String, url: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .frame(width: 24)
                Text(title)
                    .font(.subheadline.bold())
                Spacer()
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(source)
                    .font(.subheadline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 32)

            if let link = URL(string: url) {
                Link(destination: link) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption)
                        Text(url.replacingOccurrences(of: "https://", with: ""))
                            .font(.caption)
                    }
                    .foregroundStyle(.blue)
                }
                .padding(.leading, 32)
            }
        }
    }

    // MARK: - Developer

    private var developerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Entwicklung", systemImage: "hammer.fill")
                .font(.headline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Image(systemName: "person.circle.fill")
                    .font(.title)
                    .foregroundStyle(.blue.gradient)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tom M\u{00FC}ller")
                        .font(.subheadline.bold())
                    Text("Entwickler")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
