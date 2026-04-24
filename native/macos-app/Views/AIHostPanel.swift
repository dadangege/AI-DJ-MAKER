import SwiftUI

struct AIHostPanel: View {
    @ObservedObject var store: SoulDJStore

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(SoulTheme.primaryContainer)
                    Text("AI 主播")
                        .font(.system(size: 24, weight: .bold))
                }
                Text(store.isAiDjConnected ? "主播 Vicky 已在线" : "主播 Vicky 休息了")
                    .font(.system(size: 14, weight: .medium))
                    .italic()
                    .foregroundStyle(store.isAiDjConnected ? SoulTheme.primaryContainer : SoulTheme.muted)
            }

            HStack {
                HostTab(title: "Chat", symbol: "sparkles", active: true)
                HostTab(title: "Vibe", symbol: "waveform", active: false)
                HostTab(title: "Insights", symbol: "chart.bar.fill", active: false)
            }
            .overlay(Rectangle().fill(.white.opacity(0.08)).frame(height: 1), alignment: .bottom)

            VStack(spacing: 16) {
                WaveformCard(
                    active: store.isAiDjConnected,
                    message: store.isAiDjConnected
                        ? (store.aiDjTransitionSummary.isEmpty ? "主播 Vicky 已在线" : store.aiDjTransitionSummary)
                        : "DJ 还未生效，请先去设置里配置"
                )

                Text("\"\(store.aiHostMessage)\"")
                    .font(.system(size: 15))
                    .foregroundStyle(SoulTheme.text)
                    .lineSpacing(4)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassPanel(cornerRadius: 10, opacity: 0.45)

                Button {
                    store.testAiDjTransition()
                } label: {
                    Label(store.aiDjTesting ? "Testing..." : "测试口播", systemImage: store.aiDjTesting ? "hourglass" : "speaker.wave.2.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SoulPillButtonStyle(kind: store.isAiDjConnected ? .primary : .ghost))
                .disabled(store.aiDjTesting || store.aiDjModelStatus == .checking)

                if store.aiDjTransitionSummary.isEmpty == false {
                    Text(store.aiDjTransitionSummary)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(SoulTheme.muted)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Spacer()

            VStack(alignment: .leading, spacing: 10) {
                Text("Recent Logs")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(SoulTheme.muted)
                    .textCase(.uppercase)

                ForEach(store.logs.suffix(5).reversed()) { log in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(log.level == "error" ? Color.red.opacity(0.8) : SoulTheme.secondary)
                            .frame(width: 6, height: 6)
                            .padding(.top, 6)
                        Text(log.message)
                            .font(.system(size: 12))
                            .foregroundStyle(SoulTheme.muted)
                            .lineLimit(2)
                    }
                }
            }

            HStack {
                Text("Tell the DJ what you want...")
                    .foregroundStyle(SoulTheme.muted.opacity(0.55))
                Spacer()
                Image(systemName: "paperplane.fill")
                    .foregroundStyle(SoulTheme.primaryContainer)
            }
            .font(.system(size: 13))
            .padding(.horizontal, 16)
            .frame(height: 42)
            .background(.black.opacity(0.44), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.10)))
        }
        .padding(24)
        .frame(width: 300)
        .background(.black.opacity(0.38))
        .overlay(Rectangle().fill(.white.opacity(0.08)).frame(width: 1), alignment: .leading)
    }
}

struct HostTab: View {
    let title: String
    let symbol: String
    let active: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                Text(title)
            }
            .font(.system(size: 13, weight: active ? .bold : .medium))
            .foregroundStyle(active ? SoulTheme.secondary : SoulTheme.muted.opacity(0.60))

            Rectangle()
                .fill(active ? SoulTheme.secondary : .clear)
                .frame(height: 2)
        }
        .frame(maxWidth: .infinity)
    }
}

struct WaveformCard: View {
    let active: Bool
    let message: String

    var body: some View {
        TimelineView(.animation) { context in
            let phase = active ? context.date.timeIntervalSinceReferenceDate * 2.2 : 0
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.black.opacity(0.38))
                Path { path in
                    path.move(to: CGPoint(x: 0, y: 60))
                    for x in stride(from: 0, through: 250, by: 6) {
                        let y = 60 + sin((Double(x) / 24) + phase) * (active ? 27 : 20)
                        path.addLine(to: CGPoint(x: Double(x), y: y))
                    }
                }
                .stroke(
                    LinearGradient(
                        colors: active
                            ? [SoulTheme.primaryContainer, SoulTheme.secondary, SoulTheme.primaryContainer]
                            : [SoulTheme.primaryContainer.opacity(0.45), SoulTheme.primaryContainer.opacity(0.20)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: active ? 3.4 : 2.4, lineCap: .round, lineJoin: .round)
                )
                .shadow(color: active ? SoulTheme.primaryContainer.opacity(0.45) : .clear, radius: 10)

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
