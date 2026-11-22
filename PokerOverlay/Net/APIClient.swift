import Foundation

enum APIError: LocalizedError {
    case badURL
    case status(Int, String)
    case decoding(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .badURL: return "服务器地址不对"
        case .status(let code, let body): return "HTTP \(code) \(body.prefix(120))"
        case .decoding(let m): return "解析失败 \(m)"
        case .network(let m): return "网络错误 \(m)"
        }
    }
}

struct APIClient {
    var base: String
    var pin: String

    private func request(_ path: String, method: String = "GET", body: [String: Any]? = nil) throws -> URLRequest {
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed + path) else { throw APIError.badURL }
        var req = URLRequest(url: url, timeoutInterval: 70)
        req.httpMethod = method
        req.setValue(pin, forHTTPHeaderField: "X-Pin")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return req
    }

    private func send<T: Decodable>(_ req: URLRequest, as: T.Type) async throws -> T {
        let started = Date()
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            DebugLog.shared.add("[HTTP] \(req.httpMethod ?? "GET") \(req.url?.path ?? "") \(code) \(ms)ms")
            guard let http = resp as? HTTPURLResponse else { throw APIError.network("no response") }
            if http.statusCode != 200 {
                throw APIError.status(http.statusCode, String(data: data, encoding: .utf8) ?? "")
            }
            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                throw APIError.decoding(String(data: data, encoding: .utf8)?.prefix(160).description ?? "\(error)")
            }
        } catch let e as APIError {
            throw e
        } catch {
            DebugLog.shared.add("[HTTP] ERR \(req.url?.path ?? "") \(error.localizedDescription)")
            throw APIError.network(error.localizedDescription)
        }
    }

    func decide(mode: String, raw: String?, extra: [String: Any] = [:]) async throws -> Decision {
        var body: [String: Any] = ["mode": mode]
        if let raw, !raw.isEmpty { body["raw"] = raw }
        for (k, v) in extra { body[k] = v }
        return try await send(try request("/api/decide", method: "POST", body: body), as: Decision.self)
    }

    func vision(text: String, mode: String) async throws -> Decision {
        let body: [String: Any] = ["text": text, "mode": mode, "source": "ios-capture"]
        return try await send(try request("/api/vision", method: "POST", body: body), as: Decision.self)
    }

    func opponents() async throws -> [Opponent] {
        try await send(try request("/api/opponents/list?limit=200"), as: [Opponent].self)
    }

    func billing() async throws -> Billing {
        try await send(try request("/api/billing"), as: Billing.self)
    }

    func overview() async throws -> Overview {
        try await send(try request("/api/stats/overview"), as: Overview.self)
    }

    func hands(limit: Int = 20) async throws -> HandsPage {
        try await send(try request("/api/stats/hands?limit=\(limit)"), as: HandsPage.self)
    }

    func daily() async throws -> [DayPoint] {
        try await send(try request("/api/stats/daily"), as: [DayPoint].self)
    }

    func addHand(result: Int, hole: String?, position: String?, gameType: String) async throws {
        var body: [String: Any] = ["result": result, "game_type": gameType, "bb": 2]
        if let hole, !hole.isEmpty { body["hole"] = hole }
        if let position, !position.isEmpty { body["position"] = position }
        let req = try request("/api/hands", method: "POST", body: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError.status((resp as? HTTPURLResponse)?.statusCode ?? -1,
                                  String(data: data, encoding: .utf8) ?? "")
        }
    }

    func health() async throws -> [String: Any] {
        let req = try request("/api/health")
        let (data, _) = try await URLSession.shared.data(for: req)
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}
