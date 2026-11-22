import SwiftUI
import UIKit

struct DebugView: View {
    @ObservedObject private var log = DebugLog.shared
    @State private var shareURL: URL?
    @State private var showShare = false

    var body: some View {
        NavigationStack {
            Group {
                if log.entries.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "doc.text.magnifyingglass").font(.largeTitle)
                        Text("暂无日志").foregroundStyle(.secondary)
                        Text("打一手牌，再回来看")
                            .font(.caption).foregroundStyle(.secondary)
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
                    Button {
                        exportTxt()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("清空") { log.clear() }
                }
            }
            .sheet(isPresented: $showShare) {
                if let shareURL {
                    ShareSheet(items: [shareURL])
                }
            }
        }
    }

    private func exportTxt() {
        let url = log.exportFile()
        shareURL = url
        showShare = url != nil
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
