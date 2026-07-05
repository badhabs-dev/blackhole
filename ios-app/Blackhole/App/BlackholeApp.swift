import SwiftUI

/// Einstiegspunkt der App.
///
/// Blackhole ist ein Werkzeug für DIY-Smarthome und Netzwerk-Debugging im
/// *eigenen* WLAN. Es kombiniert vier Bereiche:
///  - Netzwerk-Scan (welche Geräte hängen im WLAN, mit IP)
///  - Kameras (ONVIF/RTSP entdecken, Bild + Ton ansehen)
///  - Router-Verwaltung (kicken/drosseln – nur über die Router-API)
///  - Fernsteuerung eigener Rechner (über den Blackhole Companion Agent)
@main
struct BlackholeApp: App {
    @StateObject private var session = AppSession()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}

/// Gemeinsamer, app-weiter Zustand. Hält die zentralen Services, damit die
/// einzelnen Feature-Views sich denselben Scanner / Router-Controller teilen.
@MainActor
final class AppSession: ObservableObject {
    let scanner = NetworkScanner()
    let cameraDiscovery = CameraDiscovery()
    let router = RouterController()
    let policies = PolicyStore()
    let companion = CompanionRegistry()

    /// Ergebnis der Local-Network-Berechtigung (iOS fragt einmalig nach).
    @Published var localNetworkAuthorized: Bool = false

    func requestLocalNetworkAccessIfNeeded() async {
        localNetworkAuthorized = await LocalNetworkAuthorization().requestAuthorization()
    }
}
