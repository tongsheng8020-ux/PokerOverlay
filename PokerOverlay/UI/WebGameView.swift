import SwiftUI
import WebKit

/// 打开 zzpk.vip 网页版，注入假定位 + 轻量 HUD（不覆盖 fetch，靠 seat token 轮询）。
struct WebGameView: UIViewRepresentable {
    @EnvironmentObject var store: AppStore

    func makeCoordinator() -> Coordinator { Coordinator(store: store) }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        let uc = WKUserContentController()
        uc.add(WeakScriptMessageHandler(context.coordinator), name: "ai")
        uc.add(WeakScriptMessageHandler(context.coordinator), name: "log")
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

    static let fakeLocationJS = """
    (function(){
      if (window.__g) return;
      window.__g = true;
      var LAT = 3.1390, LNG = 101.6869;
      function pos(){
        return { coords: { latitude: LAT, longitude: LNG, accuracy: 20,
                 altitude: null, altitudeAccuracy: null, heading: null, speed: null },
                 timestamp: Date.now() };
      }
      var g = {
        getCurrentPosition: function(ok){ setTimeout(function(){ ok && ok(pos()); }, 30); },
        watchPosition: function(ok){ setTimeout(function(){ ok && ok(pos()); }, 30); return 1; },
        clearWatch: function(){}
      };
      try { Object.defineProperty(navigator, 'geolocation', { value: g, configurable: true }); }
      catch(e) { navigator.geolocation.getCurrentPosition = g.getCurrentPosition; }
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
      if (window.__h) return;
      window.__h = true;
      window.__s = null;
      window.__log = function(m){
        try { window.webkit.messageHandlers.log.postMessage(String(m)); } catch(e){}
      };
      window.__log('js injected');
      window.__rid = null;

      function acctTok(){
        try { return JSON.parse(localStorage.getItem('zzpk.acct')).token; } catch(e){ return null; }
      }
      function seatTok(rid){
        try {
          const m = JSON.parse(localStorage.getItem('zzpk.seats') || '{}');
          const v = m[rid];
          if (!v) return null;
          if (typeof v === 'string') return v;
          return v.player_token || v.token || v.t || v.seatTok || null;
        } catch(e){ return null; }
      }
      function findRoom(){
        if (window.__rid) return window.__rid;
        try {
          const names = performance.getEntriesByType('resource').map(function(e){ return e.name; });
          for (let i = names.length - 1; i >= 0; i--) {
            const m = names[i].match(/\\/v1\\/rooms\\/([0-9a-f]+)\\//);
            if (m) { window.__rid = m[1]; return m[1]; }
          }
        } catch(e){}
        return null;
      }

      const box = document.createElement('div');
      box.id = 'p-hud';
      box.style.cssText = 'position:fixed;left:8px;right:8px;top:2px;z-index:2147483646;'
        + 'background:rgba(6,10,16,.90);border:1px solid rgba(88,166,255,.45);'
        + 'border-radius:10px;padding:4px 8px;color:#e9eef6;'
        + 'font:12px/1.35 -apple-system,PingFang SC,sans-serif;box-shadow:0 6px 18px rgba(0,0,0,.45);'
        + 'display:none;max-height:56px;overflow:hidden;touch-action:none;user-select:none;';
      box.innerHTML = '<div style="display:flex;gap:6px;align-items:center">'
        + '<span style="color:#58a6ff;font-weight:700;font-size:10px">提示</span>'
        + '<span id="p-act" style="flex:1;white-space:pre-wrap;max-height:34px;overflow:hidden"></span>'
        + '<span id="p-x" style="font-size:10px;border:1px solid rgba(255,255,255,.22);'
        + 'border-radius:99px;padding:0 6px;line-height:16px">收</span></div>'
        + '<div id="p-dbg" style="color:#5b6b80;font-size:9px"></div>';

      function stop(e){ e.stopPropagation(); }
      ['pointerdown','touchstart','touchmove'].forEach(function(t){ box.addEventListener(t, stop, true); });
      let big = false;
      box.addEventListener('click', function(){
        big = !big;
        box.style.maxHeight = big ? '320px' : '56px';
        const a = document.getElementById('p-act');
        if (a) a.style.maxHeight = big ? '260px' : '34px';
      });
      const pill = document.createElement('div');
      pill.id = 'p-pill';
      pill.style.cssText = 'position:fixed;left:8px;top:44px;z-index:2147483645;'
        + 'background:rgba(8,12,18,.92);border:1px solid rgba(88,166,255,.55);border-radius:999px;'
        + 'padding:4px 10px;color:#58a6ff;font:11px/1.2 -apple-system,PingFang SC,sans-serif;'
        + 'display:none;';
      pill.textContent = 'AI';
      const reopen = function(e){
        if (e) { e.stopPropagation(); }
        box.style.display = 'block';
        pill.style.display = 'none';
        window.__hidden = false;
      };
      pill.addEventListener('click', reopen);
      pill.addEventListener('touchstart', function(e){ e.stopPropagation(); }, true);
      pill.addEventListener('touchend', function(e){ e.stopPropagation(); reopen(e); }, true);

      const x = box.querySelector('#p-x');
      const close = function(e){
        if (e) { e.stopPropagation(); }
        box.style.display = 'none';
        pill.style.display = 'block';
        window.__hidden = true;
      };
      x.addEventListener('click', close);
      x.addEventListener('touchend', function(e){ e.stopPropagation(); close(e); }, true);

      let drag = null;
      box.addEventListener('touchstart', function(e){
        const t = e.touches[0]; drag = { x: t.clientX, y: t.clientY, top: box.offsetTop, left: box.offsetLeft };
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
        const root = document.documentElement || document.body;
        if (!root) return;
        if (!document.getElementById('p-pill')) root.appendChild(pill);
        if (!document.getElementById('p-hud') && !window.__hidden) root.appendChild(box);
      };
      let mountLogged = false;
      setInterval(function(){ mount(); if (mountLogged === false && document.getElementById('p-hud')) { mountLogged = true; window.__log('hud mounted'); } }, 800);
      mount();

      window.zzAiUpdate = function(text){
        const el = document.getElementById('p-act');
        if (el) el.textContent = text;
        box.style.display = 'block';
      };

      let lastSig = '';
      window.__my = false;

      function poll(){
        const s = window.__s;
        if (!s) return;
        const vobj = (s.viewer && typeof s.viewer === 'object') ? s.viewer : null;
        let vid = (typeof s.viewer === 'string' && s.viewer !== 'spectator') ? s.viewer : null;
        const map = seatsMap();
        let entry = window.__rid ? map[window.__rid] : null;
        if (!entry) { const ks = Object.keys(map); if (ks.length) entry = map[ks[ks.length - 1]]; }
        if (!vid && entry && entry.player_id) vid = entry.player_id;
        const fallbackSeat = (entry && entry.seat != null) ? entry.seat : null;
        const me = (s.seats || []).find(function(x){
          if (vobj && vobj.seat != null && x.seat === vobj.seat) return true;
          if (vid && x.player_id === vid) return true;
          if (fallbackSeat != null && x.seat === fallbackSeat) return true;
          return false;
        }) || null;
        window.__my = !!(me && s.next_actor === me.player_id);
        const seatNow = me ? me.seat : null;
        if (seatNow !== window.__lastSeat) {
          window.__lastSeat = seatNow;
          window.__log('seated=' + (seatNow == null ? '-' : seatNow) + ' hole=' + (me && me.hole ? me.hole.join('') : '-'));
        }
        if (window.__my !== window.__lastMy) {
          window.__lastMy = window.__my;
          if (window.__my) lastSig = '';
          window.__log('turn my=' + (window.__my ? 1 : 0) + ' seat=' + (me ? me.seat : '-') + ' hole=' + (me && me.hole ? me.hole.join('') : '-'));
        }
        const dbg = document.getElementById('p-dbg');
        if (dbg) dbg.textContent = 'v:' + (vobj ? ('seat' + vobj.seat) : String(s.viewer)) + ' 座' + (me ? me.seat : '-')
          + ' 牌' + (me && me.hole ? me.hole.length : 0) + ' 我' + (window.__my ? 1 : 0);
        const sig = [s.hand_id, s.street, s.to_call, s.pot, (s.board||[]).join(''),
                     me ? (me.hole||[]).join('') : ''].join('|');
        if (sig === lastSig) return;
        lastSig = sig;
        try {
          window.webkit.messageHandlers.ai.postMessage({
            room: String(window.__room || '').slice(0, 8),
            hand: String(s.hand_id || '').slice(0, 8),
            street: s.street || '', pot: s.pot || 0, to_call: s.to_call || 0,
            board: (s.board || []).join(' '),
            hole: me ? (me.hole || []).join(' ') : '',
            stack: me ? me.stack : 0,
            legal: (s.legal_actions || []).join('/'),
            myturn: window.__my,
            rule: s.rule || (s.ante ? 'short' : 'long')
          });
        } catch(e){}
      }

      function seatsMap(){
        try { return JSON.parse(localStorage.getItem('zzpk.seats') || '{}'); } catch(e){ return {}; }
      }
      async function pull(){
        const acct = acctTok();
        if (!acct) { window.__log('pull skip acct=0'); return; }
        const map = seatsMap();
        const keys = Object.keys(map);
        // 优先用“有座位凭证”的房间
        let rid = null, entry = null;
        if (keys.length) {
          rid = keys[keys.length - 1];
          entry = map[rid];
        }
        if (!rid) rid = findRoom();
        if (!rid) { window.__log('pull skip rid=null'); return; }
        if (rid !== window.__room) {
          window.__room = rid;
          window.__s = null;
          window.__lastSeat = null;
          window.__lastMy = null;
          lastSig = '';
          window.__log('room changed ' + String(rid).slice(0, 6));
          try { window.zzAiUpdate('换桌了，等待牌局…'); } catch(e){}
        }
        window.__rid = rid;
        const tk = (entry && entry.player_token) ? entry.player_token : acct;
        try {
          const h = { 'Authorization': 'Bearer ' + tk };
          if (acct) h['X-Account-Session'] = acct;
          const r = await fetch('/v1/rooms/' + rid + '/snapshot', { headers: h });
          if (!r.ok) { window.__log('snap http=' + r.status + ' room=' + rid.slice(0, 6) + ' seatTok=' + (entry ? 1 : 0)); return; }
          const j = await r.json();
          if (!j.viewer && window.__s && window.__s.viewer) j.viewer = window.__s.viewer;
          window.__s = j;
          window.__log('snap room=' + rid.slice(0, 6) + ' seatTok=' + (entry ? 1 : 0) + ' viewer=' + JSON.stringify(j.viewer) + ' seats=' + (j.seats ? j.seats.length : 0));
          poll();
        } catch(e){
          window.__log('pull err=' + String(e).slice(0, 40));
        }
      }
      setInterval(pull, 1500);
      setTimeout(pull, 600);
      window.__log('seatsStore=' + maskSeats());
      function maskSeats(){
        try {
          const m = JSON.parse(localStorage.getItem('zzpk.seats') || '{}');
          const out = {};
          Object.keys(m).forEach(function(k){
            const v = m[k] || {};
            out[k.slice(0, 6)] = { player_id: String(v.player_id || '').slice(0, 6), token: String(v.player_token || '').slice(0, 6), seat: v.seat };
          });
          return JSON.stringify(out);
        } catch(e){ return 'err'; }
      }
      setInterval(function(){
        window.__log('seatsStore=' + maskSeats());
      }, 8000);
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
        private var lastRoom = ""
        private var inFlight = false

        init(store: AppStore) { self.store = store }

        func webView(_ webView: WKWebView,
                     requestGeolocationPermissionFor origin: WKSecurityOrigin,
                     initiatedByFrame frame: WKFrameInfo,
                     decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            decisionHandler(.grant)
        }

        func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "log" {
                let text = String(describing: message.body)
                DispatchQueue.main.async { DebugLog.shared.add("[JS] \(text)") }
                return
            }
            guard let dict = message.body as? [String: Any] else { return }
            Task { @MainActor in await handle(dict) }
        }

        @MainActor
        func handle(_ d: [String: Any]) async {
            let room = d["room"] as? String ?? ""
            if room != lastRoom { lastRoom = room; lastKey = "" }
            let hole = d["hole"] as? String ?? ""
            let board = d["board"] as? String ?? ""
            let myturn = d["myturn"] as? Bool ?? false
            let pot = d["pot"] as? Int ?? 0
            let toCall = d["to_call"] as? Int ?? 0
            let stack = d["stack"] as? Int ?? 0
            let hand = d["hand"] as? String ?? ""
            let street = d["street"] as? String ?? ""
            _ = d["rule"] as? String ?? "long"

            if myturn {
                DebugLog.shared.add("[AI] state hand=\(hand) street=\(street) hole=\(hole) board=\(board) pot=\(pot) call=\(toCall)")
            }
            guard myturn else {
                await js("window.zzAiUpdate('等待行动')")
                return
            }
            guard !hole.isEmpty else {
                await js("window.zzAiUpdate('入座后才有牌')")
                return
            }

            let legal = d["legal"] as? String ?? ""
            let key = "\(hand)|\(street)|\(pot)|\(toCall)"
            if key == lastKey || inFlight { return }
            lastKey = key
            inFlight = true
            defer { inFlight = false }

            let mode = store.mode
            let raw = "\(mode == "short" ? "S6" : "L6") 网页牌桌 \(hole) | \(board) | P:\(pot) C:\(toCall) | H:\(stack) | 合法动作:\(legal) | 他行动完轮到我"
            await js("window.zzAiUpdate('分析中…')")
            do {
                DebugLog.shared.add("[AI] request mode=\(mode) raw=\(raw)")
                let decision = try await store.api.decide(mode: mode, raw: raw)
                DebugLog.shared.add("[AI] reply \(decision.action ?? "-") \(decision.latency)ms")
                DebugLog.shared.add("[HUD] \(decision.action ?? "-") \(decision.size)")
                var act = (decision.action ?? "").uppercased()
                if toCall > 0 && (act == "CHECK" || act.isEmpty) {
                    act = "CALL"
                    DebugLog.shared.add("[FIX] illegal CHECK -> CALL (to_call=\(toCall))")
                }
                if toCall == 0 && act == "CALL" {
                    act = "CHECK"
                    DebugLog.shared.add("[FIX] illegal CALL -> CHECK (to_call=0)")
                }
                store.applyWeb(decision)
                let text = "\(act)\n\(decision.size)\n\(decision.reason)"
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
