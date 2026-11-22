import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        TabView {
            WebGameView()
                .tabItem { Label("牌桌", systemImage: "suit.club.fill") }

            DecideView()
                .tabItem { Label("决策", systemImage: "suit.spade.fill") }

            StatsView()
                .tabItem { Label("战绩", systemImage: "chart.line.uptrend.xyaxis") }

            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }

            DebugView()
                .tabItem { Label("日志", systemImage: "doc.text.magnifyingglass") }
        }
        .tint(Color(red: 0.35, green: 0.65, blue: 1))
        .sheet(isPresented: $store.showPinGate) {
            PinGateView()
                .interactiveDismissDisabled()
        }
    }
}

struct PinGateView: View {
    @EnvironmentObject var store: AppStore
    @State private var input = ""
    @State private var checking = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "suit.spade.fill")
                .font(.system(size: 52))
                .foregroundStyle(.linearGradient(colors: [.white, .gray], startPoint: .top, endPoint: .bottom))
            Text("输入访问密码")
                .font(.title2.bold())
            Text("第一次使用需要验证，之后自动记住")
                .font(.footnote)
                .foregroundStyle(.secondary)
            SecureField("密码", text: $input)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .multilineTextAlignment(.center)
                .keyboardType(.asciiCapable)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 40)
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            Button {
                Task { await submit() }
            } label: {
                if checking { ProgressView() } else { Text("进入").bold().frame(maxWidth: .infinity) }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 40)
            .disabled(input.isEmpty || checking)
        }
        .padding()
        .presentationDetents([.medium])
    }

    private func submit() async {
        checking = true
        store.pin = input
        do {
            _ = try await store.api.overview()
            store.showPinGate = false
            await store.refreshAll()
        } catch {
            store.pin = ""
            self.error = "密码不对或服务器连不上"
        }
        checking = false
    }
}
