import ReplayKit
import Vision
import CoreImage
import Foundation

/// 系统「屏幕录制」扩展：把当前屏幕 OCR 成文字，POST 给本机 App。
/// 它只负责看，不负责显示；显示由 App 的画中画浮窗完成。
final class SampleHandler: RPBroadcastSampleHandler {
    private let ciContext = CIContext()
    private let queue = DispatchQueue(label: "poker.ocr", qos: .userInitiated)
    private var lastAt = Date.distantPast
    private var lastText = ""

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        lastAt = .distantPast
        lastText = ""
    }

    override func broadcastFinished() {
        lastText = ""
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer,
                                      with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video else { return }
        let now = Date()
        guard now.timeIntervalSince(lastAt) >= 1.0 else { return }
        lastAt = now
        queue.async { [weak self] in
            self?.recognize(sampleBuffer)
        }
    }

    private func recognize(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.010

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        try? handler.perform([request])

        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        let text = lines.joined(separator: "\n")
        guard text.count > 8, text != lastText else { return }
        lastText = text
        post(text)
    }

    private func post(_ text: String) {
        guard let url = URL(string: "http://127.0.0.1:8791/ocr") else { return }
        var req = URLRequest(url: url, timeoutInterval: 2.5)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["text": text])
        URLSession.shared.dataTask(with: req).resume()
    }
}
