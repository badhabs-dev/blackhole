import Foundation
import Combine

/// Regeln für Elternkontrolle / Automatisierung, gebunden an ein Gerät.
///
/// Durchsetzung (zwei Wege, je nach Ziel):
///  - **Fremde Geräte im WLAN** (Konsole des Kindes, Tablet, …): über den Router.
///    Zeitfenster → `setInternetSchedule`; blockierte Domains → DNS-Filter des
///    Routers (z.B. FRITZ!Box-Zugangsprofil, OpenWrt `dnsmasq`-Blocklist,
///    AdGuard Home / Pi-hole per API).
///  - **Eigene Apple-Familiengeräte**: über Apples `FamilyControls`/`ManagedSettings`
///    (Screen-Time-API) – blockiert Apps & Web systemseitig auf dem Kind-iPhone.
///
/// Diese Klasse hält die Regeln und bildet sie auf Router-Aktionen ab.
@MainActor
final class PolicyStore: ObservableObject {
    @Published var policies: [DevicePolicy] = []

    func policy(forDeviceID id: String) -> DevicePolicy {
        policies.first { $0.deviceID == id } ?? DevicePolicy(deviceID: id, deviceName: id)
    }

    func upsert(_ policy: DevicePolicy) {
        if let idx = policies.firstIndex(where: { $0.deviceID == policy.deviceID }) {
            policies[idx] = policy
        } else {
            policies.append(policy)
        }
    }

    /// Wendet alle Regeln über den Router an (Zeitfenster + Blocklisten).
    func apply(using router: RouterController) async {
        for policy in policies {
            guard let client = router.clients.first(where: { $0.id == policy.deviceID }) else { continue }
            let allowedNow = policy.isInternetAllowed(at: Date())
            try? await router.backend?.setInternetSchedule(client, allowed: allowedNow)
            // Domain-/App-Blocklisten würden hier an den DNS-Filter des Routers
            // (dnsmasq/AdGuard/Pi-hole) übergeben.
        }
    }
}

/// Regelwerk für ein einzelnes Gerät.
struct DevicePolicy: Identifiable, Hashable {
    var id: String { deviceID }
    var deviceID: String
    var deviceName: String

    /// Erlaubte Nutzungsfenster pro Wochentag.
    var schedule: [AllowedWindow] = []
    /// Tägliches Bildschirmzeit-Limit in Minuten (0 = kein Limit).
    var dailyLimitMinutes: Int = 0
    /// Blockierte Domains/Webseiten (DNS-Filter).
    var blockedDomains: [String] = []
    /// Blockierte App-Kategorien (nur eigene Apple-Geräte via Screen Time).
    var blockedAppCategories: [String] = []
    var enabled: Bool = true

    func isInternetAllowed(at date: Date) -> Bool {
        guard enabled else { return true }
        if schedule.isEmpty { return true }
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: date)  // 1 = So
        let minutes = cal.component(.hour, from: date) * 60 + cal.component(.minute, from: date)
        return schedule.contains { $0.weekday == weekday && minutes >= $0.startMinute && minutes < $0.endMinute }
    }
}

struct AllowedWindow: Hashable, Identifiable {
    var id = UUID()
    var weekday: Int      // 1 = Sonntag … 7 = Samstag
    var startMinute: Int  // ab Mitternacht
    var endMinute: Int
}
