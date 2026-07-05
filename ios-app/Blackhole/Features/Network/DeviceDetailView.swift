import SwiftUI

/// Detailansicht eines Geräts inkl. Diensten und Schnellaktionen.
struct DeviceDetailView: View {
    let device: NetworkDevice
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        header
                        infoCard
                        servicesCard
                        actionsCard
                    }
                    .padding()
                }
            }
            .navigationTitle(device.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: device.kind.symbol)
                .font(.system(size: 44))
                .foregroundStyle(Theme.accent)
            Text(device.kind.rawValue).foregroundStyle(Theme.textSecondary)
        }
        .padding(.top)
    }

    private var infoCard: some View {
        GlowCard {
            VStack(alignment: .leading, spacing: 10) {
                infoRow("IP-Adresse", device.ipAddress ?? "—")
                infoRow("Hostname", device.hostname ?? "—")
                infoRow("MAC", device.macAddress ?? "nur über Router-API")
                infoRow("Hersteller", device.vendor ?? "—")
                infoRow("Zuletzt gesehen", device.lastSeen.formatted(date: .omitted, time: .standard))
            }
        }
    }

    private var servicesCard: some View {
        GlowCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Offene Dienste").font(.headline).foregroundStyle(Theme.textPrimary)
                if device.services.isEmpty {
                    Text("keine").foregroundStyle(Theme.textFaint)
                }
                ForEach(device.services, id: \.self) { s in
                    HStack {
                        Text(s.type).font(.system(.caption, design: .monospaced))
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                        if let p = s.port { Text("Port \(p)").font(.caption).foregroundStyle(Theme.textFaint) }
                    }
                }
            }
        }
    }

    @ViewBuilder private var actionsCard: some View {
        GlowCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Aktionen").font(.headline).foregroundStyle(Theme.textPrimary)

                if device.kind == .camera {
                    NavigationLink {
                        CameraLoginView(host: device.ipAddress ?? device.name)
                    } label: {
                        actionLabel("Kamera öffnen", "video.fill")
                    }
                }
                if let ip = device.ipAddress {
                    Link(destination: URL(string: "http://\(ip)")!) {
                        actionLabel("Web-Oberfläche öffnen", "safari.fill")
                    }
                }
                Button {
                    session.router.requestKick(ip: device.ipAddress)
                } label: {
                    actionLabel("Im Router sperren/kicken", "hand.raised.fill")
                }
                .tint(Theme.danger)
                Text("Sperren/Drosseln funktioniert nur, wenn im Router-Tab eine kompatible Router-Verbindung eingerichtet ist.")
                    .font(.caption2).foregroundStyle(Theme.textFaint)
            }
        }
    }

    private func infoRow(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value).foregroundStyle(Theme.textPrimary)
                .font(.system(.body, design: .monospaced)).lineLimit(1)
        }
    }

    private func actionLabel(_ title: String, _ symbol: String) -> some View {
        HStack {
            Image(systemName: symbol)
            Text(title)
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.textFaint)
        }
        .foregroundStyle(Theme.textPrimary)
    }
}
