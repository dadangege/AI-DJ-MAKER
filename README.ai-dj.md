# AI DJ MVP

一个运行在 Mac 本地的 AI 电台 / AI DJ 原型。它读取系统级 Now Playing 信息，在歌曲衔接的两个阶段提前生成中文串场词：`pre_outro`、`gap_bridge`。先缓存文案，再在合适时机用 MiniMax TTS 合成语音并用 `afplay` 本地播放。

## 前置条件

- macOS
- Node.js 18+
- Xcode Command Line Tools / Xcode
- macOS App 顶部填写 OpenAI-compatible API 配置，或在 `.env` 中配置 `OPENAI_API_KEY`
- 允许本机使用 macOS 私有 `MediaRemote.framework`，仅用于本地原型

## 运行

推荐先安装 MediaRemote Adapter，它能在 macOS 15.4+ 上更可靠地读取系统 Now Playing：

```bash
npm run mediaremote-adapter:setup
```

先构建系统级 Now Playing helper：

```bash
npm run ai-dj:build-listener
```

启动 AI DJ：

```bash
npm run ai-dj
```

如果当前机器没有 `npm`，可以直接运行：

```bash
swiftc native/now-playing-listener/main.swift -framework Foundation -F /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/PrivateFrameworks -framework MediaRemote -o native/now-playing-listener/now-playing-listener
node src/ai-dj/orchestrator.mjs
```

## 验证

1. 用任意支持系统 Now Playing 的播放器播放音乐，例如网易云音乐、Apple Music、Spotify、浏览器音乐页。
2. 观察终端输出当前歌曲、artist、elapsed、duration。
3. 看到界面里的“当前阶段 / 下一阶段 / 缓存状态”开始变化，说明串场计划和文案预生成已经在跑。
4. 到对应阶段后，MiniMax TTS 会先把音频预热好，然后 `afplay` 本地播放。

## 配置

可通过环境变量覆盖：

```bash
AI_DJ_TRIGGER_SECONDS=12
AI_DJ_VOICE_ID="Chinese (Mandarin)_Gentle_Senior"
OPENAI_API_KEY="你的_key"
OPENAI_BASE_URL="https://api.minimaxi.com/v1"
OPENAI_MODEL="MiniMax-M2.7-highspeed"
AI_DJ_TTS_MODEL="speech-2.8-hd"
AI_DJ_PRE_OUTRO_LEAD_SECONDS=15
AI_DJ_INTRO_BRIDGE_START_SECONDS=5
AI_DJ_INTRO_BRIDGE_END_SECONDS=14
AI_DJ_GAP_BRIDGE_GRACE_SECONDS=8
AI_DJ_TTS_PREFETCH_SECONDS=8
AI_DJ_DUCK_VOLUME=22
AI_DJ_ALLOW_SYSTEM_DUCKING=true
AI_DJ_TTS_PLAYBACK_GAIN=1.25
```

## 自建播放器模式

现在 App 里新增了“自建播放器模式”，主链路不再依赖系统 Now Playing：

1. 点击“扫码登录网易云”，用网易云手机 App 扫码并确认登录。
2. 登录成功后点击“刷新歌单”，App 会读取你的网易云歌单并填入下拉框。
3. 点击“启动网易云服务”会启动本地 `Netease_url` 服务，默认端口 `5000`。
4. 在下拉框选择歌单、音质和缓存数量，点击“加载歌单”。
5. App 会缓存歌曲到 `output/ai-dj/music-cache/`，然后通过原生 `AVAudioEngine` 播放。
6. 当前歌开始后，会立刻基于“当前歌 + 下一首”生成串场文案和 TTS，并按 TTS 时长反推播放点。
7. 播放口播时，音乐轨道会淡出降低，TTS 轨道独立播放，口播结束后音乐淡入恢复。

说明：`Netease_url` README 主推手动填写 Cookie，但仓库里的 `music_api.QRLoginManager` 已包含网易云二维码登录能力；本 App 走扫码登录，把拿到的登录态保存到本机用户目录，不需要用户手动复制 Cookie。

手动安装 `Netease_url`：

```bash
npm run netease-url:setup
```

当前 Mac 只有 Python 3.9 时，安装脚本会自动把 `click==8.2.1` 降级为 `click==8.1.8` 生成兼容 requirements，不修改第三方仓库源码。

## 已知限制

- 使用 macOS 私有 API，只适合本地 MVP，不适合上架 App Store。
- 如果存在 `vendor/mediaremote-adapter/build/MediaRemoteAdapter.framework`，会优先通过 `mediaremote-adapter` 读取 Now Playing；否则回退到本项目的 Swift helper。
- 不保证所有播放器都完整提供 title/artist/duration；网易云缓存兜底只能估算当前歌曲，不支持可靠识别暂停或拖动。
- MVP 只做基础混音，不做更复杂的多轨混音或自动增益控制。
- 现在会优先尝试对 `Music` / `Spotify` 这类支持 `sound volume` 的播放器做单 App 压低与恢复；网易云等不支持单 App 音量的播放器会降级为压低系统输出音量，TTS 同时用 `afplay -v` 抬高播放增益。可用 `AI_DJ_ALLOW_SYSTEM_DUCKING=false` 关闭这个降级。
- 文案先生成、音频临近触发再合成，所以界面里会看到“文案已缓存 / 音频已缓存”的状态变化。
- 自建播放器模式可以做真正双轨 ducking；系统监听模式仍然只能做外部播放器音量控制或系统输出音量降级。
