import SwiftUI
import WebKit

/// 直接打开 zzpk.vip 网页版，注入假定位 + AI HUD。
struct WebGameView: UIViewRepresentable {
    @EnvironmentObject var store: AppStore

    func makeCoordinator() -> Coordinator { Coordinator(store: store) }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        let uc = WKUserContentController()
        uc.add(WeakScriptMessageHandler(context.coordinator), name: "ai")
        uc.addUserScript(WKUserScript(source: Self.fakeLocationJS,
                                      injectionTime: .atDocumentStart,
                                      forMainFrameOnly: false))
        uc.addUserScript(WKUserScript(source: Self.injectedJS,
                                      injectionTime: .atDocumentEnd,
                                      forMainFrameOnly: false))
        cfg.userContentController = uc
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.navigationDelegate = context.coordinator
        wv.uiDelegate = context.coordinator
        wv.scrollView.contentInsetAdjustmentBehavior = .never
        wv.load(URLRequest(url: URL(string: "https://zzpk.vip/?lang=zh-Hans")!))
        context.coordinator.webView = wv
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.store = store
    }

    /// 假定位：把 navigator.geolocation 换成固定坐标（吉隆坡）。
    static let fakeLocationJS = """
    (function(){
      if (window.__zzFakeGeo) return;
      window.__zzFakeGeo = true;
      var LAT = 3.1390, LNG = 101.6869;
      function makePos(){
        return { coords: { latitude: LAT, longitude: LNG, accuracy: 20,
                           altitude: null, altitudeAccuracy: null, heading: null, speed: null },
                 timestamp: Date.now() };
      }
      var geo = {
        getCurrentPosition: function(ok, err, opt){ setTimeout(function(){ ok && ok(makePos()); }, 30); },
        watchPosition: function(ok, err, opt){ setTimeout(function(){ ok && ok(makePos()); }, 30); return 1; },
        clearWatch: function(){}
      };
      try { Object.defineProperty(navigator, 'geolocation', { value: geo, configurable: true }); }
      catch(e) { navigator.geolocation.getCurrentPosition = geo.getCurrentPosition; }
      if (navigator.permissions && navigator.permissions.query) {
        var q = navigator.permissions.query.bind(navigator.permissions);
        navigator.permissions.query = function(d){
          if (d && d.name === 'geolocation') {
            return Promise.resolve({ state: 'granted', onchange: null,
              addEventListener: function(){}, removeEventListener: function(){} });
          }
          return q(d);
        };
      }
    })();
    """

    static let injectedJS = """
    (function(){
      if (window.__zzAiInstalled) return;
      window.__zzAiInstalled = true;
      window.__snap = null;

      const origFetch = window.fetch;
      window.fetch = function(){
        const args = arguments;
        return origFetch.apply(this, args).then(function(r){
          try {
            const u = String((args[0] && args[0].url) || args[0]);
            if (u.indexOf('/snapshot') >= 0) {
              r.clone().json().then(function(j){ window.__snap = j; poll(); }).catch(function(){});
            }
          } catch(e){}
          return r;
        });
      };

      const box = document.createElement('div');
      box.id = 'zz-ai-hud';
      box.style.cssText = 'position:fixed;top:calc(env(safe-area-inset-top,0px) + 6px);left:8px;right:8px;z-index:2147483647;'
        + 'background:rgba(8,12,18,.92);border:1px solid rgba(88,166,255,.55);border-radius:12px;'
        + 'padding:6px 10px;color:#e9eef6;font:12.5px/1.45 -apple-system,PingFang SC,sans-serif;'
        + 'box-shadow:0 8px 24px rgba(0,0,0,.5);display:none;max-height:62px;overflow:hidden;'
        + 'transition:max-height .18s ease';
      box.innerHTML = '<div style="color:#58a6ff;font-weight:700;font-size:11px;margin-bottom:2px">'
        + 'AI 助手 · 点我展开/收起</div>'
        + '<div id="zz-ai-act" style="white-space:pre-wrap;max-height:40px;overflow:hidden">等待牌局…</div>';
      let expanded = false;
      box.addEventListener('click', function(){
        expanded = !expanded;
        box.style.maxHeight = expanded ? '300px' : '62px';
        const a = document.getElementById('zz-ai-act');
        if (a) a.style.maxHeight = expanded ? '260px' : '40px';
      });
      const mount = function(){ if (document.body && !document.getElementById('zz-ai-hud')) document.body.appendChild(box); };
      setInterval(mount, 800);
      mount();

      let lastSig = '';
      window.zzAiUpdate = function(text){
        const el = document.getElementById('zz-ai-act');
        if (el) el.textContent = text;
        box.style.display = 'block';
      };
      window.zzAiHide = function(){ box.style.display = 'none'; };

      function poll(){
        const s = window.__snap;
        if (!s) { return; }
        const me = (s.viewer && s.viewer.seat != null)
          ? (s.seats || []).find(function(x){ return x.seat === s.viewer.seat; })
          : null;
        const sig = [s.hand_id, s.street, s.to_call, s.pot, (s.board||[]).join(''),
                     me ? (me.cards||[]).join('') : ''].join('|');
        if (sig === lastSig) return;
        lastSig = sig;
        const payload = {
          hand: String(s.hand_id || '').slice(0, 8),
          street: s.street || '',
          pot: s.pot || 0,
          to_call: s.to_call || 0,
          board: (s.board || []).join(' '),
          hole: me ? (me.cards || []).join(' ') : '',
          stack: me ? me.stack : 0,
          legal: (s.legal_actions || []).join('/'),
          myturn: !!(me && s.next_actor === me.player_id),
          rule: s.rule || (s.ante ? 'short' : 'long')
        };
        try { window.webkit.messageHandlers.ai.postMessage(payload); } catch(e){}
      }
      setInterval(poll, 900);
    })();
    """
}

