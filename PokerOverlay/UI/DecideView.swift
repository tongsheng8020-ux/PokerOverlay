import SwiftUI

struct DecideView: View {
    @EnvironmentObject var store: AppStore
    @State private var showCaptureHelp = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    modePicker
                    liveBanner
                    editor
                    decideButton
                    if let d = store.decision {
                        DecisionCardView(decision: d, mode: store.mode)
                    }
                    overlayPanel
                    if let e = store.errorText {
                        Text(e).font(.caption).foregroundStyle(.red)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("德州助手")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Image(systemName: store.serverOK == true ? "bolt.fill" :
                            (store.serverOK == false ? "bolt.slash" : "bolt"))
                        .foregroundStyle(store.serverOK == true ? .green : .secondary)
                }
            }
            .sheet(isPresented: $showCaptureHelp) { CaptureHelpView() }
        }
    }

    private var modePicker: some View {
        Picker("模式", selection: $store.mode) {
            Text("长牌").tag("long")
            Text("短牌").tag("short")
            Text("伙牌").tag("team")
        }
        .pickerStyle(.segmented)
    }

    private var liveBanner: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(store.bridgeConnected ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.bridgeConnected ? "屏幕识别已连接" : "屏幕识别未启动")
                    .font(.footnote.weight(.semibold))
                Text(store.liveStatus)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("怎么开") { showCaptureHelp = true }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(12)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("实时识别会自动读屏；这里只做兜底和修正")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: $store.raw)
                .font(.system(size: 14, design: .monospaced))
                .frame(minHeight: 92)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
                .overlay(alignment: .topLeading) {
                    if store.raw.isEmpty {
                        Text("L6 BTN AhKh | Qh7c2h | P:24 C:8 | H:198 V:186")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(.secondary.opacity(0.6))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    private var decideButton: some View {
        Button {
            Task { await store.decide() }
        } label: {
            HStack {
                if store.loading { ProgressView().tint(.black) }
                Text(store.loading ? "算牌中…" : "出 决 策")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(Color(red: 0.35, green: 0.65, blue: 1))
        .disabled(store.loading)
    }

    private var overlayPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("游戏最前端浮窗")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(store.pipActive ? "已浮窗" : (store.pipPossible ? "可启动" : "准备中"))
                    .font(.caption2)
                    .foregroundStyle(store.pipActive ? .green : .secondary)
            }
            PiPHost(pip: store.pip)
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08)))
            HStack(spacing: 10) {
                Button {
                    if let d = store.decision { store.pip.update(d, mode: store.mode) }
                    store.startOverlay()
                } label: {
                    Text("浮到游戏上").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.35, green: 0.65, blue: 1))

                Button {
                    store.pip.stop()
                } label: {
                    Text("收起").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.regular)
            if let err = store.pipError {
                Text(err).font(.caption2).foregroundStyle(.orange)
            }
            Text("点完按钮先别切 App，等小窗出现（首次约 1 秒）；没出现就看上面这行提示。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
    }
}

struct CaptureHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    step(1, "先点「浮到游戏上」，让决策窗出现。")
                    step(2, "下拉控制中心 → 点「屏幕录制」按钮（圆圈）。")
                    step(3, "选择「德州助手 · 屏幕识别」，点「开始直播」。")
                    step(4, "切回游戏，决策窗会盖在游戏上方，随画面自动更新。")
                    step(5, "结束时从控制中心停止直播。")
                    Divider().padding(.vertical, 6)
                    Text("提示")
                        .font(.headline)
                    Text("识别是整屏 OCR：牌面、底池、筹码、按钮文字都会被读进服务器解析。桌面越干净、游戏窗口越大，识别越准。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("直播扩展不消耗额外权限，iOS 需要你每次手动开播，这是系统限制。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("开启实时识别")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("知道了") { dismiss() }
                }
            }
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)")
                .font(.caption.bold())
                .frame(width: 22, height: 22)
                .background(Color.blue.opacity(0.25), in: Circle())
            Text(text).font(.subheadline)
        }
    }
}

struct PiPHost: UIViewRepresentable {
    @ObservedObject var pip: PiPController

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .black
        v.clipsToBounds = true
        pip.attach(to: v)
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        pip.attach(to: uiView)
    }
}
