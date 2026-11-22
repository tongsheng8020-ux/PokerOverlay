import Foundation
import Combine

/// App 内调试日志：记录采集到了什么、没采集到什么。
final class DebugLog: ObservableObject {
    static let shared = DebugLog()

    @Published private(set) var entries: [String] = []

    private let fileURL: URL
    private let stamp: DateFormatter

    init() {
        stamp = DateFormatter()
        stamp.dateFormat = "HH:mm:ss.SSS"
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = dir.appendingPathComponent("debug.log")
        if let text = try? String(contentsOf: fileURL, encoding: .utf8) {
            entries = text.split(separator: "\n").map(String.init)
        }
    }

    func add(_ message: String) {
        let line = "\(stamp.string(from: Date())) \(message)"
        entries.append(line)
        if entries.count > 800 { entries.removeFirst(entries.count - 800) }
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
}
