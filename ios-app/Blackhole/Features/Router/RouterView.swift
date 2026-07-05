import SwiftUI

/// WLAN-Verwaltung: Router verbinden, Clients kicken/bannen/priorisieren.
struct RouterView: View {
    @EnvironmentObject private var session: AppSession
    @State private var showSetup = false

    private var router: RouterController { session.router }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()
                if router.isConfigured {
                    clientList
                } else {
                    notConnected
                }
            }
            .navigationTitle("Router")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSetup = true } label: { Image(systemName: "gearshape") }
                }
                if router.isConfigured {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { Task { await router.refreshClients() } } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
            .sheet(isPresented: $showSetup) { RouterSetupView() }
            .task { if router.isConfigured { await router.refreshClients() } }
        }
    }

    private var clientList: some View {
        List {
            if let err = router.lastError {
                Text(err).font(.caption).foregroundStyle(Theme.danger)
                    .listRowBackground(Color.clear)
            }
            ForEach(router.clients) { client in
                RouterClientRow(client: client)
                    .listRowBackground(Theme.eventHorizon)
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var notConnected: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.router").font(.system(size: 48)).foregroundStyle(Theme.accent)
            Text("Kein Router verbunden").font(.headline).foregroundStyle(Theme.textPrimary)
            Text("Kicken, Bannen und Drosseln funktionieren nur über die API deines Routers. Verbinde deine FRITZ!Box oder deinen OpenWrt-Router mit dem WLAN-/Admin-Passwort.")
                .font(.callout).multilineTextAlignment(.center)
                .foregroundStyle(Theme.textSecondary).padding(.horizontal, 32)
            Button("Router einrichten") { showSetup = true }
                .buttonStyle(.borderedProminent).tint(Theme.accent)
        }
    }
}

private struct RouterClientRow: View {
    let client: RouterClient
    @EnvironmentObject private var session: AppSession

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: client.isWireless ? "wifi" : "cable.connector")
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(client.name).foregroundStyle(Theme.textPrimary)
                    Text("\(client.ip)  ·  \(client.mac)")
                        .font(.caption2).foregroundStyle(Theme.textFaint)
                }
                Spacer()
                if client.isBlocked {
                    Text("gesperrt").font(.caption2).foregroundStyle(Theme.danger)
                }
            }
            HStack(spacing: 10) {
                Button(client.isBlocked ? "Freigeben" : "Kicken/Bannen") {
                    Task {
                        client.isBlocked ? await session.router.unblock(client)
                                         : await session.router.kick(client)
                    }
                }
                .buttonStyle(.bordered).tint(client.isBlocked ? Theme.success : Theme.danger)

                Menu("Bandbreite") {
                    Button("Boost (hoch)") { setQoS(.high) }
                    Button("Normal") { setQoS(.normal) }
                    Button("Drosseln (2 Mbit)") { setQoS(.low) }
                }
                .buttonStyle(.bordered).tint(Theme.accent)
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
    }

    private func setQoS(_ p: QoSPriority) {
        Task {
            await session.router.setBandwidth(client, priority: p,
                                              limitMbps: p == .low ? 2 : nil)
        }
    }
}
