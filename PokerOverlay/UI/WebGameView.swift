import SwiftUI
import WebKit

/// 直接打开 zzpk.vip 网页版，注入假定位 + AI HUD（可拖动/可收起/自己拉 snapshot）。
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

    /// 假定位：固定坐标（吉隆坡）。
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
      window.__roomId = null;

      /* 1. 抓页面自己的 snapshot（fetch + XHR） */
      const origFetch = window.fetch;
      window.fetch = function(){
        const args = arguments;
        const u = String((args[0] && args[0].url) || args[0] || '');
        const m = u.match(/\\/v1\\/rooms\\/([0-9a-f]+)\\/snapshot/);
        if (m) window.__roomId = m[1];
        return origFetch.apply(this, args).then(function(r){
          try {
            if (m) { r.clone().json().then(function(j){ window.__snap = j; poll(); }).catch(function(){}); }
          } catch(e){}
          return r;
        });
      };
      const origOpen = XMLHttpRequest.prototype.open;
      XMLHttpRequest.prototype.open = function(method, url){
        const u = String(url || '');
        const m = u.match(/\\/v1\\/rooms\\/([0-9a-f]+)\\/snapshot/);
        if (m) {
          window.__roomId = m[1];
          this.addEventListener('load', function(){
            try { window.__snap = JSON.parse(this.responseText); poll(); } catch(e){}
          });
        }
        return origOpen.apply(this, arguments);
      };

      /* 2. 自己定时拉 snapshot */
      function token(){
        try { return JSON.parse(localStorage.getItem('zzpk.acct')).token; } catch(e){ return null; }
      }
      function findRoomFromPerf(){
        try {
          const names = performance.getEntriesByType('resource').map(function(e){ return e.name; });
          for (let i = names.length - 1; i >= 0; i--) {
            const m = names[i].match(/\\/v1\\/rooms\\/([0-9a-f]+)\\//);
            if (m) return m[1];
          }
        } catch(e){}
        return null;
      }
      async function pull(){
        if (!window.__roomId) window.__roomId = findRoomFromPerf();
        const rid = window.__roomId, tk = token();
        if (!rid || !tk) return;
        try {
          const r = await origFetch('/v1/rooms/' + rid + '/snapshot', {
            headers: { 'Authorization': 'Bearer ' + tk, 'X-Account-Session': tk }
          });
          if (r.ok) { window.__snap = await r.json(); poll(); }
        } catch(e){}
      }
      setInterval(pull, 1200);

      /* 3. HUD */
      const box = document.createElement('div');
      box.id = 'zz-ai-hud';
      box.style.cssText = 'position:fixed;top:calc(env(safe-area-inset-top,0px) + 6px);left:8px;right:8px;'
        + 'z-index:2147483647;background:rgba(8,12,18,.93);border:1px solid rgba(88,166,255,.55);'
        + 'border-radius:12px;padding:6px 10px;color:#e9eef6;'
        + 'font:12.5px/1.45 -apple-system,PingFang SC,sans-serif;'
        + 'box-shadow:0 8px 24px rgba(0,0,0,.5);display:none;max-height:64px;overflow:hidden;'
        + 'transition:max-height .18s ease;touch-action:none;user-select:none;';
      box.innerHTML = '<div style="display:flex;align-items:center;gap:8px">'
        + '<span style="color:#58a6ff;font-weight:700;font-size:11px;flex:1">AI 助手 · 可拖动 / 点我展开</span>'
        + '<span id="zz-ai-x" style="padding:0 8px;border:1px solid rgba(255,255,255,.25);'
        + 'border-radius:999px;font-size:11px;line-height:20px">收</span></div>'
        + '<div id="zz-ai-act" style="white-space:pre-wrap;max-height:44px;overflow:hidden;margin-top:2px">'
        + '等待牌局…</div>'
        + '<div id="zz-ai-dbg" style="color:#5b6b80;font-size:10px;margin-top:2px"></div>';

      let expanded = false;
      function stop(e){ e.stopPropagation(); e.preventDefault(); }
      ['touchstart','touchend','touchmove','pointerdown','pointerup','click'].forEach(function(t){
        box.addEventListener(t, stop, true);
      });
      box.addEventListener('click', function(){
        expanded = !expanded;
        box.style.maxHeight = expanded ? '300px' : '64px';
        const a = document.getElementById('zz-ai-act');
        if (a) a.style.maxHeight = expanded ? '240px' : '44px';
      });
      const closeBtn = box.querySelector('#zz-ai-x');
      closeBtn.addEventListener('click', function(){ box.style.display = 'none'; window.__zzHidden = true; });
      closeBtn.addEventListener('touchstart', function(){ box.style.display = 'none'; window.__zzHidden = true; });

      let drag = null;
      box.addEventListener('touchstart', function(e){
        const t = e.touches[0];
        drag = { x: t.clientX, y: t.clientY, top: box.offsetTop, left: box.offsetLeft };
      }, true);
      box.addEventListener('touchmove', function(e){
        if (!drag) return;
        const t = e.touches[0];
        box.style.top = Math.max(0, drag.top + (t.clientY - drag.y)) + 'px';
        box.style.left = Math.max(0, drag.left + (t.clientX - drag.x)) + 'px';
        box.style.right = 'auto';
      }, true);
      box.addEventListener('touchend', function(){ drag = null; }, true);

      const mount = function(){
        if (document.body && !document.getElementById('zz-ai-hud') && !window.__zzHidden) {
          document.body.appendChild(box);
        }
      };
      setInterval(mount, 800);
      mount();

      window.zzAiUpdate = function(text){
        const el = document.getElementById('zz-ai-act');
        if (el) el.textContent = text;
        box.style.display = 'block';
      };
      window.zzAiHide = function(){ box.style.display = 'none'; };

      let lastSig = '';
      window.__zzMyTurn = false;
      window.__zzSeated = false;

      function poll(){
        const s = window.__snap;
        if (!s) return;
        const me = (s.viewer && s.viewer.seat != null)
          ? (s.seats || []).find(function(x){ return x.seat === s.viewer.seat; })
          : null;
        window.__zzSeated = !!me;
        window.__zzMyTurn = !!(me && s.next_actor === me.player_id);
        const dbg = document.getElementById('zz-ai-dbg');
        if (dbg) dbg.textContent = 'snap✓ 座位' + (me ? me.seat : '-') + ' 手牌' +
          (me && me.cards ? me.cards.length : 0) + ' 轮到我' + (window.__zzMyTurn ? '是' : '否');
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
          myturn: window.__zzMyTurn,
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
