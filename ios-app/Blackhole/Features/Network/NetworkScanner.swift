import Foundation
import Network
import Combine

/// Durchsucht das lokale WLAN nach Geräten.
///
/// Auf iOS gibt es keinen App-Zugriff auf die ARP-Tabelle und kein rohes
/// ICMP-Broadcast-Ping. Wir kombinieren daher zwei erlaubte Techniken:
///
///  1. **Bonjour/mDNS** (`NWBrowser`): findet zuverlässig alle Geräte, die
///     einen Dienst ankündigen (Apple-Geräte, Kameras, Drucker, Chromecasts,
///     Smart-Home). Liefert Name, Diensttyp und – nach Auflösung – IP + Port.
///
///  2. **Gezielter TCP-Probe** über den eigenen Subnetz-Bereich: Wir leiten aus
///     der eigenen IP das /24-Netz ab und versuchen kurze TCP-Verbindungen auf
///     typische Ports (80, 443, 554, 22, 8080, 9000). Antwortet ein Host, ist
///     er online – so tauchen auch Geräte ohne Bonjour auf.
///
/// Für eine *vollständige* Geräteliste inkl. MAC-Adressen braucht man die
/// Router-API (siehe `RouterController`), weil nur der Router die ARP-/DHCP-
/// Tabelle kennt.
@MainActor
final class NetworkScanner: ObservableObject {
    @Published private(set) var devices: [NetworkDevice] = []
    @Published private(set) var isScanning = false
    @Published private(set) var progress: Double = 0

    private var browsers: [NWBrowser] = []
    private var probeTask: Task<Void, Never>?

    /// Bonjour-Diensttypen, nach denen gesucht wird.
    private let serviceTypes = [
        "_http._tcp", "_https._tcp", "_rtsp._tcp", "_onvif._tcp",
        "_airplay._tcp", "_raop._tcp", "_googlecast._tcp",
        "_ipp._tcp", "_ipps._tcp", "_pdl-datastream._tcp",
        "_ssh._tcp", "_smb._tcp", "_afpovertcp._tcp", "_rfb._tcp",
        "_hap._tcp", "_matter._tcp", "_homekit._tcp",
        "_workstation._tcp", "_device-info._tcp"
    ]

    func startScan() {
        guard !isScanning else { return }
        isScanning = true
        progress = 0
        devices.removeAll()
        startBonjour()
        probeTask = Task { await sweepSubnet() }
    }

    func stopScan() {
        isScanning = false
        browsers.forEach { $0.cancel() }
        browsers.removeAll()
        probeTask?.cancel()
        probeTask = nil
    }

    // MARK: - Bonjour

    private func startBonjour() {
        for type in serviceTypes {
            let params = NWParameters()
            params.includePeerToPeer = true
            let browser = NWBrowser(for: .bonjour(type: type, domain: "local."), using: params)
            browser.browseResultsChangedHandler = { [weak self] results, _ in
                Task { @MainActor in self?.handleBonjour(results: results, type: type) }
            }
            browser.start(queue: .global(qos: .utility))
            browsers.append(browser)
        }
    }

    private func handleBonjour(results: Set<NWBrowser.Result>, type: String) {
        for result in results {
            guard case let .service(name, _, _, _) = result.endpoint else { continue }
            let service = DiscoveredService(type: type, port: nil)
            upsert(name: name, service: service, ip: nil)
            resolve(endpoint: result.endpoint, serviceType: type, displayName: name)
        }
    }

    /// Löst einen Bonjour-Endpunkt zu IP:Port auf.
    private func resolve(endpoint: NWEndpoint, serviceType: String, displayName: String) {
        let conn = NWConnection(to: endpoint, using: .tcp)
        conn.stateUpdateHandler = { [weak self] state in
            guard case .ready = state else {
                if case .failed = state { conn.cancel() }
                return
            }
            if let path = conn.currentPath, let remote = path.remoteEndpoint,
               case let .hostPort(host, port) = remote {
                let ip = Self.hostString(host)
                Task { @MainActor in
                    let service = DiscoveredService(type: serviceType, port: Int(port.rawValue))
                    self?.upsert(name: displayName, service: service, ip: ip)
                }
            }
            conn.cancel()
        }
        conn.start(queue: .global(qos: .utility))
    }

