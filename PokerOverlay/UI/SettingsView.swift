import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @State private var testing = false
    @State private var testResult: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("连接") {
                    Button {
                        Task { await test() }
                    } label: {
                        HStack {
                            Text("测试连接")
                            Spacer()
                            if testing { ProgressView() }
                        }
                    }
                    if let testResult {
                        Text(testResult).font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("牌局类型") {
                    Picker("分析模式", selection: $store.mode) {
                        Text("长牌 52").tag("long")
                        Text("短牌 36").tag("short")
                    }
                    .pickerStyle(.segmented)
                    Text("AI 按这里选的规则分析：长牌 52 张；短牌 36 张（三条>顺子、同花>葫芦）。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("余额") {
                    if let b = store.billing {
                        HStack {
                            Text("余额")
                            Spacer()
                            Text(String(format: "¥ %.4f", b.balance))
                                .font(.headline)
                                .monospacedDigit()
                        }
                        HStack {
                            Text("已用")
                            Spacer()
                            Text(String(format: "¥ %.4f", b.spent))
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("调用 / Token")
                            Spacer()
                            Text("\(b.calls) 次 / \(b.tokens)")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("暂无数据").foregroundStyle(.secondary)
                    }
                    Button("刷新余额") {
                        Task { await store.refreshBilling() }
                    }
                }

                Section("状态") {
                    HStack {
                        Text("服务器")
                        Spacer()
                        Text(store.serverOK == true ? "在线" : (store.serverOK == false ? "连不上" : "未检测"))
                            .foregroundStyle(store.serverOK == true ? .green : .secondary)
                    }
                    HStack {
                        Text("访问密码")
                        Spacer()
                        Text(store.pin.isEmpty ? "未设置" : "已设置")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Text("牌桌页直接打开 zzpk.vip，AI 悬浮条在顶部；点条展开，点「收」收起，点「AI」气泡复原。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func test() async {
        testing = true
        testResult = nil
        do {
            let h = try await store.api.health()
            let model = h["model"] as? String ?? "?"
            testResult = "连接成功 · \(model)"
            store.serverOK = true
            await store.refreshAll()
        } catch {
            testResult = "失败：\(error.localizedDescription)"
            store.serverOK = false
        }
        testing = false
    }
}
