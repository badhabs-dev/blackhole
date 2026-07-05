import SwiftUI

/// Haupt-Navigation als Tab-Leiste über die vier Bereiche.
struct RootView: View {
    @EnvironmentObject private var session: AppSession

    var body: some View {
        TabView {
            NetworkView()
                .tabItem { Label("Netzwerk", systemImage: "point.3.connected.trianglepath.dotted") }

            CamerasView()
                .tabItem { Label("Kameras", systemImage: "video") }

            RouterView()
                .tabItem { Label("Router", systemImage: "wifi.router") }

            ParentalControlsView()
                .tabItem { Label("Kontrolle", systemImage: "hand.raised") }

            RemoteControlView()
                .tabItem { Label("Fernsteuerung", systemImage: "display") }
        }
        .task {
            // iOS blendet den Local-Network-Dialog erst beim ersten Zugriff ein.
            await session.requestLocalNetworkAccessIfNeeded()
        }
    }
}
