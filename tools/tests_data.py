import sys, json
sys.path.insert(0, "/srv/poker")
import app

PASS = 0
FAIL = []


def ok(name, cond, detail=""):
    global PASS
    if cond:
        PASS += 1
    else:
        FAIL.append(name + " " + str(detail))


def state(**kw):
    d = dict(mode="long", raw="L6 网页牌桌", hole="Ah Kh", board="", pot=0,
             to_call=0, stack=1000, button=0, opponents=[], room="r1", hand_id="h1")
    d.update(kw)
    return app.StateIn(**d)


# 1) 牌力判定
ok("category 高牌", app.hand_category("Kh 5s", "9d Js Ad Qh 2c") == "高牌")
ok("category 同花", app.hand_category("Th 9h", "9h 3h Jh 2h") == "同花")
ok("category 葫芦", app.hand_category("5s Js", "9s 5d 6s Jd Jc").startswith("葫芦"))
ok("category 两对", app.hand_category("Th Td", "4h Qc 6s 5d 4s") == "两对(T,4)")

# 2) 听牌判定
ok("4 张同花=听花", app.draw_info("5s Js", "9s 5d 6s").startswith("系统判定：你有同花听牌"))
ok("3 张同花≠听花", app.draw_info("Ts 9s", "Qd Ah Tc Js") == "")

# 3) 牌面纹理
ok("干燥面", "干燥" in app.board_texture("Qh7c2h"))
ok("湿润面", ("湿润" in app.board_texture("9hThJh")) or ("中等" in app.board_texture("9hThJh")))

# 4) 输出清洗
t, a = app.sanitize_reply("【动作】CALL\n【尺寸】到 2.0\n【理由】x", "P:10 C:0.2")
ok("CALL 尺寸强制", a == "CALL" and "0.20" in t, t)
t, a = app.sanitize_reply("【动作】CHECK\n【尺寸】—", "P:10 C:2")
ok("有注 CHECK→CALL", a == "CALL")
t, a = app.sanitize_reply("【动作】RAISE\n【尺寸】到 110\n【理由】x", "P:4 C:2 H:500 最小加注到:0.4")
ok("加注上限 2.5x 底池", "10.00" in t, t)
t, a = app.sanitize_reply("【动作】RAISE\n【尺寸】到 30.00\n【理由】x", "P:8 C:2 H:97 最小加注到:0.4")
ok("缺单位按 10 换算", "3.00" in t, t)

# 5) 数据不变量
ok("正常状态无告警", app.validate_state(state(opponents=[{"contrib": 10}, {"contrib": 20}], pot=30)) == [])
ok("短牌带 5 报警", any("短牌" in x for x in app.validate_state(state(mode="short", hole="5s Js"))))
ok("底牌数量错报警", any("底牌" in x for x in app.validate_state(state(hole="Ah"))))
ok("负筹码报警", any("筹码为负" in x for x in app.validate_state(state(stack=-5))))
ok("底池与投入差报警", any("底池" in x for x in app.validate_state(
    state(opponents=[{"contrib": 10}], pot=1000))))

print("PASS", PASS, "FAIL", len(FAIL))
for f in FAIL:
    print(" -", f)
sys.exit(1 if FAIL else 0)
