import SwiftUI

struct OpponentsView: View {
    @EnvironmentObject var store: AppStore
    @State private var items: [Opponent] = []
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "person.2.slash").font(.largeTitle)
                        Text("当前房间暂无对手数据").foregroundStyle(.secondary)
                        Text("入座开打后，这里只显示本桌的人")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    List(items) { o in
                        row(o)
                            .listRowBackground(Color.white.opacity(0.04))
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("对手信息")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await load() }
                    } label: {
                        if loading { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                    }
                }
            }
            .refreshable { await load() }
            .overlay(alignment: .bottom) {
                if let e = error {
                    Text(e).font(.caption).foregroundStyle(.red).padding(8)
                }
            }
        }
        .task { await load() }
    }

    private func row(_ o: Opponent) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(o.name.isEmpty ? String(o.player_id.prefix(8)) : o.name)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                ForEach(o.tags, id: \.self) { t in
                    Text(t)
                        .font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Color.blue.opacity(0.2), in: Capsule())
                }
                Spacer()
                Text("\(o.hands) 手")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 14) {
                metric("入池", "\(o.vpip)%")
                metric("弃牌", "\(o.folds)%")
                metric("AF", String(format: "%.1f", o.af))
                metric("全下", "\(o.allins)")
                metric("下/跟/过", "\(o.bets)/\(o.calls)/\(o.checks)")
            }
            if let last = o.last_seen {
                Text("最后见到 \(o.lastSeenText)")
                    .font(.caption2).foregroundStyle(.secondary.opacity(0.7))
            }
        }
        .padding(.vertical, 4)
    }

    private func metric(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(k).font(.system(size: 9)).foregroundStyle(.secondary)
            Text(v).font(.system(size: 12, weight: .medium, design: .rounded))
        }
    }

    private func load() async {
        loading = true
        error = nil
        do {
            items = try await store.api.opponents(ids: store.currentPlayerIds)
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}