final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(uc, didReceive: message)
    }
}

extension WebGameView {
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
        var store: AppStore
        weak var webView: WKWebView?
        private var lastKey = ""
        private var inFlight = false

        init(store: AppStore) { self.store = store }

        func webView(_ webView: WKWebView,
                     requestGeolocationPermissionFor origin: WKSecurityOrigin,
                     initiatedByFrame frame: WKFrameInfo,
                     decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            decisionHandler(.grant)
        }

        func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let dict = message.body as? [String: Any] else { return }
            Task { @MainActor in await handle(dict) }
        }

        @MainActor
        func handle(_ d: [String: Any]) async {
            let hole = d["hole"] as? String ?? ""
            let board = d["board"] as? String ?? ""
            let myturn = d["myturn"] as? Bool ?? false
            let pot = d["pot"] as? Int ?? 0
            let toCall = d["to_call"] as? Int ?? 0
            let stack = d["stack"] as? Int ?? 0
            let hand = d["hand"] as? String ?? ""
            let street = d["street"] as? String ?? ""
            let rule = d["rule"] as? String ?? "long"

            guard myturn else {
                await js("window.zzAiUpdate('轮到对手 / 等待行动')")
                return
            }
            guard !hole.isEmpty else {
                await js("window.zzAiUpdate('先入座再开助手（现在看不到你的牌）')")
                return
            }

            let key = "\(hand)|\(street)|\(pot)|\(toCall)"
            if key == lastKey || inFlight { return }
            lastKey = key
            inFlight = true
            defer { inFlight = false }

            let mode = (rule == "short") ? "short" : store.mode
            let raw = "\(mode == "short" ? "S6" : "L6") 网页牌桌 \(hole) | \(board) | P:\(pot) C:\(toCall) | H:\(stack) | 他行动完轮到我"
            await js("window.zzAiUpdate('分析中…')")
            do {
                let decision = try await store.api.decide(mode: mode, raw: raw)
                store.applyWeb(decision)
                let text = "\(decision.action ?? "")\n\(decision.size)\n\(decision.reason)"
                await js("window.zzAiUpdate(\(jsString(text)))")
            } catch {
                await js("window.zzAiUpdate(\(jsString("出错：\(error.localizedDescription)")))")
            }
        }

        @MainActor
        private func js(_ code: String) async {
            _ = try? await webView?.evaluateJavaScript(code)
        }

        private func jsString(_ s: String) -> String {
            let data = try? JSONSerialization.data(withJSONObject: [s])
            let arr = String(data: data ?? Data(), encoding: .utf8) ?? "[\"\"]"
            return String(arr.dropFirst().dropLast())
        }
    }
}
