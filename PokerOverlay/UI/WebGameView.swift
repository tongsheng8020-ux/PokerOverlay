import SwiftUI
import WebKit
import CoreLocation


struct WebGameView: View {
    @EnvironmentObject var store: AppStore
    /// 原生条默认关闭；JS HUD 失效时改成 true 兜底
    private let showNativeHUD = false

    var body: some View {
        ZStack(alignment: .top) {
            WebGameViewRep()
                .ignoresSafeArea(edges: .top)
            if showNativeHUD, let d = store.decision {
                NativeHUD(decision: d)
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
            }
        }
    }
}

struct NativeHUD: View {
    let decision: Decision
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text("提示")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color(red: 0.35, green: 0.65, blue: 1))
                Text(decision.action ?? "—")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(color)
                Text(decision.size)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.orange)
                Spacer()
                Text(expanded ? "收" : "展")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.3), lineWidth: 0.5))
            }
            if expanded {
                Text(decision.reason)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(red: 0.03, green: 0.05, blue: 0.08).opacity(0.92), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(red: 0.35, green: 0.65, blue: 1).opacity(0.45), lineWidth: 0.5))
        .onTapGesture { expanded.toggle() }
    }

    private var color: Color {
        switch (decision.action ?? "").uppercased() {
        case "RAISE", "BET": return Color(red: 0.25, green: 0.85, blue: 0.5)
        case "FOLD": return Color(red: 1, green: 0.36, blue: 0.36)
        default: return Color(red: 0.35, green: 0.65, blue: 1)
        }
    }
}

/// 打开 zzpk.vip 网页版，注入假定位 + 轻量 HUD（不覆盖 fetch，靠 seat token 轮询）。
struct WebGameViewRep: UIViewRepresentable {
    @EnvironmentObject var store: AppStore

