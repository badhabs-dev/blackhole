import Foundation
import Combine

/// Steuert eigene Rechner (PC/Mac/Linux) über den **Blackhole Companion Agent**.
///
/// iOS darf nicht einfach auf die Webcam, den Bildschirm oder die Dateien eines
/// anderen Rechners zugreifen – das muss der Rechner selbst erlauben. Dafür läuft
/// dort ein kleines Agent-Programm (siehe `companion-agent/`), das eine lokale,
/// gekoppelte (paired) API im WLAN anbietet:
///
///   GET  /info                → Name, OS, Fähigkeiten
///   GET  /screen              → MJPEG-Stream des Bildschirms
///   GET  /webcam              → MJPEG-Stream der Webcam
///   GET  /files?path=…        → Verzeichnis auflisten
///   GET  /download?path=…     → Datei herunterladen
///   POST /upload?path=…       → Datei hochladen
///   POST /input               → (optional) Maus/Tastatur
///
/// Kopplung: Beim ersten Verbinden zeigt der Agent einen PIN; die App schickt
/// ihn an `POST /pair` und erhält ein Token (danach Authorization-Header).
@MainActor
final class CompanionRegistry: ObservableObject {
    @Published var agents: [CompanionAgent] = []
    @Published var lastError: String?

    /// Findet Agents per Bonjour `_blackhole-agent._tcp` (der Agent kündigt sich an).
    func discover(from devices: [NetworkDevice]) {
        for dev in devices where dev.services.contains(where: { $0.type.contains("blackhole-agent") }) {
            guard let host = dev.ipAddress else { continue }
            if agents.contains(where: { $0.host == host }) { continue }
            agents.append(CompanionAgent(name: dev.name, host: host, port: 8765))
        }
    }

    func addManual(host: String, port: Int) {
        guard !agents.contains(where: { $0.host == host }) else { return }
        agents.append(CompanionAgent(name: host, host: host, port: port))
    }

    func pair(_ agent: CompanionAgent, pin: String) async -> Bool {
        do {
            let client = CompanionClient(agent: agent)
            let token = try await client.pair(pin: pin)
            if let idx = agents.firstIndex(where: { $0.id == agent.id }) {
                agents[idx].token = token
                agents[idx].info = try? await CompanionClient(agent: agents[idx]).info()
            }
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }
}

struct CompanionAgent: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var host: String
    var port: Int
    var token: String?
    var info: AgentInfo?

    var baseURL: URL { URL(string: "http://\(host):\(port)")! }
    var isPaired: Bool { token != nil }
}

struct AgentInfo: Hashable, Codable {
    var name: String
    var os: String
    var hasWebcam: Bool
    var hasScreen: Bool
    var hasFiles: Bool
}

/// Dünner HTTP-Client gegen einen Companion Agent.
struct CompanionClient {
    let agent: CompanionAgent

    func pair(pin: String) async throws -> String {
        var req = URLRequest(url: agent.baseURL.appendingPathComponent("pair"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(["pin": pin])
        let (data, _) = try await URLSession.shared.data(for: req)
        struct Resp: Codable { let token: String }
        return try JSONDecoder().decode(Resp.self, from: data).token
    }

    func info() async throws -> AgentInfo {
        let (data, _) = try await URLSession.shared.data(for: authorized("info"))
        return try JSONDecoder().decode(AgentInfo.self, from: data)
    }

    func listFiles(path: String) async throws -> [RemoteFile] {
        var comps = URLComponents(url: agent.baseURL.appendingPathComponent("files"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [.init(name: "path", value: path)]
        var req = URLRequest(url: comps.url!)
        addAuth(&req)
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode([RemoteFile].self, from: data)
    }

    func download(path: String) async throws -> Data {
        var comps = URLComponents(url: agent.baseURL.appendingPathComponent("download"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [.init(name: "path", value: path)]
        var req = URLRequest(url: comps.url!)
        addAuth(&req)
        return try await URLSession.shared.data(for: req).0
    }

    func upload(data: Data, toPath path: String) async throws {
        var comps = URLComponents(url: agent.baseURL.appendingPathComponent("upload"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [.init(name: "path", value: path)]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        addAuth(&req)
        _ = try await URLSession.shared.upload(for: req, from: data)
    }

    /// URL für den MJPEG-Stream von Bildschirm bzw. Webcam.
    func streamURL(kind: StreamKind) -> URL {
        var comps = URLComponents(url: agent.baseURL.appendingPathComponent(kind.rawValue), resolvingAgainstBaseURL: false)!
        if let token = agent.token { comps.queryItems = [.init(name: "token", value: token)] }
        return comps.url!
    }

    enum StreamKind: String { case screen, webcam }

    private func authorized(_ path: String) -> URLRequest {
        var req = URLRequest(url: agent.baseURL.appendingPathComponent(path))
        addAuth(&req)
        return req
    }
    private func addAuth(_ req: inout URLRequest) {
        if let token = agent.token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
    }
}

struct RemoteFile: Codable, Identifiable, Hashable {
    var id: String { path }
    var name: String
    var path: String
    var isDirectory: Bool
    var size: Int
}