    nonisolated static func hostString(_ host: NWEndpoint.Host) -> String {
        switch host {
        case .ipv4(let a): return "\(a)".components(separatedBy: "%").first ?? "\(a)"
        case .ipv6(let a): return "\(a)".components(separatedBy: "%").first ?? "\(a)"
        case .name(let n, _): return n
        @unknown default: return "\(host)"
        }
    }

    // MARK: - Subnetz-Sweep

    private func sweepSubnet() async {
        guard let base = LocalAddress.ipv4SubnetPrefix() else {
            isScanning = false
            return
        }
        let ports: [UInt16] = [80, 443, 554, 8080, 22, 9000]
        let total = 254
        var done = 0

        await withTaskGroup(of: Void.self) { group in
            for host in 1...254 {
                let ip = "\(base).\(host)"
                group.addTask { await self.probe(ip: ip, ports: ports) }
                // Begrenze Parallelität grob, damit iOS nicht drosselt.
                if host % 24 == 0 { await group.next() }
            }
            for await _ in group {
                done += 1
                await MainActor.run { self.progress = Double(done) / Double(total) }
            }
        }
        await MainActor.run {
            self.progress = 1
            self.isScanning = false
        }
    }

    private func probe(ip: String, ports: [UInt16]) async {
        for port in ports {
            if await tcpReachable(ip: ip, port: port) {
                await MainActor.run {
                    let svc = DiscoveredService(type: "_probe._tcp", port: Int(port))
                    self.upsert(name: ip, service: svc, ip: ip)
                }
                return
            }
        }
    }

    private func tcpReachable(ip: String, port: UInt16, timeout: TimeInterval = 0.6) async -> Bool {
        await withCheckedContinuation { continuation in
            let conn = NWConnection(
                host: .init(ip),
                port: .init(rawValue: port)!,
                using: .tcp
            )
            var resumed = false
            let done: (Bool) -> Void = { ok in
                if !resumed { resumed = true; conn.cancel(); continuation.resume(returning: ok) }
            }
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready: done(true)
                case .failed, .cancelled: done(false)
                default: break
                }
            }
            conn.start(queue: .global(qos: .utility))
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { done(false) }
        }
    }

    // MARK: - Zusammenführen

    /// Fügt einen Fund hinzu oder aktualisiert ein bestehendes Gerät (per IP oder Name).
    private func upsert(name: String, service: DiscoveredService, ip: String?) {
        let index = devices.firstIndex { dev in
            (ip != nil && dev.ipAddress == ip) || dev.name == name
        }

        if let index {
            var dev = devices[index]
            if dev.ipAddress == nil, let ip { dev.ipAddress = ip }
            if !dev.services.contains(service) { dev.services.append(service) }
            dev.kind = Self.inferKind(from: dev.services, fallback: dev.kind)
            dev.lastSeen = .init()
            devices[index] = dev
        } else {
            var dev = NetworkDevice(
                name: name,
                ipAddress: ip,
                hostname: name.contains(".") ? name : nil,
                services: [service],
                kind: .unknown
            )
            dev.kind = Self.inferKind(from: dev.services, fallback: .unknown)
            devices.append(dev)
        }
        devices.sort { ($0.ipAddress ?? "z") < ($1.ipAddress ?? "z") }
    }

    static func inferKind(from services: [DiscoveredService], fallback: NetworkDevice.Kind) -> NetworkDevice.Kind {
        for s in services { if let k = s.impliedKind { return k } }
        return fallback
    }

    var cameras: [NetworkDevice] { devices.filter { $0.kind == .camera } }
}
