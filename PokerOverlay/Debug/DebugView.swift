import SwiftUI

struct DebugView: View {
    @ObservedObject private var log = DebugLog.shared

    var body: some View {
        NavigationStack {
            Group {
                if log.entries.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "doc.text.magnifyingglass").font(.largeTitle)
                        Text("暂无日志").foregroundStyle(.secondary)
                    }
                } else {
                    List(log.entries, id: \.self) { line in
                        Text(line)
                            .font(.system(size: 10.5, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("调试日志")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: log.text) { Image(systemName: "square.and.arrow.up") }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("清空") { log.clear() }
                }
            }
        }
    }
}
