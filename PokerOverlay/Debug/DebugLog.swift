import Foundation
import Combine

/// App 内调试日志：记录采集到了什么、没采集到什么，可导出 .txt。
final class DebugLog: ObservableObject {
    static let shared = DebugLog()

    @Published private(set) var entries: [String] = []

    private let fileURL: URL
    private let dirURL: URL
    private let stroke: DateFormatter

    init() {
        stroke = DateFormatter()
        stroke.dateFormat = "HH:mm:ss.SSS"
        dirURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = dirURL.appendingPathComponent("debug.log")
        if let text = try? String(contentsOf: fileURL, encoding: .utf8) {
            entries = text.split(separator: "\n").map(String.init)
        }
    }

    func add(_ message: String) {
        let line = "\(stroke.string(from: Date())) \(message)"
        entries.append(line)
        if entries.count > 1500 { entries.removeFirst(entries.count - 1500) }
        if let data = (line + "\n").data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: fileURL)
            }
        }
    }

    func clear() {
        entries.removeAll()
        try? "".write(to: fileURL, atomically: true, encoding: .utf8)
    }

    var text: String { entries.joined(separator: "\n") }

    /// 导出带时间戳的 .txt。
    func exportFile() -> URL? {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        let url = dirURL.appendingPathComponent("poker-debug-\(f.string(from: Date())).txt")
        let body = entries.isEmpty ? "(empty)\n" : entries.joined(separator: "\n") + "\n"
        do {
            try body.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}
