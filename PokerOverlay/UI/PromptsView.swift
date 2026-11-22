import SwiftUI

struct PromptsView: View {
    @EnvironmentObject var store: AppStore
    @State private var items: [PromptRecord] = []
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath").font(.largeTitle)
                        Text("还没有提示记录").foregroundStyle(.secondary)
                        Text("轮到你出过建议后，这里会逐条记下来")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    List(items) { r in
                        row(r).listRowBackground(Color.white.opacity(0.04))
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("提示历史")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await load() } } label: {
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

    private func row(_ r: PromptRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(r.action.isEmpty ? "—" : r.action)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(color(r.action))
                if !r.size.isEmpty {
                    Text(r.size)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                Spacer()
                Text(r.mode == "short" ? "短牌" : (r.mode == "team" ? "伙牌" : "长牌"))
                    .font(.caption2)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Color.blue.opacity(0.18), in: Capsule())
                Text(r.timeText)
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if !r.reason.isEmpty {
                Text(r.reason)
                    .font(.caption)
                    .foregroundStyle(Color(white: 0.75))
                    .lineLimit(3)
            }
            HStack(spacing: 10) {
                Text("置信度 \(r.confidence)").font(.caption2).foregroundStyle(.secondary)
                Text("\(r.latency_ms)ms").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func color(_ a: String) -> Color {
        switch a {
        case "RAISE", "BET": return Color(red: 0.25, green: 0.85, blue: 0.5)
        case "FOLD": return Color(red: 1, green: 0.36, blue: 0.36)
        default: return Color(red: 0.35, green: 0.65, blue: 1)
        }
    }

    private func load() async {
        loading = true
        error = nil
        do { items = try await store.api.prompts() }
        catch { self.error = error.localizedDescription }
        loading = false
    }
}
