import SwiftUI
import UIKit

struct DecisionCardView: View {
    @EnvironmentObject var store: AppStore
    let decision: Decision
    let mode: String

    private var actionColor: Color {
        switch decision.action {
        case "RAISE", "BET": return Color(red: 0.25, green: 0.85, blue: 0.5)
        case "FOLD": return Color(red: 1, green: 0.36, blue: 0.36)
        default: return Color(red: 0.35, green: 0.65, blue: 1)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(decision.action ?? "—")
                    .font(.system(size: 46, weight: .heavy, design: .rounded))
                    .foregroundStyle(actionColor)
                if !decision.size.isEmpty {
                    Text(decision.size)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Color(red: 1, green: 0.78, blue: 0.4))
                }
                Spacer()
            }

            if !decision.numbers.isEmpty {
                row("数字", decision.numbers)
            }
            if !decision.reason.isEmpty {
                row("理由", decision.reason)
            }
            if !decision.alternative.isEmpty {
                row("备选", decision.alternative)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(LinearGradient(colors: [Color(red: 0.35, green: 0.65, blue: 1),
                                                      Color(red: 0.25, green: 0.85, blue: 0.5)],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * CGFloat(min(100, max(0, decision.confidence))) / 100)
                }
            }
            .frame(height: 6)

            HStack {
                Text("置信度 \(decision.confidence)")
                Spacer()
                Text("\(decision.latency)ms · \(decision.model ?? "")")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button {
                    store.speak(decision.text.replacingOccurrences(of: "【", with: "，")
                        .replacingOccurrences(of: "】", with: "，"))
                } label: {
                    Label("朗读", systemImage: "speaker.wave.2.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    UIPasteboard.general.string = decision.text
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.regular)
        }
        .padding(14)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.07)))
    }

    private func row(_ key: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(key)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .leading)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(Color(white: 0.82))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
