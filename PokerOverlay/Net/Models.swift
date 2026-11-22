import Foundation

struct CostInfo: Codable {
    var charged: Double = 0
    var raw: Double = 0
    var markup: Double = 1
    var peak: Bool = false
}

struct Decision: Codable, Identifiable {
    var id = UUID()
    var ok: Bool? = nil
    var text: String = ""
    var action: String? = nil
    var latency_ms: Int? = nil
    var model: String? = nil
    var source: String? = nil
    var cost: CostInfo? = nil
    var billing: Billing? = nil

    enum CodingKeys: String, CodingKey {
        case ok, text, action, latency_ms, model, source, cost, billing
    }

    var latency: Int { latency_ms ?? 0 }

    var size: String { field("尺寸") }
    var numbers: String { field("数字") }
    var reason: String { field("理由") }
    var alternative: String { field("备选") }

    var confidence: Int {
        let digits = field("置信度").filter { $0.isNumber }
        return Int(String(digits.prefix(3))) ?? 0
    }

    private func field(_ name: String) -> String {
        for line in text.split(separator: "\n") {
            var s = String(line).trimmingCharacters(in: .whitespaces)
            let tag = "【\(name)】"
            guard s.contains(tag) else { continue }
            s = s.replacingOccurrences(of: tag, with: "")
            s = s.replacingOccurrences(of: "：", with: "")
            return s.trimmingCharacters(in: .whitespaces)
        }
        return ""
    }
}

struct KeyInfo: Codable {
    var ok: Bool = true
    var expires_at: String? = nil
    var kind: String? = nil
}

struct PromptRecord: Codable, Identifiable {
    var id: Int = 0
    var mode: String = ""
    var action: String = ""
    var reply: String = ""
    var latency_ms: Int = 0
    var created_at: String = ""

    var size: String { field("尺寸") }
    var reason: String { field("理由") }
    var confidence: Int {
        Int(field("置信度").filter { $0.isNumber }.prefix(3)) ?? 0
    }

    private func field(_ name: String) -> String {
        for line in reply.split(separator: "\n") {
            var s = String(line).trimmingCharacters(in: .whitespaces)
            let tag = "【\(name)】"
            guard s.contains(tag) else { continue }
            s = s.replacingOccurrences(of: tag, with: "")
            s = s.replacingOccurrences(of: "：", with: "")
            return s.trimmingCharacters(in: .whitespaces)
        }
        return ""
    }
}

struct Opponent: Codable, Identifiable {
    var player_id: String = ""
    var name: String = ""
    var hands: Int = 0
    var vpip: Int = 0
    var folds: Int = 0
    var allins: Int = 0
    var bets: Int = 0
    var calls: Int = 0
    var checks: Int = 0
    var af: Double = 0
    var tags: [String] = []
    var last_seen: String? = nil
    var id: String { player_id }
}

struct Billing: Codable {
    var balance: Double = 0
    var spent: Double = 0
    var calls: Int = 0
    var tokens: Int = 0
    var updated_at: String? = nil
}

struct Overview: Codable {
    var hands: Int = 0
    var total: Int = 0
    var bb_total: Double = 0
    var bb100: Double = 0
    var win_rate: Double = 0
    var avg: Double = 0
    var max_drawdown: Int = 0
    var worst_streak: Int = 0
    var today: Int = 0
    var today_hands: Int = 0
    var week: Int = 0
}

struct HandRow: Codable, Identifiable {
    var id: Int = 0
    var created_at: String? = nil
    var position: String? = nil
    var hole: String? = nil
    var result: Int = 0
    var game_type: String? = nil
    var result_bb: Double? = nil
}

struct HandsPage: Codable {
    var total: Int = 0
    var rows: [HandRow] = []
}

struct DayPoint: Codable, Identifiable {
    var date: String = ""
    var hands: Int = 0
    var win: Int = 0
    var cum: Int = 0
    var id: String { date }
}
