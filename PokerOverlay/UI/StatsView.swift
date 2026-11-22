import SwiftUI

struct StatsView: View {
    @EnvironmentObject var store: AppStore
    @State private var resultText = ""
    @State private var hole = ""
    @State private var position = ""
    @State private var win = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    cards
                    quickAdd
                    handsList
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
            }
            .navigationTitle("战绩")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await store.refreshAll() }
                    } label: { Image(systemName: "arrow.clockwise") }
                }
            }
            .refreshable { await store.refreshAll() }
        }
    }

    private var cards: some View {
        let ov = store.overview ?? Overview()
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            stat("总输赢", money(ov.total), color(ov.total), "\(Int(ov.bb_total)) BB")
            stat("BB / 100", String(format: "%.0f", ov.bb100), color(Int(ov.bb100)), "每 100 手")
            stat("手数 / 胜率", "\(ov.hands)", .primary, "胜率 \(String(format: "%.0f", ov.win_rate))%")
            stat("最大回撤", "\(ov.max_drawdown)", .red, "最长连输 \(ov.worst_streak) 手")
        }
        .padding(.top, 6)
    }

    private func stat(_ k: String, _ v: String, _ c: Color, _ s: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(k).font(.caption2).foregroundStyle(.secondary)
            Text(v).font(.title2.weight(.bold)).foregroundStyle(c)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(s).font(.caption2).foregroundStyle(.secondary.opacity(0.8))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
    }

    private var quickAdd: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("录一手").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                TextField("手牌 AhKh", text: $hole)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Picker("", selection: $win) {
                    Text("赢").tag(true)
                    Text("输").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 110)
                TextField("金额", text: $resultText)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 78)
            }
            HStack(spacing: 8) {
                TextField("位置（可空）", text: $position)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                Button {
                    Task { await save() }
                } label: {
                    Text("保存").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(Int(resultText) == nil)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
    }

    private var handsList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("最近手牌").font(.caption).foregroundStyle(.secondary)
            if store.hands.isEmpty {
                Text("还没有记录").font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                VStack(spacing: 0) {
                    ForEach(store.hands) { h in
                        HStack(spacing: 6) {
                            Text((h.created_at ?? "").suffix(11))
                                .font(.caption2).foregroundStyle(.secondary)
                                .frame(width: 74, alignment: .leading)
                            Text(h.position ?? "-")
                                .font(.caption).frame(width: 34, alignment: .leading)
                            Text(h.hole ?? "-")
                                .font(.caption.monospaced())
                            Spacer()
                            Text(money(h.result))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(color(h.result))
                        }
                        .padding(.vertical, 7)
                        Divider().opacity(0.2)
                    }
                }
                .padding(.horizontal, 12)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private func save() async {
        guard let v = Int(resultText) else { return }
        await store.addQuickHand(result: win ? abs(v) : -abs(v), hole: hole, position: position)
        resultText = ""
        hole = ""
    }

    private func money(_ v: Int) -> String {
        (v > 0 ? "+" : "") + String(v)
    }

    private func color(_ v: Int) -> Color {
        v > 0 ? Color(red: 0.25, green: 0.85, blue: 0.5) : (v < 0 ? .red : .primary)
    }
}
