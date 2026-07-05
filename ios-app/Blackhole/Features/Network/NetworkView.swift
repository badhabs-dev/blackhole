import SwiftUI

/// Zeigt alle im WLAN gefundenen Geräte mit IP-Adresse und Diensten.
struct NetworkView: View {
    @EnvironmentObject private var session: AppSession
    @State private var selected: NetworkDevice?

    private var scanner: NetworkScanner { session.scanner }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()

                List {
                    if scanner.isScanning {
                        Section {
                            ProgressView(value: scanner.progress) {
                                Text("Scanne Subnetz … \(Int(scanner.progress * 100)) %")
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            .tint(Theme.accent)
                        }
                        .listRowBackground(Color.clear)
                    }

                    ForEach(scanner.devices) { device in
                        Button { selected = device } label: {
                            DeviceRow(device: device)
                        }
                        .listRowBackground(Theme.eventHorizon)
                    }

                    if scanner.devices.isEmpty && !scanner.isScanning {
                        emptyState
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Netzwerk")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        scanner.isScanning ? scanner.stopScan() : scanner.startScan()
                    } label: {
                        Image(systemName: scanner.isScanning ? "stop.circle" : "arrow.clockwise")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    if let ip = LocalAddress.ipv4() {
                        Text("Ich: \(ip)").font(.caption2).foregroundStyle(Theme.textFaint)
                    }
                }
            }
            .sheet(item: $selected) { DeviceDetailView(device: $0) }
            .task { if scanner.devices.isEmpty { scanner.startScan() } }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "wifi.slash").font(.largeTitle).foregroundStyle(Theme.textFaint)
            Text("Keine Geräte gefunden.").foregroundStyle(Theme.textSecondary)
            Text("Stelle sicher, dass du im WLAN bist und die Local-Network-Berechtigung erteilt hast.")
                .font(.caption).multilineTextAlignment(.center).foregroundStyle(Theme.textFaint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .listRowBackground(Color.clear)
    }
}

private struct DeviceRow: View {
    let device: NetworkDevice

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: device.kind.symbol)
                .font(.title3)
                .foregroundStyle(Theme.accent)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(device.name).foregroundStyle(Theme.textPrimary).lineLimit(1)
                HStack(spacing: 6) {
                    Text(device.ipAddress ?? "IP unbekannt")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                    Text("· \(device.kind.rawValue)")
                        .font(.caption).foregroundStyle(Theme.textFaint)
                }
            }
            Spacer()
            Circle()
                .fill(device.isOnline ? Theme.success : Theme.textFaint)
                .frame(width: 8, height: 8)
        }
        .padding(.vertical, 4)
    }
}
