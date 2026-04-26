import SwiftUI

struct AIHostPanel: View {
    @ObservedObject var store: SoulDJStore
    @State private var selectedTab: AIHostTab = .chat

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .center, spacing: 12) {
                if let host = store.configuredHost {
                    AIHostAvatar(host: host, size: 42)
                } else {
                    UnsetAIHostAvatar(size: 42)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("AI 主播")
                        .font(.system(size: 24, weight: .bold))
                    Text(hostStatusText)
                        .font(.system(size: 14, weight: .medium))
                        .italic()
                        .foregroundStyle(store.hasSelectedHost && store.isAiDjConnected ? SoulTheme.primaryContainer : SoulTheme.muted)
                }

                Spacer()

                Button {
                    store.openHostPicker()
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 14, weight: .bold))
                }
                .buttonStyle(SoulIconButtonStyle())
                .help("切换主播")
            }

            HStack {
                ForEach(AIHostTab.allCases, id: \.self) { tab in
                    HostTab(tab: tab, active: selectedTab == tab) {
                        selectedTab = tab
                    }
                }
            }
            .overlay(Rectangle().fill(.white.opacity(0.08)).frame(height: 1), alignment: .bottom)

            Group {
                switch selectedTab {
                case .chat:
                    chatContent
                case .recentLog:
                    recentLogContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(24)
        .frame(width: 300)
        .background(.black.opacity(0.38))
        .overlay(Rectangle().fill(.white.opacity(0.08)).frame(width: 1), alignment: .leading)
    }

    private var hostStatusText: String {
        guard let host = store.configuredHost else {
            return "还未选择主播，点击右侧按钮设置"
        }
        let mode = store.configuredHostMode?.title ?? "未选择模式"
        return store.isAiDjConnected ? "主播 \(host.name) 已在线 · \(mode)" : "主播 \(host.name) 休息了"
    }

    private var chatContent: some View {
        VStack(spacing: 16) {
            WaveformCard(
                active: store.isAiDjConnected,
                levels: store.spectrumLevels,
                message: store.isAiDjConnected
                    ? (store.aiDjTransitionSummary.isEmpty ? (store.configuredHost.map { "主播 \($0.name) 已在线" } ?? "请先选择 AI 主播") : store.aiDjTransitionSummary)
                    : "DJ 还未生效，请先去设置里配置"
            )

            LyricsPanel(
                lines: store.lyricLines,
                elapsed: store.elapsed,
                status: store.lyricStatus
            )
        }
    }

    private var recentLogContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if store.logs.isEmpty {
                    Text("暂无日志")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(SoulTheme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)
                } else {
                    ForEach(store.logs.suffix(18).reversed()) { log in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(log.level == "error" ? Color.red.opacity(0.8) : SoulTheme.secondary)
                                .frame(width: 6, height: 6)
                                .padding(.top, 6)
                            Text(log.message)
                                .font(.system(size: 12))
                                .foregroundStyle(SoulTheme.muted)
                                .lineLimit(3)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct LyricsPanel: View {
    let lines: [TimedLyricLine]
    let elapsed: Double
    let status: String

    private var activeID: Int? {
        guard lines.isEmpty == false else { return nil }
        return lines.last(where: { $0.time <= elapsed + 0.18 })?.id ?? lines.first?.id
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.black.opacity(0.30))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.08)))

            if lines.isEmpty {
                Text(status.isEmpty ? "暂无歌词" : status)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SoulTheme.muted.opacity(0.68))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 13) {
                            Spacer().frame(height: 34)
                            ForEach(lines) { line in
                                LyricLineView(line: line, active: line.id == activeID)
                                    .id(line.id)
                            }
                            Spacer().frame(height: 58)
                        }
                        .padding(.horizontal, 14)
                    }
                    .mask(
                        LinearGradient(
                            colors: [.clear, .black, .black, .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .onChange(of: activeID) { _, nextID in
                        guard let nextID else { return }
                        withAnimation(.easeInOut(duration: 0.42)) {
                            proxy.scrollTo(nextID, anchor: .center)
                        }
                    }
                    .onAppear {
                        guard let activeID else { return }
                        proxy.scrollTo(activeID, anchor: .center)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .layoutPriority(1)
    }
}

struct LyricLineView: View {
    let line: TimedLyricLine
    let active: Bool

    var body: some View {
        Text(line.text)
            .font(.system(size: active ? 15 : 13, weight: active ? .semibold : .regular))
            .foregroundStyle(active ? SoulTheme.text : SoulTheme.muted.opacity(0.50))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .frame(maxWidth: .infinity)
            .scaleEffect(active ? 1.02 : 0.96)
            .shadow(color: active ? SoulTheme.secondary.opacity(0.28) : .clear, radius: 8)
    }
}

struct HostTab: View {
    let tab: AIHostTab
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: tab.symbol)
                    Text(tab.title)
                }
                .font(.system(size: 13, weight: active ? .bold : .medium))
                .foregroundStyle(active ? SoulTheme.secondary : SoulTheme.muted.opacity(0.60))

                Rectangle()
                    .fill(active ? SoulTheme.secondary : .clear)
                    .frame(height: 2)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

enum AIHostTab: CaseIterable {
    case chat
    case recentLog

    var title: String {
        switch self {
        case .chat: return "Chat"
        case .recentLog: return "Recent Log"
        }
    }

    var symbol: String {
        switch self {
        case .chat: return "sparkles"
        case .recentLog: return "list.bullet.rectangle"
        }
    }
}

struct WaveformCard: View {
    let active: Bool
    let levels: [Float]
    let message: String

    var body: some View {
        TimelineView(.animation) { context in
            let phase = active ? context.date.timeIntervalSinceReferenceDate * 2.2 : 0
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.black.opacity(0.38))
                SpectrumBarsView(active: active, phase: phase, levels: levels)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)

                Text(message)
                    .font(.system(size: 12, weight: active ? .semibold : .medium))
                    .foregroundStyle(active ? SoulTheme.text.opacity(0.72) : SoulTheme.muted.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
            }
            .frame(height: 128)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}

struct SpectrumBarsView: View {
    let active: Bool
    let phase: TimeInterval
    let levels: [Float]

    private let barCount = 36

    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            let baseline = height * 0.66
            let barWidth = max(2, (proxy.size.width - CGFloat(barCount - 1) * 3) / CGFloat(barCount))

            ZStack(alignment: .bottomLeading) {
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(0..<barCount, id: \.self) { index in
                        let level = spectrumLevel(for: index)
                        let barHeight = max(active ? 7 : 3, baseline * level)
                        let peakOffset = max(0, barHeight + 5 + CGFloat(peakLevel(for: index)) * 12)

                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(barGradient(index: index))
                                .frame(width: barWidth, height: barHeight)
                                .shadow(color: SoulTheme.secondary.opacity(active ? 0.34 : 0.08), radius: active ? 7 : 1)

                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                .fill(SoulTheme.text.opacity(active ? 0.82 : 0.22))
                                .frame(width: barWidth, height: 2)
                                .offset(y: -peakOffset)

                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(barGradient(index: index).opacity(active ? 0.25 : 0.08))
                                .frame(width: barWidth, height: barHeight * 0.34)
                                .scaleEffect(y: -1, anchor: .bottom)
                                .offset(y: 7)
                                .blur(radius: 1.3)
                        }
                    }
                }
                .frame(height: height, alignment: .bottom)

                LinearGradient(colors: [.clear, .black.opacity(0.62)], startPoint: .top, endPoint: .bottom)
                    .frame(height: height * 0.38)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
    }

    private func spectrumLevel(for index: Int) -> CGFloat {
        if active, levels.indices.contains(index), levels[index] > 0.01 {
            let measured = Double(levels[index])
            let shaped = min(1, 0.08 + measured * 1.05)
            return CGFloat(shaped)
        }

        let position = Double(index) / Double(max(1, barCount - 1))
        let bass = sin(phase * 1.8 + position * 4.7)
        let mids = sin(phase * 3.1 + position * 11.3)
        let highs = sin(phase * 5.4 + position * 23.0)
        let curve = 1.0 - abs(position - 0.34) * 0.74
        let motion = (bass * 0.40) + (mids * 0.26) + (highs * 0.13)
        let energized = max(0.08, min(1.0, 0.38 + motion + curve * 0.36))
        return CGFloat(active ? energized : 0.07 + curve * 0.06)
    }

    private func peakLevel(for index: Int) -> CGFloat {
        guard active else { return 0 }
        let position = Double(index) / Double(max(1, barCount - 1))
        return CGFloat(max(0, sin(phase * 1.15 + position * 8.0)) * 0.65)
    }

    private func barGradient(index: Int) -> LinearGradient {
        let position = Double(index) / Double(max(1, barCount - 1))
        let highColor = position < 0.62 ? SoulTheme.secondary : SoulTheme.primaryContainer
        return LinearGradient(
            colors: [
                SoulTheme.primaryContainer.opacity(active ? 0.92 : 0.26),
                highColor.opacity(active ? 0.95 : 0.18)
            ],
            startPoint: .bottom,
            endPoint: .top
        )
    }
}
