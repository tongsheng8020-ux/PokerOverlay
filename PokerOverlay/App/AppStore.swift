import Foundation
import SwiftUI
import AVFoundation
import Combine

@MainActor
final class AppStore: ObservableObject {
    @Published var baseURL: String { didSet { defaults.set(baseURL, forKey: "base") } }
    @Published var pin: String { didSet { defaults.set(pin, forKey: "pin") } }
    @Published var mode: String = "long"
    @Published var raw: String = ""
    @Published var decision: Decision?
    @Published var loading = false
    @Published var errorText: String?
    @Published var overview: Overview?
    @Published var hands: [HandRow] = []
    @Published var daily: [DayPoint] = []
    @Published var autoSpeak = true
    @Published var liveStatus = "实时识别未开启"
    @Published var liveText = ""
    @Published var showPinGate = false
    @Published var serverOK: Bool?
    @Published var billing: Billing?
    @Published var bridgeConnected = false
    @Published var pipActive = false
    @Published var pipPossible = false
    @Published var pipLastFrame: Date?
    @Published var pipError: String?

    let pip = PiPController()
    let bridge = LiveBridge()
    private let defaults = UserDefaults.standard
    private let speaker = AVSpeechSynthesizer()
    private var lastLive = ""
    private var busy = false

    init() {
        let savedBase = UserDefaults.standard.string(forKey: "base") ?? "http://64.90.0.27:8099"
        let savedPin = UserDefaults.standard.string(forKey: "pin") ?? ""
        baseURL = savedBase
        pin = savedPin
        showPinGate = savedPin.isEmpty
        bridge.onText = { [weak self] text in
            Task { @MainActor in await self?.handleLive(text) }
        }
        bridge.$connected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] v in Task { @MainActor in self?.bridgeConnected = v } }
            .store(in: &bag)
        pip.$isActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] v in Task { @MainActor in self?.pipActive = v } }
            .store(in: &bag)
        pip.$possible
            .receive(on: DispatchQueue.main)
            .sink { [weak self] v in Task { @MainActor in self?.pipPossible = v } }
            .store(in: &bag)
        pip.$lastFrameAt
            .receive(on: DispatchQueue.main)
            .sink { [weak self] v in Task { @MainActor in self?.pipLastFrame = v } }
            .store(in: &bag)
        pip.$lastError
            .receive(on: DispatchQueue.main)
            .sink { [weak self] v in Task { @MainActor in self?.pipError = v } }
            .store(in: &bag)
    }

    private var bag = Set<AnyCancellable>()

    var api: APIClient { APIClient(base: baseURL, pin: pin) }

    func boot() {
        bridge.start()
        Task { await ping(); await refreshAll() }
    }

    func ping() async {
        do {
            _ = try await api.health()
            serverOK = true
        } catch {
            serverOK = false
        }
    }

    func decide() async {
        guard !busy else { return }
        busy = true
        loading = true
        errorText = nil
        defer { busy = false; loading = false }
        do {
            let d = try await api.decide(mode: mode, raw: raw.isEmpty ? nil : raw)
            apply(d)
        } catch {
            errorText = error.localizedDescription
        }
    }

    func handleLive(_ text: String) async {
        liveText = text
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 8, trimmed != lastLive else { return }
        lastLive = trimmed
        liveStatus = "识别中…"
        do {
            let d = try await api.vision(text: trimmed, mode: mode)
            apply(d)
            liveStatus = "已更新 · \(d.latency)ms"
        } catch {
            liveStatus = "识别失败：\(error.localizedDescription)"
        }
    }

    func applyWeb(_ d: Decision) {
        decision = d
        if let b = d.billing { billing = b }
        pip.update(d, mode: mode)
    }

    func refreshBilling() async {
        if let b = try? await api.billing() { billing = b }
    }

    private func apply(_ d: Decision) {
        decision = d
        pip.update(d, mode: mode)
        if autoSpeak, let a = d.action, !a.isEmpty {
            speak("\(a)，\(d.size)")
        }
    }

    func speak(_ s: String) {
        guard !s.isEmpty else { return }
        speaker.stopSpeaking(at: .immediate)
        let u = AVSpeechUtterance(string: s)
        u.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        u.rate = 1.02
        speaker.speak(u)
    }

    func startOverlay() {
        pip.start()
    }

    func refreshAll() async {
        if pin.isEmpty { return }
        do {
            async let ov = api.overview()
            async let hs = api.hands(limit: 20)
            async let dl = api.daily()
            overview = try await ov
            hands = try await hs.rows
            daily = try await dl
            if let b = try? await api.billing() { billing = b }
            serverOK = true
        } catch {
            errorText = error.localizedDescription
        }
    }

    func addQuickHand(result: Int, hole: String, position: String) async {
        do {
            try await api.addHand(result: result, hole: hole, position: position, gameType: mode)
            await refreshAll()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

