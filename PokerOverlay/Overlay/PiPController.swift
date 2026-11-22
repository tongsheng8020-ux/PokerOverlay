import AVKit
import AVFoundation
import UIKit
import Combine

extension Data {
    mutating func append(u32 v: UInt32) {
        var x = v.littleEndian
        withUnsafeBytes(of: &x) { append(contentsOf: ) }
    }
    mutating func append(u16 v: UInt16) {
        var x = v.littleEndian
        withUnsafeBytes(of: &x) { append(contentsOf: ) }
    }
}

/// 用系统画中画把决策浮在游戏上面。
/// PiP 是 iOS 上唯一能在别的 App 上方常驻显示第三方内容的系统能力。
final class PiPController: NSObject, ObservableObject {
    @Published var isActive = false
    @Published var possible = false
    @Published var available = AVPictureInPictureController.isPictureInPictureSupported()
    @Published var lastError: String?

    let displayLayer = AVSampleBufferDisplayLayer()

    private var pip: AVPictureInPictureController?
    private var timebase: CMTimebase?
    private var heartbeat: Timer?
    private var retryTimer: Timer?
    private var decision: Decision?
    private var mode: String = "long"
    private var startWanted = false
    private var attempt = 0
    private var possibleObs: NSKeyValueObservation?
    private var keepAlive: AVAudioPlayer?

    override init() {
        super.init()
        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = UIColor.black.cgColor
        displayLayer.frame = CGRect(x: 0, y: 0, width: 320, height: 180)
        configureAudio()
    }

    func configureAudio() {
        do {
            let s = AVAudioSession.sharedInstance()
            try s.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
            try s.setActive(true)
        } catch {
            print("audio session \(error)")
        }
    }

    func attach(to view: UIView) {
        if displayLayer.superlayer !== view.layer {
            view.layer.addSublayer(displayLayer)
        }
        updateLayerFrame(for: view)
        setupTimebaseIfNeeded()
        setupControllerIfNeeded()
    }

    private func updateLayerFrame(for view: UIView) {
        let size = view.bounds.size
        if size.width > 1 && size.height > 1 {
            displayLayer.frame = CGRect(origin: .zero, size: size)
        } else {
            displayLayer.frame = CGRect(x: 0, y: 0, width: 320, height: 180)
        }
    }

    private func setupTimebaseIfNeeded() {
        guard timebase == nil else { return }
        var tb: CMTimebase?
        CMTimebaseCreateWithSourceClock(allocator: kCFAllocatorDefault,
                                        sourceClock: CMClockGetHostTimeClock(),
                                        timebaseOut: &tb)
        guard let tb else { return }
        CMTimebaseSetTime(tb, time: .zero)
        CMTimebaseSetRate(tb, rate: 1)
        displayLayer.controlTimebase = tb
        timebase = tb
    }

