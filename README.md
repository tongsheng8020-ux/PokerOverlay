# PokerOverlay · iOS 独立 App（实时读屏 + 决策浮窗）

不是网页套壳，是一个真正的 iOS App：
**系统屏幕直播负责实时读屏 → 本机通道 → DeepSeek 出决策 → 画中画浮窗盖在游戏上。**

```
┌─────────────┐   控制中心「屏幕录制」   ┌──────────────────┐
│  Telegram   │ ───────────────────────▶ │ BroadcastExtension│
│  牌局界面    │                          │  Vision OCR 1 帧/秒│
└─────────────┘                          └────────┬─────────┘
       ▲                                          │ POST 127.0.0.1:8791
       │            画中画浮窗（系统级悬浮）         ▼
┌──────┴──────┐        ┌──────────────┐    ┌──────────────┐
│  决策卡片    │ ◀───── │  PokerOverlay │ ◀── │ LiveBridge   │
└─────────────┘        │  PiP 渲染     │    └──────────────┘
                       └──────┬───────┘
                              │ POST /api/vision
                              ▼
                   https://你的服务器（DeepSeek）
```

---

## 为什么是「画中画」不是「悬浮窗」

iOS 没有给第三方 App 开「在其他 App 上画东西」的权限。系统里唯一能常驻在别的 App 上方的能力就是 **画中画（PiP）**，所以决策窗用 PiP 呈现：它在游戏上面浮动、可以拖动、可以缩放，切换 App 不消失。

App 用 `AVSampleBufferDisplayLayer` 自己渲染画面喂给 PiP，所以显示的不是视频文件，而是实时生成的决策帧。

---

## 实时链路

| 环节 | 实现 | 耗时 |
|---|---|---|
| 读屏 | 屏幕直播扩展 `RPBroadcastSampleHandler`，1 秒取一帧 | 实时 |
| 文字 | Vision `VNRecognizeTextRequest`（中文+英文，精确模式） | ~150ms |
| 传回 | 扩展 POST 到 App 的本机监听 `127.0.0.1:8791` | <20ms |
| 决策 | App 调服务器 `/api/vision`（DeepSeek） | 1–2s |
| 显示 | PiP 帧刷新 | 即时 |

**你只在第一次点「开始直播」，之后全自动。**

---

## 安装到 iPhone

### 路线 A：有 Mac（最稳）

```bash
brew install xcodegen
cd PokerOverlay
xcodegen generate
open PokerOverlay.xcodeproj
```
Xcode 里选自己的 Apple ID → 选真机 → Run。
免费账号 7 天需要重签；付费开发者账号 1 年。

### 路线 B：没 Mac，用 GitHub Actions 出 ipa（Windows 也能干）

1. 把这个目录推到你的 GitHub 私有仓库（`.github/workflows/build-ipa.yml` 已带好）。
2. Actions → `build-ipa` → Run workflow → 等 3–5 分钟。
3. 下载 `PokerOverlay-unsigned.ipa`。
4. Windows 装 **Sideloadly**（或 AltStore / TrollStore），插上 iPhone，拖入 ipa，填 Apple ID，开始签名安装。
5. 手机上：设置 → 通用 → VPN与设备管理 → 信任你的证书；iOS 16+ 还要开「开发者模式」。

> Sideloadly 会重新签名，扩展和主 App 一起装。免费 Apple ID 同样 7 天有效。

### 路线 C：已越狱 / TrollStore

直接装未签名 ipa，永久有效。

---

## 第一次使用

1. 打开 App，输密码（服务器 PIN，默认 `fj2026`）。
2. 设置里确认服务器地址：`http://64.90.0.27:8099`。
3. 「决策」页点 **浮到游戏上** → 屏幕上方出现画中画卡片。
4. 控制中心 → 屏幕录制 → 选「德州助手 · 屏幕识别」→ 开始直播。
5. 切回 Telegram 打开牌局，卡片自动跟着画面刷新。

停止：控制中心停止直播，或在 App 里点「收起」。

---

## 服务器端

后端在 `poker_app/server/`，新增了 `/api/vision`：接收整屏 OCR 文本，先解析牌局再出决策，6 秒内相同文本走缓存，不重复烧 token。

```bash
curl -X POST http://64.90.0.27:8099/api/vision \
  -H "Content-Type: application/json" -H "X-Pin: fj2026" \
  -d '{"text":"翻牌 Qh 7c 2h 底池24 需跟注8 我 AhKh","mode":"long"}'
```

---

## 目录

```
PokerOverlay/
├── project.yml                 XcodeGen 工程定义（App + 扩展）
├── PokerOverlay/
│   ├── App/                    入口、Store、PIN 门
│   ├── Net/                    API 客户端、模型
│   ├── UI/                     决策页、战绩页、设置页
│   ├── Overlay/                PiP 控制器、渲染器、本机 HTTP 通道
│   └── Assets.xcassets/        App 图标
├── BroadcastExtension/
│   └── SampleHandler.swift     屏幕直播 → Vision OCR → POST
└── .github/workflows/build-ipa.yml
```

---

## 调优

| 问题 | 处理 |
|---|---|
| 识别不到牌面数字 | `minimumTextHeight` 调小、关闭 `usesLanguageCorrection`（已关）、游戏窗口放大 |
| 决策太慢 | 服务器 `/api/vision` 缓存已开；采样 1 帧/秒已够，别调快 |
| 浮窗起不来 | 必须先点按钮再启动（系统要求用户手势）；模拟器不支持 PiP |
| 切后台浮窗消失 | 确认 Info.plist 有 `UIBackgroundModes: audio`；App 需保持运行 |
| 免费签名 7 天掉 | 换付费账号，或用 AltStore 自动续签 |

---

## 安全

- 密码只存在手机本地和服务器 env。
- 服务器已按 IP 限流（180 次/分钟）。
- 直播扩展只发文字，不上传画面。
