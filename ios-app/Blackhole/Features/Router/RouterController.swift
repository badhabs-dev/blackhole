import Foundation
import Combine

/// Verwaltet die Verbindung zum WLAN-Router und die dortigen Aktionen.
///
/// **Warum ein Router nötig ist:** Eine iOS-App kann fremde Geräte nicht auf
/// Netzwerkebene „kicken" oder deren Bandbreite drosseln – dafür fehlen der
/// Sandbox jegliche Rechte. Solche Eingriffe macht immer der Router. Diese App
/// spricht daher mit der **API des Routers** (mit dem WLAN-/Admin-Passwort, das
/// der Nutzer besitzt).
///
/// Unterstützt werden über austauschbare `RouterBackend`-Adapter u.a.:
///  - **FRITZ!Box** via TR-064 (SOAP) – Geräteliste, WLAN-Sperre, Zeitprofile.
///  - **OpenWrt** via ubus/LuCI-RPC oder SSH (`iptables`, `tc`, `wifi`).
///  - Generisch: alles mit dokumentierter HTTP-API.
///
/// Ohne konfiguriertes Backend sind diese Aktionen absichtlich deaktiviert.
@MainActor
final class RouterController: ObservableObject {
    @Published var backend: RouterBackend?
    @Published private(set) var clients: [RouterClient] = []
    @Published var lastError: String?
    @Published var pendingKickIP: String?

    var isConfigured: Bool { backend != nil }

    func configure(_ backend: RouterBackend) {
        self.backend = backend
    }

    func refreshClients() async {
        guard let backend else { return }
        do { clients = try await backend.listClients() }
        catch { lastError = error.localizedDescription }
    }

    func kick(_ client: RouterClient) async {
        await run { try await $0.setBlocked(client, blocked: true) }
    }

    func unblock(_ client: RouterClient) async {
        await run { try await $0.setBlocked(client, blocked: false) }
    }

    /// „Boosten / weniger geben": QoS-Priorität bzw. Bandbreitenlimit.
    func setBandwidth(_ client: RouterClient, priority: QoSPriority, limitMbps: Int?) async {
        await run { try await $0.setQoS(client, priority: priority, limitMbps: limitMbps) }
    }

    /// Wird aus der Geräte-Detailansicht angestoßen.
    func requestKick(ip: String?) {
        pendingKickIP = ip
    }

    private func run(_ op: (RouterBackend) async throws -> Void) async {
        guard let backend else { lastError = "Kein Router verbunden."; return }
        do { try await op(backend); await refreshClients() }
        catch { lastError = error.localizedDescription }
    }
}

/// Ein am Router bekannter Client (aus DHCP-/WLAN-Tabelle).
struct RouterClient: Identifiable, Hashable {
    let id: String              // meist MAC
    var name: String
    var ip: String
    var mac: String
    var isBlocked: Bool
    var isWireless: Bool
    var priority: QoSPriority = .normal
}

enum QoSPriority: String, CaseIterable, Hashable {
    case high = "Boost"
    case normal = "Normal"
    case low = "Gedrosselt"
}

/// Adapter-Protokoll für konkrete Router. Neue Router = neue Implementierung.
protocol RouterBackend: Sendable {
    var displayName: String { get }
    func listClients() async throws -> [RouterClient]
    func setBlocked(_ client: RouterClient, blocked: Bool) async throws
    func setQoS(_ client: RouterClient, priority: QoSPriority, limitMbps: Int?) async throws
    /// Für Elternkontrolle: Zeitprofil / Internet-Pause setzen.
    func setInternetSchedule(_ client: RouterClient, allowed: Bool) async throws
}
