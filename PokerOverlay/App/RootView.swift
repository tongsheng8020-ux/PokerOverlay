import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        TabView {
            WebGameView()
                .tabItem { Label("牌桌", systemImage: "suit.club.fill") }

            PromptsView()
                .tabItem { Label("提示历史", systemImage: "clock.arrow.circlepath") }

            OpponentsView()
                .tabItem { Label("对手信息", systemImage: "person.2.fill") }

            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
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
            Text("输入卡密")
                .font(.title2.bold())
            Text("卡密有效期 24 小时 / 7 天，到期后不再提示")
                .font(.footnote)
                .foregroundStyle(.secondary)
            TextField("卡密", text: $input)
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
        let key = input.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        do {
            let info = try await store.api.activateKey(key)
            store.pin = key
            store.keyExpires = info.expires_at
            store.showPinGate = false
            self.error = nil
            await store.refreshAll()
        } catch {
            store.pin = ""
            self.error = "卡密无效或已过期"
        }
        checking = false
    }
}