    private func setupControllerIfNeeded() {
        guard pip == nil, AVPictureInPictureController.isPictureInPictureSupported() else { return }
        let source = AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: displayLayer,
                                                                playbackDelegate: self)
        let c = AVPictureInPictureController(contentSource: source)
        c.delegate = self
        c.canStartPictureInPictureAutomaticallyFromInline = true
        pip = c
        possibleObs = c.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] controller, _ in
            DispatchQueue.main.async {
                self?.possible = controller.isPictureInPicturePossible
            }
        }
    }

    func update(_ d: Decision, mode: String = "long") {
        decision = d
        self.mode = mode
        enqueueFrame()
    }

    func start() {
        configureAudio()
        setupControllerIfNeeded()
        guard let pip else {
            lastError = "此设备不支持画中画"
            return
        }
        lastError = nil
        startWanted = true
        attempt = 0
        enqueueFrame()
        if pip.isPictureInPictureActive { return }
        attemptStart()
    }

    private func attemptStart() {
        guard startWanted, let pip else { return }
        if pip.isPictureInPictureActive { return }
        if pip.isPictureInPicturePossible {
            pip.startPictureInPicture()
            startKeepAlive()
            startHeartbeat()
            return
        }
        attempt += 1
        if attempt > 12 {
            lastError = "画中画无法启动：先在 App 前台点按钮，并确认 设置→通用→画中画→自动开启已打开"
            startWanted = false
            return
        }
        enqueueFrame()
        retryTimer?.invalidate()
        retryTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            self?.attemptStart()
        }
    }

    func stop() {
        keepAlive?.stop()
        keepAlive = nil
        startWanted = false
        retryTimer?.invalidate()
        heartbeat?.invalidate()
        heartbeat = nil
        decision = nil
        pip?.stopPictureInPicture()
    }

    private func startKeepAlive() {
        guard keepAlive == nil, let url = silentWavURL() else { return }
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.numberOfLoops = -1
            p.volume = 1.0
            p.prepareToPlay()
            p.play()
            keepAlive = p
        } catch {
            print("keepalive \(error)")
        }
    }

    private func silentWavURL() -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poker_silence.wav")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        var d = Data()
        let rate: UInt32 = 8000, ch: UInt16 = 1, bits: UInt16 = 16
        let byteRate = rate * UInt32(ch) * UInt32(bits / 8)
        let dataSize = Int(rate) * Int(ch) * Int(bits / 8)
        d.append(contentsOf: Array("RIFF".utf8))
        d.append(u32: 36 + UInt32(dataSize))
        d.append(contentsOf: Array("WAVEfmt ".utf8))
        d.append(u32: 16); d.append(u16: 1); d.append(u16: ch)
        d.append(u32: rate); d.append(u32: byteRate)
        d.append(u16: UInt16(Int(ch) * Int(bits / 8))); d.append(u16: bits)
        d.append(contentsOf: Array("data".utf8))
        d.append(u32: UInt32(dataSize))
        d.append(Data(count: dataSize))
        do { try d.write(to: url) } catch {
            print("wav \(error)")
            return nil
        }
        return url
    }

    private func startHeartbeat() {
        heartbeat?.invalidate()
        heartbeat = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            self?.enqueueFrame()
        }
    }

    // MARK: - 帧生成

    private func enqueueFrame() {
        guard displayLayer.status != .failed else {
            displayLayer.flush()
            return
        }
        let image = OverlayRenderer.image(for: decision, mode: mode)
        guard let pixel = pixelBuffer(from: image) else { return }
        var fmt: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
                                                    imageBuffer: pixel,
                                                    formatDescriptionOut: &fmt)
        guard let fmt else { return }
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
            decodeTimeStamp: .invalid
        )
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault,
                                                 imageBuffer: pixel,
                                                 formatDescription: fmt,
                                                 sampleTiming: &timing,
                                                 sampleBufferOut: &sample)
        guard let sample else { return }
        CMSetAttachment(sample,
                        key: kCMSampleAttachmentKey_DisplayImmediately,
                        value: kCFBooleanTrue,
                        attachmentMode: kCMAttachmentMode_ShouldPropagate)
        if displayLayer.isReadyForMoreMediaData {
            displayLayer.enqueue(sample)
        }
    }

    private func pixelBuffer(from image: UIImage) -> CVPixelBuffer? {
        guard let cg = image.cgImage else { return nil }
        let width = cg.width, height = cg.height
        var pb: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                                         kCVPixelFormatType_32BGRA,
                                         attrs as CFDictionary, &pb)
        guard status == kCVReturnSuccess, let buffer = pb else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let ctx = CGContext(data: base, width: width, height: height,
                                  bitsPerComponent: 8,
                                  bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                  space: space, bitmapInfo: info) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }
}

extension PiPController: AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
        DispatchQueue.main.async {
            self.isActive = true
            self.startWanted = false
        }
        startHeartbeat()
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        DispatchQueue.main.async { self.isActive = false }
    }

    func pictureInPictureController(_ controller: AVPictureInPictureController,
                                    failedToStartPictureInPictureWithError error: Error) {
        DispatchQueue.main.async {
            self.isActive = false
            self.lastError = error.localizedDescription
        }
    }
}

extension PiPController: AVPictureInPictureSampleBufferPlaybackDelegate {
    func pictureInPictureController(_ controller: AVPictureInPictureController,
                                    setPlaying playing: Bool) {
        if playing { enqueueFrame() }
    }

    func pictureInPictureControllerTimeRangeForPlayback(_ controller: AVPictureInPictureController) -> CMTimeRange {
        CMTimeRange(start: .zero, duration: .positiveInfinity)
    }

    func pictureInPictureControllerIsPlaybackPaused(_ controller: AVPictureInPictureController) -> Bool {
        false
    }

    func pictureInPictureController(_ controller: AVPictureInPictureController,
                                    didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}

    func pictureInPictureController(_ controller: AVPictureInPictureController,
                                    skipByInterval skipInterval: CMTime,
                                    completion completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}
