import AVKit
import AVFoundation
import UIKit
import Combine

/// 用系统画中画把决策浮在游戏上面。
/// PiP 是 iOS 上唯一能在别的 App 上方常驻显示第三方内容的系统能力。
final class PiPController: NSObject, ObservableObject {
    @Published var isActive = false
    @Published var available = AVPictureInPictureController.isPictureInPictureSupported()
    @Published var lastError: String?

    let displayLayer = AVSampleBufferDisplayLayer()

    private var pip: AVPictureInPictureController?
    private var timebase: CMTimebase?
    private var heartbeat: Timer?
    private var decision: Decision?
    private var mode: String = "long"
    private weak var hostView: UIView?

    override init() {
        super.init()
        displayLayer.videoGravity = .resizeAspect
        configureAudio()
    }

    func configureAudio() {
        do {
            let s = AVAudioSession.sharedInstance()
            try s.setCategory(.playback, mode: .moviePlayback, options: [])
            try s.setActive(true)
        } catch {
            print("audio session \(error)")
        }
    }

    func attach(to view: UIView) {
        hostView = view
        if displayLayer.superlayer !== view.layer {
            displayLayer.frame = view.bounds
            view.layer.addSublayer(displayLayer)
        } else {
            displayLayer.frame = view.bounds
        }
        setupTimebaseIfNeeded()
        setupControllerIfNeeded()
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
        enqueueFrame()
        if pip.isPictureInPictureActive { return }
        pip.startPictureInPicture()
        startHeartbeat()
    }

    func stop() {
        pip?.stopPictureInPicture()
        heartbeat?.invalidate()
        heartbeat = nil
    }

    private func startHeartbeat() {
        heartbeat?.invalidate()
        heartbeat = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
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
        DispatchQueue.main.async { self.isActive = true }
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