    func makeCoordinator() -> Coordinator { Coordinator(store: store) }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        let uc = WKUserContentController()
        uc.add(WeakScriptMessageHandler(context.coordinator), name: context.coordinator.aiName)
        uc.add(WeakScriptMessageHandler(context.coordinator), name: context.coordinator.logName)
        let hudJS = Self.prepareJS(ai: context.coordinator.aiName, log: context.coordinator.logName)
        uc.addUserScript(WKUserScript(source: hudJS,
                                      injectionTime: .atDocumentEnd,
                                      forMainFrameOnly: false))
        cfg.userContentController = uc
        let wv = WKWebView(frame: .zero, configuration: cfg)
        let osv = UIDevice.current.systemVersion.replacingOccurrences(of: ".", with: "_")
        let major = UIDevice.current.systemVersion.split(separator: ".").first.map(String.init) ?? "17"
        wv.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS \(osv) like Mac OS X) "
            + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(major).0 Mobile/15E148 Safari/604.1"
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

    static let locMgr = CLLocationManager()

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

    static let hudWorld = WKContentWorld.world(name: "hud")

    static func prepareJS(ai: String, log: String) -> String {
        var js = injectedJS
        js = js.replacingOccurrences(of: "messageHandlers.ai", with: "messageHandlers.\(ai)")
        js = js.replacingOccurrences(of: "messageHandlers.log", with: "messageHandlers.\(log)")
        let suffix = String(ai.suffix(5))
        js = js.replacingOccurrences(of: "p-hud", with: "p-hud-\(suffix)")
        js = js.replacingOccurrences(of: "p-pill", with: "p-pill-\(suffix)")
        return js
    }

    static func injectHUD(into webView: WKWebView, ai: String, log: String) {
        DebugLog.shared.add("[JS] reinject start")
        let js = prepareJS(ai: ai, log: log)
        webView.evaluateJavaScript("window.__h=false; window.__s=null;", in: nil, in: WKContentWorld.page) { _ in
            let wrapped = """
            (function(){
              try {
            \(js)
              } catch(e) {
                try { window.webkit.messageHandlers.\(log).postMessage('jsfatal ' + (e && e.message) + ' | ' + (e && e.stack)); } catch(_) {}
              }
            })();
            """
            webView.evaluateJavaScript(wrapped, in: nil, in: WKContentWorld.page) { result in
                if case .failure(let err) = result {
                    DebugLog.shared.add("[JS] inject err \(err.localizedDescription)")
                    webView.evaluateJavaScript(js, in: nil, in: WKContentWorld.page) { r2 in
                        if case .failure(let e2) = r2 {
                            DebugLog.shared.add("[JS] page fallback err \(e2.localizedDescription)")
                        } else {
                            DebugLog.shared.add("[JS] page fallback ok")
                        }
                    }
                } else {
                    DebugLog.shared.add("[JS] inject ok")
                    let suffix = String(ai.suffix(5))
                    let check = "(function(){var x=document.getElementById('p-hud-\(suffix)'); return x ? x.style.display : 'missing';})()"
                    webView.evaluateJavaScript(check, in: nil, in: WKContentWorld.page) { r in
                        DebugLog.shared.add("[JS] hud check \(String(describing: try? r.get()))")
                    }
                }
            }
        }
    }

    static let injectedJS = """
    (function(){
      if (window.__h) return;
      window.__h = true;
      window.__s = null;
      window.__log = function(m){
        try { window.webkit.messageHandlers.log.postMessage(String(m)); } catch(e){}
      };
      window.log = window.__log;
      function log(m){ try { window.__log(m); } catch(e){} }
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
      window.__hist = [];
      window.__acts = [];
      window.__handId = null;
      window.__prevSnap = null;

      function streetName(x){
        return ({pre:'翻前', flop:'翻牌', turn:'转牌', river:'河牌'})[x] || x || '';
      }
      function track(s){
          if (!window.__seatLogged && (s.seats || []).length) {
            window.__seatLogged = true;
            const x = s.seats[0] || {};
            log('seatKeys ' + JSON.stringify(Object.keys(x)) + ' nameFields ' +
                JSON.stringify({name: x.name, nick: x.nick, nickname: x.nickname,
                                display_name: x.display_name, player_name: x.player_name}));
          }
        const p = window.__prevSnap;
        window.__prevSnap = s;
        if (!p) return;
        const h = window.__hist;
        if (s.hand_id !== window.__handId) { window.__handId = s.hand_id; window.__acts = []; window.__hist = []; }
        if (s.street !== p.street && s.street) h.push('到' + streetName(s.street));
        const prev = {};
        (p.seats || []).forEach(function(x){ prev[x.seat] = x; });
        (s.seats || []).forEach(function(x){
          const q = prev[x.seat];
          if (!q) return;
          if (!q.folded && x.folded) {
            h.push('座' + x.seat + '弃牌');
            window.__acts.push({ id: x.player_id, street: s.street || '', kind: 'fold', amount: 0 });
          }
          const dc = (x.total_contribution || 0) - (q.total_contribution || 0);
          if (dc > 0) {
            h.push('座' + x.seat + '投入+' + dc);
            const need = s.to_call || 0;
            let kind = 'bet';
            if (dc <= need + 1) kind = 'call';
            if (x.all_in && !q.all_in) kind = 'allin';
            window.__acts.push({ id: x.player_id, street: s.street || '', kind: kind, amount: dc });
          } else if (!q.acted && x.acted && !x.folded) {
            window.__acts.push({ id: x.player_id, street: s.street || '', kind: 'check', amount: 0 });
          }
          if (!q.all_in && x.all_in) h.push('座' + x.seat + '全下');
        });
        while (h.length > 10) h.shift();
      }

      function poll(){
        const s = window.__s;
        if (!s) return;
        track(s);
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
            mySeat: me ? me.seat : -1,
            account: me ? me.player_id : '',
            accountName: (function(){try{var a=JSON.parse(localStorage.getItem('zzpk.acct')||'{}');return a.username||a.name||a.account||a.nickname||'';}catch(e){return '';}})(),
            button: s.button_seat != null ? s.button_seat : -1,
            capacity: s.seats_capacity || 0,
            currentBet: s.current_bet || 0,
            minRaise: s.min_raise_to || 0,
            active: (s.seats || []).filter(function(x){ return !x.folded; }).length,
            history: window.__hist.join('；'),
            actions: window.__acts.slice(-40),
            opponents: (s.seats || []).map(function(x){
              return { id: x.player_id, name: x.name || x.nickname || x.display_name || x.player_name || '', folded: !!x.folded, contrib: x.total_contribution || 0, allin: !!x.all_in };
            }),
            seats: (s.seats || []).map(function(x){
              return { seat: x.seat, stack: x.stack, folded: !!x.folded,
                       allin: !!x.all_in, contrib: x.total_contribution || 0,
                       shown: x.hand_shown ? (x.hole || []) : [] };
            }),
            street: s.street || '', pot: s.pot || 0, to_call: s.to_call || 0,
            board: (s.board || []).join(' '),
            hole: me ? (me.hole || []).join(' ') : '',
            stack: me ? me.stack : 0,
            unit: s.chip_unit || 1,
            legal: (s.legal_actions || []).map(function(a){
              if (!a) return '';
              if (typeof a === 'string') return a;
              return a.kind || a.action || a.type || JSON.stringify(a);
            }).filter(Boolean).join('/'),
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
      (function jitter(){ setTimeout(function(){ pull(); jitter(); }, 1300 + Math.floor(Math.random()*500)); })();
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

extension WebGameViewRep {
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
        var store: AppStore
        weak var webView: WKWebView?
        let aiName = "m" + String(UUID().uuidString.prefix(6)).lowercased()
        let logName = "s" + String(UUID().uuidString.prefix(6)).lowercased()
        private var lastKey = ""
        private var lastRoom = ""
        private var lastMyTurn = false
        private var inFlight = false

        init(store: AppStore) {
            self.store = store
            super.init()
            NotificationCenter.default.addObserver(
                forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                DebugLog.shared.add("[APP] foreground, re-inject HUD")
                if let wv = self.webView { WebGameViewRep.injectHUD(into: wv, ai: aiName, log: logName) }
            }
        }

        private var locRequested = false
        private var hudReinjected = false

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DebugLog.shared.add("[JS] page finished")
            if !hudReinjected {
                hudReinjected = true
                WebGameViewRep.injectHUD(into: webView, ai: aiName, log: logName)
            }
            if !locRequested {
                locRequested = true
                switch WebGameViewRep.locMgr.authorizationStatus {
                case .denied, .restricted:
                    webView.evaluateJavaScript(WebGameViewRep.fakeLocationJS, in: nil, in: WKContentWorld.page) { _ in
                        DebugLog.shared.add("[GEO] denied, fallback coords injected")
                    }
                default:
                    WebGameViewRep.locMgr.requestWhenInUseAuthorization()
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DebugLog.shared.add("[JS] nav fail \(error.localizedDescription)")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DebugLog.shared.add("[JS] nav provisional fail \(error.localizedDescription)")
        }

        func webView(_ webView: WKWebView,
                     requestGeolocationPermissionFor origin: WKSecurityOrigin,
                     initiatedByFrame frame: WKFrameInfo,
                     decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            decisionHandler(.grant)
        }

        func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == logName {
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
            let mySeat = d["mySeat"] as? Int ?? -1
            let account = d["account"] as? String ?? ""
            let accountName = d["accountName"] as? String ?? ""

            if myturn {
                DebugLog.shared.add("[AI] state hand=\(hand) street=\(street) hole=\(hole) board=\(board) pot=\(pot) call=\(toCall)")
            }
            guard myturn else {
                if lastMyTurn {
                    lastMyTurn = false
                    DebugLog.shared.add("[WAIT] 非我行动")
                }
                await js("window.zzAiUpdate('等待行动')")
                return
            }
            if !lastMyTurn {
                lastMyTurn = true
                DebugLog.shared.add("[TURN] 轮到我 seat=\(mySeat) hole=\(hole)")
            }
            guard !hole.isEmpty else {
                DebugLog.shared.add("[SKIP] 轮到我但没读到牌 seat=\(mySeat)")
                await js("window.zzAiUpdate('入座后才有牌')")
                return
            }

            let legal = d["legal"] as? String ?? ""
            let activePlayers = d["active"] as? Int ?? 0
            let history = d["history"] as? String ?? ""
            let opponents = (d["opponents"] as? [[String: Any]]) ?? []
            let actions = (d["actions"] as? [[String: Any]]) ?? []
            let pids = opponents.compactMap { $0["id"] as? String }
            if !pids.isEmpty { store.currentPlayerIds = pids }
            let button = d["button"] as? Int ?? -1
            let curBet = d["currentBet"] as? Int ?? 0
            let minRaise = d["minRaise"] as? Int ?? 0
            var oppParts: [String] = []
            if let seats = d["seats"] as? [[String: Any]] {
                for x in seats {
                    let seat = x["seat"] as? Int ?? -1
                    if seat == mySeat { continue }
                    let stk = x["stack"] as? Int ?? 0
                    let folded = (x["folded"] as? Bool ?? false) ? "弃" : "在"
                    let allin = (x["allin"] as? Bool ?? false) ? "全下" : ""
                    let contrib = x["contrib"] as? Int ?? 0
                    let shown = (x["shown"] as? [String]) ?? []
                    var part = "座\(seat) \(folded)\(allin) 筹码\(stk) 投\(contrib)"
                    if !shown.isEmpty { part += " 亮牌\(shown.joined(separator: ""))" }
                    oppParts.append(part)
                    if oppParts.count >= 8 { break }
                }
            }
            let oppText = oppParts.isEmpty ? "无" : oppParts.joined(separator: "；")
            let unit = max(1, d["unit"] as? Int ?? 1)
            let u = Double(unit)
            func dsp(_ v: Int) -> String {
                let x = Double(v) / u
                return x == x.rounded() ? String(Int(x)) : String(format: "%.2f", x)
            }
            let key = "\(hand)|\(street)|\(pot)|\(toCall)"
            if key == lastKey || inFlight {
                DebugLog.shared.add("[SKIP] 去重/在途 key=\(key) inflight=\(inFlight)")
                return
            }
            DebugLog.shared.add("[DECIDE] hand=\(hand) street=\(street) hole=\(hole) board=\(board) pot=\(pot) call=\(toCall) stack=\(stack)")
            lastKey = key
            inFlight = true
            defer { inFlight = false }

            let mode = store.mode
            let raw = "\(mode == "short" ? "S6" : "L6") 网页牌桌 \(hole) | \(board) | P:\(dsp(pot)) C:\(dsp(toCall)) | H:\(dsp(stack)) | 活跃:\(activePlayers)人 | 按钮位:\(button) | 对手:\(oppText)\(history.isEmpty ? "" : " | 行动:\(history)") | 当前注:\(dsp(curBet)) 最小加注到:\(dsp(minRaise)) | 计数单位:1 = \(unit) 筹码 | 合法动作:\(legal) | 注意：C>0 时不能 CHECK，只能 CALL/RAISE/FOLD；C=0 时不能 CALL | 所有尺寸都用上面这个显示单位 | 他行动完轮到我"
            await js("window.zzAiUpdate('分析中…')")
            do {
                DebugLog.shared.add("[AI] request mode=\(mode) raw=\(raw)")
                let decision = try await store.api.decide(
                    mode: mode, raw: raw,
                    extra: ["hand_id": hand, "street": street, "opponents": opponents,
                            "actions": actions, "hole": hole, "board": board,
                            "pot": pot, "to_call": toCall, "account": account, "account_name": accountName, "stack": stack]
                )
                DebugLog.shared.add("[AI] reply \(decision.action ?? "-") \(decision.latency)ms")
                var act = (decision.action ?? "").uppercased()
                if toCall > 0 && (act == "CHECK" || act.isEmpty) {
                    act = "CALL"
                    DebugLog.shared.add("[FIX] illegal CHECK -> CALL (to_call=\(toCall))")
                }
                if toCall > 0 && act == "BET" {
                    act = "RAISE"
                    DebugLog.shared.add("[FIX] BET -> RAISE (to_call=\(toCall))")
                }
                if toCall == 0 && act == "CALL" {
                    act = "CHECK"
                    DebugLog.shared.add("[FIX] illegal CALL -> CHECK (to_call=0)")
                }
                var sizeText = decision.size
                if act == "CALL" {
                    sizeText = dsp(toCall)
                } else if act == "CHECK" || act == "FOLD" {
                    sizeText = "—"
                } else if let n = num(decision.size) {
                    let lo = max(Double(toCall) / u, Double(minRaise) / u)
                    let hi = Double(stack) / u
                    var v = n
                    if v < lo && lo > 0 {
                        v = lo
                        DebugLog.shared.add("[FIX] raise size \(n) -> \(v) (min)")
                    }
                    if v > hi && hi > 0 {
                        v = hi
                        DebugLog.shared.add("[FIX] raise size \(n) -> allin \(v)")
                    }
                    sizeText = fmt(v)
                }
                var fixed = decision
                fixed.action = act
                fixed.text = "\(act)\n\(sizeText)\n\(decision.reason)"
                store.applyWeb(fixed)
                DebugLog.shared.add("[HUD] \(act) \(sizeText)")
                await js("window.zzAiUpdate(\(jsString(fixed.text)))")
            } catch {
                DebugLog.shared.add("[ERR] \(error.localizedDescription)")
                let low = error.localizedDescription.lowercased()
                if low.contains("expired") || low.contains("invalid key") || low.contains("card key") {
                    store.showPinGate = true
                    await js("window.zzAiUpdate('卡密已过期，请重新输入')")
                } else {
                    await js("window.zzAiUpdate(\(jsString("出错：\(error.localizedDescription)")))")
                }
            }
        }

        private func num(_ s: String) -> Double? {
            var t = ""
            for ch in s {
                if ch.isNumber || ch == "." {
                    t.append(ch)
                } else if !t.isEmpty {
                    break
                }
            }
            return Double(t)
        }

        private func fmt(_ v: Double) -> String {
            v == v.rounded() ? String(Int(v)) : String(format: "%.2f", v)
        }

        @MainActor
        private func js(_ code: String) async {
            webView?.evaluateJavaScript(code, in: nil, in: WKContentWorld.page) { _ in }
        }

        private func jsString(_ s: String) -> String {
            let data = try? JSONSerialization.data(withJSONObject: [s])
            let arr = String(data: data ?? Data(), encoding: .utf8) ?? "[\"\"]"
            return String(arr.dropFirst().dropLast())
        }
    }
}
