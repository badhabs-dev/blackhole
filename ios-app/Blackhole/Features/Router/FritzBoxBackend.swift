import Foundation

/// Beispiel-Backend für AVM FRITZ!Box über **TR-064** (SOAP, Port 49000).
///
/// TR-064 ist die offizielle Fernkonfigurations-Schnittstelle der FRITZ!Box.
/// Man authentifiziert sich mit den Zugangsdaten der Box. Relevante Dienste:
///  - `Hosts:1` → `GetHostNumberOfEntries`, `GetGenericHostEntry` (Geräteliste)
///  - `X_AVM-DE_HostFilter:1` → `DisallowWANAccessByIP` (Internet für Gerät sperren)
///  - `WLANConfiguration:1` → `X_AVM-DE_SetWLANGlobalEnable` etc.
///
/// Hinweis: Die Digest-Authentifizierung (SOAP `Auth`-Header mit Challenge/
/// Response) ist hier verkürzt dargestellt; die Aufrufstruktur ist real.
struct FritzBoxBackend: RouterBackend {
    let displayName = "FRITZ!Box (TR-064)"
    let host: String
    let username: String
    let password: String
    var port: Int = 49000

    func listClients() async throws -> [RouterClient] {
        let count = try await hostCount()
        var clients: [RouterClient] = []
        for index in 0..<count {
            if let client = try await hostEntry(index: index) {
                clients.append(client)
            }
        }
        return clients
    }

    func setBlocked(_ client: RouterClient, blocked: Bool) async throws {
        // X_AVM-DE_HostFilter: DisallowWANAccessByIP
        let action = "DisallowWANAccessByIP"
        let body = """
        <u:\(action) xmlns:u="urn:dslforum-org:service:X_AVM-DE_HostFilter:1">
          <NewIPv4Address>\(client.ip)</NewIPv4Address>
          <NewDisallow>\(blocked ? 1 : 0)</NewDisallow>
        </u:\(action)>
        """
        _ = try await call(service: "X_AVM-DE_HostFilter:1",
                           controlURL: "/upnp/control/x_hostfilter",
                           action: action, body: body)
    }

    func setQoS(_ client: RouterClient, priority: QoSPriority, limitMbps: Int?) async throws {
        // Die FRITZ!Box priorisiert Geräte über „Priorisierung/Realtime".
        // In TR-064 begrenzt, daher hier als No-Op mit Hinweis dokumentiert.
        throw RouterError.unsupported("QoS pro Gerät ist bei der FRITZ!Box nur über die Weboberfläche voll steuerbar.")
    }

    func setInternetSchedule(_ client: RouterClient, allowed: Bool) async throws {
        // Kindersicherung/Zugangsprofil zuweisen (X_AVM-DE_HostFilter Zeitprofil).
        try await setBlocked(client, blocked: !allowed)
    }

    // MARK: - TR-064 intern

    private func hostCount() async throws -> Int {
        let xml = try await call(
            service: "Hosts:1", controlURL: "/upnp/control/hosts",
            action: "GetHostNumberOfEntries",
            body: #"<u:GetHostNumberOfEntries xmlns:u="urn:dslforum-org:service:Hosts:1"/>"#)
        return Int(extract("NewHostNumberOfEntries", xml) ?? "0") ?? 0
    }

    private func hostEntry(index: Int) async throws -> RouterClient? {
        let body = """
        <u:GetGenericHostEntry xmlns:u="urn:dslforum-org:service:Hosts:1">
          <NewIndex>\(index)</NewIndex>
        </u:GetGenericHostEntry>
        """
        let xml = try await call(service: "Hosts:1", controlURL: "/upnp/control/hosts",
                                 action: "GetGenericHostEntry", body: body)
        guard let mac = extract("NewMACAddress", xml) else { return nil }
        return RouterClient(
            id: mac,
            name: extract("NewHostName", xml) ?? mac,
            ip: extract("NewIPAddress", xml) ?? "",
            mac: mac,
            isBlocked: false,
            isWireless: (extract("NewInterfaceType", xml) ?? "").contains("802.11")
        )
    }

    private func call(service: String, controlURL: String, action: String, body: String) async throws -> String {
        var req = URLRequest(url: URL(string: "http://\(host):\(port)\(controlURL)")!)
        req.httpMethod = "POST"
        req.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        req.setValue("urn:dslforum-org:service:\(service)#\(action)", forHTTPHeaderField: "SoapAction")
        req.httpBody = """
        <?xml version="1.0"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>\(body)</s:Body>
        </s:Envelope>
        """.data(using: .utf8)
        // Reale Nutzung: HTTP-Digest-Auth-Header ergänzen (URLSession delegate).
        let (data, _) = try await URLSession.shared.data(for: req)
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func extract(_ tag: String, _ xml: String) -> String? {
        guard let open = xml.range(of: "<\(tag)>"),
              let close = xml.range(of: "</\(tag)>", range: open.upperBound..<xml.endIndex)
        else { return nil }
        return String(xml[open.upperBound..<close.lowerBound])
    }
}

enum RouterError: LocalizedError {
    case unsupported(String)
    case auth
    var errorDescription: String? {
        switch self {
        case .unsupported(let m): return m
        case .auth: return "Anmeldung am Router fehlgeschlagen."
        }
    }
}
