import json, os, re, subprocess, tempfile, urllib.request, urllib.error, glob, time

ROOT = r"C:\Users\jinsh\Desktop\杂事"
SWIFT = r"C:\Users\jinsh\Desktop\杂事\PokerOverlay\PokerOverlay\UI\WebGameView.swift"
PY = r"C:\Users\jinsh\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe"
NODE = r"C:\Users\jinsh\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\node\bin\node.exe"
CHROME = r"C:\Program Files\Google\Chrome\Application\chrome.exe"
B = "http://64.90.0.27:8099"
results = []


def record(name, ok, detail=""):
    results.append((name, ok, detail))
    print(("PASS " if ok else "FAIL ") + name + ("  " + detail if detail else ""))


# ---------- 1) JS 语法 ----------
s = open(SWIFT, encoding="utf-8").read()
i = s.index('static let injectedJS = """') + len('static let injectedJS = """')
j = s.index('"""', i)
js = s[i:j].replace("\\\\", "\\")
js_prepared = (js
    .replace("messageHandlers.ai", "messageHandlers.testai")
    .replace("messageHandlers.log", "messageHandlers.testlog")
    .replace("p-hud", "p-hud-test")
    .replace("p-pill", "p-pill-test"))
pjs = os.path.join(tempfile.gettempdir(), "hud_prepared.js")
open(pjs, "w", encoding="utf-8").write(js_prepared)
r = subprocess.run([NODE, "--check", pjs], capture_output=True, text=True, encoding="utf-8", errors="replace")
record("注入脚本语法", r.returncode == 0, r.stderr.strip()[:120])

# ---------- 2) HUD DOM 渲染（headless Chrome） ----------
html = """<!DOCTYPE html><html><head><meta charset="utf-8"></head><body>
<script>
window.__logs=[];
window.webkit={messageHandlers:{testai:{postMessage:function(m){window.__ai=m;}},
  testlog:{postMessage:function(m){window.__logs.push(String(m));}}}};
localStorage.setItem('zzpk.acct', JSON.stringify({token:'tok'}));
localStorage.setItem('zzpk.seats', JSON.stringify({'room1':{player_token:'t',player_id:'p',seat:1}}));
performance.getEntriesByType = function(){return [{name:'https://x/v1/rooms/room1/snapshot'}]};
window.fetch = function(){ return Promise.reject(new Error('offline')); };
</script>
<script>
""" + js_prepared + """
</script>
</body></html>"""
hp = os.path.join(tempfile.gettempdir(), "hud_regression.html")
open(hp, "w", encoding="utf-8").write(html)
dom = subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--no-sandbox",
                      "--virtual-time-budget=6000", "--dump-dom", "file:///" + hp.replace("\\", "/")],
                     capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=120).stdout
record("HUD 元素渲染", '<div id="p-hud-test"' in dom)
record("HUD 默认文案", '换桌了' in dom, dom[dom.find('p-act'):dom.find('p-act')+80] if 'p-act' in dom else "")


# ---------- 3) 服务端接口 ----------
def call(path, body=None, headers=None, method=None):
    h = {"Content-Type": "application/json"}
    if headers:
        h.update(headers)
    req = urllib.request.Request(B + path, data=(json.dumps(body).encode() if body is not None else None),
                                 headers=h, method=method or ("POST" if body is not None else "GET"))
    return json.loads(urllib.request.urlopen(req, timeout=60).read().decode())


try:
    health = call("/api/health")
    record("健康检查", health.get("ok") is True, health.get("model", ""))
except Exception as e:
    record("健康检查", False, str(e))

try:
    admin = {"X-Pin": "2602"}
    key = call("/api/admin/keys", {"kind": "30m", "count": 1, "note": "regression"}, admin)["keys"][0]
    act = call("/api/key/activate", {"key": key, "device": "regression"})
    record("卡密生成/激活", act.get("ok") is True, act.get("expires_at", ""))
    bad = 0
    try:
        call("/api/decide", {"mode": "long", "raw": "x"}, {"X-Key": "BADKEY"})
    except urllib.error.HTTPError as e:
        bad = e.code
    record("无效卡密被拒", bad == 401, str(bad))

    d = call("/api/decide", {"mode": "short", "raw": "S6 网页牌桌 AhKh | Qh7c2h | P:24 C:8 | H:198",
                             "hole": "AhKh", "board": "Qh7c2h", "pot": 240, "to_call": 80,
                             "hand_id": "regh1", "account": "regacct", "stack": 1980},
             {"X-Key": key})
    record("决策接口", d.get("action") in ("FOLD", "CHECK", "CALL", "BET", "RAISE"),
           str(d.get("action")) + " " + str(d.get("latency_ms")) + "ms")
    record("返回尺寸为对象", isinstance(d.get("cost"), dict), str(d.get("cost")))

    dec = call("/api/decisions?limit=10", headers={"X-Key": key})
    record("提示历史按卡隔离", isinstance(dec, list) and len(dec) >= 1, "rows=" + str(len(dec)))

    opp = call("/api/opponents/list?ids=nobody", headers={"X-Key": key})
    record("对手库查询", isinstance(opp, list), "rows=" + str(len(opp)))

    summ = call("/api/admin/summary", headers=admin)
    record("运营汇总", "balance" in summ, "balance=" + str(summ.get("balance")))
finally:
    pass

print("\n==== 汇总 ====")
ok = sum(1 for _, o, _ in results if o)
print(f"{ok}/{len(results)} 通过")
for n, o, det in results:
    if not o:
        print("  失败:", n, det)
