# Soul DJ

Soul DJ 是一个开源的 macOS AI 电台播放器原型。它可以登录网易云音乐、读取歌单、本地播放歌曲，并在两首歌之间生成 AI 主播串场，让普通歌单变成更像电台的连续收听体验。

项目主界面使用原生 SwiftUI 编写，配合少量 Node.js 脚本完成构建、打包和 TTS 辅助工具。

## 功能特性

- 网易云音乐扫码登录。
- 加载个人歌单和公共歌单，支持歌单封面展示。
- 本地播放队列，支持播放、暂停、上一首、下一首、进度、音量、循环和随机。
- 歌词同步显示。
- AI 主播自动生成两首歌之间的串场文案。
- 支持 MiniMax / OpenAI-compatible 文本与 TTS 配置。
- 支持选择不同 AI 主播和播报模式。
- 口播时自动降低背景音乐音量，并做线性淡入淡出。
- 启动后可尝试展示 IP 城市和天气信息，失败时不影响使用。

## 界面结构

Soul DJ 是一个深色音乐 App 风格的桌面应用：

- 左侧：导航、歌单和推荐内容。
- 中间：歌单详情、歌曲列表、播放内容和歌词。
- 右侧：AI 主播、聊天、最近串场记录和音律可视化。
- 底部：常驻播放控制栏。

## 运行要求

- macOS
- Node.js 18+
- Xcode Command Line Tools 或 Xcode
- 用于 AI 文案和 TTS 的 MiniMax / OpenAI-compatible API Key

网易云登录态、API Key、音乐缓存和 TTS 缓存都保存在本机，不会随分享包或仓库提交。

## 快速开始

克隆项目：

```bash
git clone git@github.com:dadangege/AI-DJ-MAKER.git
cd AI-DJ-MAKER
```

构建 macOS App：

```bash
npm run mac-app:build
```

打开应用：

```bash
open "macos/Soul DJ.app"
```

首次使用：

1. 在设置里填写 API Key、Base URL、文本模型和 TTS 模型。
2. 使用网易云音乐扫码登录。
3. 选择歌单并开始播放。
4. 可选：进入 AI 主播切换页，选择主播和播报模式。

## 常用命令

构建原生 App：

```bash
npm run mac-app:build
```

生成分享包：

```bash
npm run share:package
```

命令行生成一段 TTS：

```bash
npm run tts -- --text "欢迎收听 Soul DJ。" --out output/intro.mp3
```

查看可用音色：

```bash
npm run voices
```

启动旧版网页 TTS 工具：

```bash
npm run app
```

## AI 主播模式

当前支持几种主播风格：

- 夜店 DJ：更活跃，重点介绍下一首歌和节奏变化。
- 午夜电台：更慢、更低声、更有陪伴感。
- 音乐推荐官：解释为什么推荐下一首歌。
- 情绪陪伴：根据歌曲情绪做温柔过渡。
- 轻松聊天：更随意、更口语化的短串场。

主播和模式会保存在本机配置里。首次登录时默认不强制选择主播，用户可以在右侧 AI 主播区域进入设置。

## 环境信息

应用启动后会尝试通过公共接口获取城市和天气：

- IP 定位：`https://ipapi.co/json/`
- 天气：Open-Meteo

如果获取成功，顶部会显示一个城市和天气的小标签；如果失败，则不显示，不弹窗，也不影响播放。

## 项目结构

```text
native/macos-app/      原生 SwiftUI macOS App
src/                   Node.js TTS 与旧版辅助工具
script/                构建和打包脚本
examples/              示例电台文案
output/                本地生成音频目录，已被 git 忽略
macos/                 构建后的 App 输出目录
```

## 当前状态

这是一个本地优先的实验性 AI 电台应用，适合用来探索：

- AI 电台串场
- 虚拟主播与 TTS 音色
- 歌单播放体验
- 简单双轨混音
- 歌曲情绪与下一首推荐之间的自然衔接

项目还不是正式商业产品，也不适合直接上架 App Store。部分能力依赖第三方音乐接口和公共网络服务，不同账号、地区和网络环境下表现可能不同。

## License

License 暂未确定。
