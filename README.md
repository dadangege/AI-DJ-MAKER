# Soul DJ / AI-DJ-MAKER

一个运行在 Mac 本地的 AI 电台 / AI DJ 原型。它可以扫码登录网易云、读取歌单、播放本地队列，并在两首歌衔接处提前生成 AI 主播串场词和 TTS 口播，通过双轨播放实现基础 ducking、fade 与 crossfade。

当前主版本是原生 SwiftUI App，不再依赖 Python 版 `Netease_url` 服务。网易云扫码登录、歌单读取、歌词读取和播放地址解析都已迁移到 Swift 内置实现。

## 当前能力

- 原生 SwiftUI 桌面界面：深色玻璃态 Soul DJ UI、左侧导航、AI 主播状态、底部播放器。
- 网易云扫码登录：登录态保存在本机，不随分享包分发。
- 歌单播放：支持播放/暂停、上一首/下一首、进度拖动、音量、顺序/循环/单曲循环/随机。
- AI 串场：当前歌开始后提前生成“当前歌 -> 下一首”的串场文案和 TTS 音频。
- 广播式衔接：根据 TTS 时长计算口播开始点，让口播尽量跨在两首歌边界附近。
- 混音策略：口播时音乐自动 duck，结束后平滑恢复；切歌时下一首淡入。
- OpenAI-compatible 配置：朋友使用时填写自己的 API Key、Base URL、文本模型和 TTS 模型。

## 打包给别人测试

构建并生成分享包：

```bash
npm run mac-app:build
npm run share:package
```

生成文件：

```text
dist/SoulDJ-Share.zip
```

分享包只包含 `.app` 和 README，不包含 API Key、网易云 Cookie、音乐缓存、TTS 缓存、`.env`、Python 依赖或 Node 依赖。

朋友第一次打开后需要：

1. 在设置里填写自己的 OpenAI-compatible API 配置。
2. 点击网易云扫码登录。
3. 选择歌单，双击歌曲开始播放。

> 当前构建是 Apple Silicon / arm64 版本，Intel Mac 可能无法运行。

## 调研结论

- MiniMax 的 HTTP T2A 接口是 `POST /v1/t2a_v2`，认证方式是 `Authorization: Bearer <api key>`。
- 电台/主播场景建议先用 `speech-2.8-hd` 做高质量离线生成；如果更看重延迟，可以试 `speech-2.8-turbo`。
- `MiniMax-M2.7-highspeed` 是文本生成模型，不适用于 TTS 的 `model` 参数；TTS 这里请使用 `speech-2.8-hd`、`speech-2.8-turbo` 等 speech 模型。
- 情绪不是只靠一个开关，主要来自音色、语速、音高、停顿、文稿写法和控制标签组合。
- `speech-2.8` 系列支持停顿标签，例如 `<#0.8#>`；也支持一些非语言/语气标签，例如 `(breath)`、`(laughs)`、`(sighs)`，适合做更自然的电台留白。
- 中文电台建议从 `Chinese (Mandarin)_News_Anchor` 这类主播音色开始，再通过 `--speed 0.86-0.95`、`--pitch -2~-1` 做更沉稳的风格。

## 快速开始

需要 Node.js 18+。

```bash
cp .env.example .env
```

命令行模式可以填 OpenAI-compatible 环境变量：

```bash
OPENAI_API_KEY=你的_key
OPENAI_BASE_URL=https://api.minimaxi.com/v1
OPENAI_MODEL=MiniMax-M2.7-highspeed
```

macOS App 模式不用改 `.env`，打开后在顶部“接口配置”里填写 API Key、Base URL、文本模型和 TTS 模型即可。

生成示例电台音频：

```bash
npm run tts -- --file examples/radio-script.txt --preset story --out output/radio.mp3
```

如果你的机器没有 `npm`，可以直接用 Node 运行：

```bash
node src/minimax-tts.mjs --file examples/radio-script.txt --preset story --out output/radio.mp3
```

也可以直接传文字：

```bash
npm run tts -- --text "欢迎收听今晚的节目，我是你的声音朋友。" --out output/intro.mp3
```

## macOS App

已经内置一个不用 Xcode 编译的轻量 macOS App：

```text
macos/Soul DJ.app
```

在 Finder 里双击它，会启动一个原生 SwiftUI 的 Soul DJ 窗口。当前新版主界面优先展示自建 AI DJ 播放器、网易云扫码登录、歌单入口、AI 主播状态和底部播放器。

旧的网页 TTS 试听台仍保留在 `web/` 和 `src/app-server.mjs` 中作为回退/高级工具参考，但新版原生主窗口不再通过 `WKWebView` 打开 Node 网页 UI。

首次发给朋友使用时，对方需要在 App 顶部填写自己的 OpenAI-compatible 配置。Key 会保存在对方本机：

```text
~/Library/Application Support/MiniMax TTS Studio/settings.json
```

生成不包含 `.env` 的分享目录：

```bash
npm run share:package
```

分享 `dist/SoulDJ-Share.zip` 即可。当前 Swift 主链路不再要求朋友安装 Python、Node 或运行额外依赖脚本。

如果修改了原生壳代码，可以重新构建：

```bash
npm run mac-app:build
```

旧 Web 试听台仍可用命令行单独启动：

```bash
node src/app-server.mjs --open
```

生成的音频会保存在：

```text
output/mac-app/
```

## 查看可用音色

```bash
npm run voices
```

或：

```bash
node src/list-voices.mjs
```

如果默认主播音色不适合，可以把输出里的 `voice_id` 传给 `--voice`：

```bash
npm run tts -- --file examples/radio-script.txt --voice "Chinese (Mandarin)_News_Anchor" --out output/custom.mp3
```

## 电台风格参数

内置了三个预设：

- `radio`：温暖、沉稳，默认预设。
- `story`：更慢、更有留白，适合深夜节目、情感故事。
- `news`：语速更标准，适合资讯播报。

常用覆盖参数：

```bash
npm run tts -- \
  --file examples/radio-script.txt \
  --model speech-2.8-hd \
  --voice "Chinese (Mandarin)_News_Anchor" \
  --speed 0.9 \
  --pitch -1 \
  --out output/radio.mp3
```

## 让声音更有情绪

文稿里直接写停顿和语气控制：

```text
今晚的节目，我们想从一个问题开始：如果时间可以被听见，它会是什么声音？
<#0.8#>
也许，是凌晨街角第一辆车驶过的风声。
(breath)
也许，是你在某个深夜，终于决定重新开始时，那一秒钟的安静。
```

建议从这几类方式调：

- 停顿：在转场、反问、句尾加 `<#0.5#>` 到 `<#1.2#>`。
- 语速：情绪、故事类用 `0.86-0.95`；新闻资讯用 `0.98-1.08`。
- 音高：温柔沉稳可试 `-2` 到 `-1`；活泼节目可试 `1` 到 `2`。
- 文案：把长句拆短，给重点句单独成行，TTS 的表达会更自然。

## 文件说明

- `src/minimax-tts.mjs`：生成音频的 CLI。
- `src/list-voices.mjs`：查询 MiniMax 音色。
- `examples/radio-script.txt`：电台风格示例文稿。
- `output/`：生成音频目录，已加入 `.gitignore`。
