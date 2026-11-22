import Foundation
import Network
import Combine

/// 本机 HTTP 入口：直播扩展把 OCR 文本 POST 到 127.0.0.1:8791，这里收下交给 App。
final class LiveBridge: ObservableObject {
    @Published var lastAt: Date?
    @Published var connected = false

    var onText: ((String) -> Void)?

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "live.bridge")

    func start(port: UInt16 = 8791) {
        guard listener == nil else { return }
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }
            params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: nwPort)
            let l = try NWListener(using: params)
            l.newConnectionHandler = { [weak self] conn in
                self?.accept(conn)
            }
            l.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    switch state {
                    case .ready: self?.connected = true
                    case .failed, .cancelled: self?.connected = false
                    default: break
                    }
                }
            }
            l.start(queue: queue)
            listener = l
        } catch {
            print("bridge start failed \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        connected = false
    }

    private func accept(_ conn: NWConnection) {
        conn.start(queue: queue)
        receive(conn, buffer: Data())
    }

    private func receive(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buf = buffer
            if let data { buf.append(data) }
            if error != nil || isComplete && buf.isEmpty {
                conn.cancel()
                return
            }
            guard let headerEnd = buf.range(of: Data("\r\n\r\n".utf8)) else {
                self.receive(conn, buffer: buf)
                return
            }
            let headerText = String(data: buf[buf.startIndex..<headerEnd.lowerBound], encoding: .utf8) ?? ""
            var need = 0
            for line in headerText.components(separatedBy: "\r\n") {
                let lower = line.lowercased()
                if lower.hasPrefix("content-length:") {
                    let v = line.split(separator: ":", maxSplits: 1).last ?? ""
                    need = Int(v.trimmingCharacters(in: .whitespaces)) ?? 0
                }
            }
            let body = buf[headerEnd.upperBound...]
            if body.count < need {
                self.receive(conn, buffer: buf)
                return
            }
            let payload = body.prefix(need)
            if let obj = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
               let text = obj["text"] as? String {
                DispatchQueue.main.async {
                    self.lastAt = Date()
                    self.onText?(text)
                }
            }
            let resp = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 11\r\nConnection: close\r\n\r\n{\"ok\":true}"
            conn.send(content: Data(resp.utf8), completion: .contentProcessed { _ in conn.cancel() })
        }
    }
}
