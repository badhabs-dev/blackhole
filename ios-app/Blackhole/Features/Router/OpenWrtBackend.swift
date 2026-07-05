import Foundation

/// Beispiel-Backend für **OpenWrt** über die ubus-JSON-RPC-Schnittstelle (LuCI).
///
/// OpenWrt ist ideal für diese App, weil es echte Kontrolle erlaubt:
///  - Login: `session.login` → liefert ein `ubus_rpc_session`-Token.
///  - Geräteliste: `ubus call luci-rpc getDHCPLeases` + `iwinfo` (WLAN-Clients).
///  - **Kicken**: `iwinfo`-Deauth bzw. Firewall-DROP der MAC.
///  - **Bannen**: MAC-Filter / `iptables -A FORWARD -m mac --mac-source … -j DROP`.
///  - **Boosten/Drosseln**: `tc` (HTB/SQM) pro IP → echtes Bandbreitenlimit.
///
/// Voraussetzung auf dem Router: `uhttpd-mod-ubus` + `rpcd` (Standard bei LuCI).
struct OpenWrtBackend: RouterBackend {
    let displayName = "OpenWrt (ubus RPC)"
    let host: String
    let username: String
    let password: String

    private var rpcURL: URL { URL(string: "http://\(host)/ubus")! }

    func listClients() async throws -> [RouterClient] {
        let token = try await login()
        let leases = try await rpc(token: token, object: "luci-rpc", method: "getDHCPLeases", params: [:])
        // Aus der JSON-Antwort die Leases mappen (vereinfacht).
        guard let dhcp = leases["dhcp_leases"] as? [[String: Any]] else { return [] }
        return dhcp.map { lease in
            RouterClient(
                id: (lease["macaddr"] as? String) ?? UUID().uuidString,
                name: (lease["hostname"] as? String) ?? "unbekannt",
                ip: (lease["ipaddr"] as? String) ?? "",
                mac: (lease["macaddr"] as? String) ?? "",
                isBlocked: false,
                isWireless: true
            )
        }
    }

    func setBlocked(_ client: RouterClient, blocked: Bool) async throws {
        let token = try await login()
        // Firewall-Regel per MAC setzen/entfernen.
        let cmd = blocked
            ? "iptables -I FORWARD -m mac --mac-source \(client.mac) -j DROP"
            : "iptables -D FORWARD -m mac --mac-source \(client.mac) -j DROP"
        _ = try await rpc(token: token, object: "file", method: "exec",
                          params: ["command": "/bin/sh", "params": ["-c", cmd]])
    }

    func setQoS(_ client: RouterClient, priority: QoSPriority, limitMbps: Int?) async throws {
        let token = try await login()
        let rate = limitMbps.map { "\($0)mbit" } ?? (priority == .low ? "2mbit" : "1000mbit")
        // Vereinfachtes tc-Setup: eigene Klasse je IP mit Ratelimit.
        let cmd = """
        tc qdisc add dev br-lan root handle 1: htb 2>/dev/null; \
        tc class replace dev br-lan parent 1: classid 1:10 htb rate \(rate); \
        tc filter replace dev br-lan protocol ip parent 1: prio 1 u32 \
           match ip dst \(client.ip)/32 flowid 1:10
        """
        _ = try await rpc(token: token, object: "file", method: "exec",
                          params: ["command": "/bin/sh", "params": ["-c", cmd]])
    }

    func setInternetSchedule(_ client: RouterClient, allowed: Bool) async throws {
        try await setBlocked(client, blocked: !allowed)
    }

    // MARK: - ubus JSON-RPC

    private func login() async throws -> String {
        let body: [String: Any] = [
            "jsonrpc": "2.0", "id": 1, "method": "call",
            "params": ["00000000000000000000000000000000", "session", "login",
                       ["username": username, "password": password]]
        ]
        let json = try await post(body)
        guard let result = json["result"] as? [Any],
              let data = result.last as? [String: Any],
              let token = data["ubus_rpc_session"] as? String else {
            throw RouterError.auth
        }
        return token
    }

    private func rpc(token: String, object: String, method: String, params: [String: Any]) async throws -> [String: Any] {
        let body: [String: Any] = [
            "jsonrpc": "2.0", "id": 2, "method": "call",
            "params": [token, object, method, params]
        ]
        let json = try await post(body)
        if let result = json["result"] as? [Any], let payload = result.last as? [String: Any] {
            return payload
        }
        return [:]
    }

    private func post(_ body: [String: Any]) async throws -> [String: Any] {
        var req = URLRequest(url: rpcURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: req)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}
