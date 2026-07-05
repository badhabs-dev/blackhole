import Foundation

/// Ein im lokalen Netz gefundenes Gerät.
struct NetworkDevice: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var ipAddress: String?
    var hostname: String?
    var macAddress: String?          // Auf iOS aus einer App meist NICHT auslesbar (Sandbox).
    var vendor: String?              // Aus MAC-OUI abgeleitet, falls MAC vom Router kommt.
    var services: [DiscoveredService]
    var kind: Kind
    var isOnline: Bool = true
    var lastSeen: Date = .init()

    enum Kind: String, CaseIterable {
        case camera = "Kamera"
        case computer = "Computer"
        case phone = "Smartphone"
        case tv = "TV / Media"
        case router = "Router"
        case iot = "Smart-Home"
        case printer = "Drucker"
        case unknown = "Unbekannt"

        var symbol: String {
            switch self {
            case .camera: return "video.fill"
            case .computer: return "desktopcomputer"
            case .phone: return "iphone"
            case .tv: return "tv"
            case .router: return "wifi.router.fill"
            case .iot: return "sensor.fill"
            case .printer: return "printer.fill"
            case .unknown: return "questionmark.circle"
            }
        }
    }
}

/// Ein per Bonjour/mDNS entdeckter Dienst auf einem Gerät.
struct DiscoveredService: Hashable {
    var type: String        // z.B. "_rtsp._tcp", "_http._tcp", "_airplay._tcp"
    var port: Int?
    var txtRecords: [String: String] = [:]

    /// Heuristik: verrät der Diensttyp die Geräteart?
    var impliedKind: NetworkDevice.Kind? {
        switch type {
        case let t where t.contains("rtsp") || t.contains("onvif") || t.contains("rtp"):
            return .camera
        case let t where t.contains("airplay") || t.contains("googlecast") || t.contains("raop"):
            return .tv
        case let t where t.contains("ipp") || t.contains("printer") || t.contains("pdl"):
            return .printer
        case let t where t.contains("smb") || t.contains("afpovertcp") || t.contains("ssh") || t.contains("rfb"):
            return .computer
        case let t where t.contains("hap") || t.contains("matter") || t.contains("homekit"):
            return .iot
        default:
            return nil
        }
    }
}
