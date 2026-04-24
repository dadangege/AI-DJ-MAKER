import SwiftUI

struct PlayerBar: View {
    @ObservedObject var store: SoulDJStore

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 980
            let horizontalPadding: CGFloat = compact ? 18 : 34

            playerLayout(compact: compact)
            .padding(.horizontal, horizontalPadding)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .frame(height: 106)
        .background(.black.opacity(0.72))
        .overlay(Rectangle().fill(.white.opacity(0.08)).frame(height: 1), alignment: .top)
    }

    private func playerLayout(compact: Bool) -> some View {
        VStack(spacing: compact ? 7 : 9) {
            ZStack {
                trackInfo
                    .frame(maxWidth: compact ? 360 : 420, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                transportControls
                    .fixedSize()
                    .frame(maxWidth: .infinity, alignment: .center)

                rightControls(showQueueIcon: !compact)
                    .frame(width: compact ? 136 : 218, alignment: .trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(maxWidth: .infinity)

            progressRow
                .frame(maxWidth: .infinity)
        }
    }

    private var trackInfo: some View {
        HStack(spacing: 12) {
            AlbumArtMini(coverURL: store.currentTrack.coverURL)
                .frame(width: 52, height: 52)
                .layoutPriority(1)
            VStack(alignment: .leading, spacing: 4) {
                Text(store.currentTrack.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SoulTheme.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(store.currentTrack.artist)
                    .font(.system(size: 12))
                    .foregroundStyle(SoulTheme.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            Button {} label: {
                Image(systemName: "heart.fill")
                    .foregroundStyle(SoulTheme.primaryContainer)
            }
            .buttonStyle(.plain)
        }
    }

    private var transportControls: some View {
        HStack(spacing: 22) {
            Button { store.previous() } label: {
                Image(systemName: "backward.end.fill")
            }
            .disabled(store.isPreparingPlayback)

            Button { store.togglePlay() } label: {
                if store.isPreparingPlayback {
                    ProgressView()
                        .scaleEffect(0.82)
                        .frame(width: 42, height: 42)
                } else {
                    Image(systemName: store.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 42))
                        .foregroundStyle(SoulTheme.primaryContainer)
                        .shadow(color: SoulTheme.primaryContainer.opacity(0.45), radius: 16)
                }
            }

            Button { store.next() } label: {
                Image(systemName: "forward.end.fill")
            }
            .disabled(store.isPreparingPlayback)
        }
        .buttonStyle(.plain)
        .font(.system(size: 20))
        .foregroundStyle(SoulTheme.muted)
    }

    private var progressRow: some View {
        HStack(spacing: 10) {
            Text(formatTime(store.elapsed))
                .frame(width: 38, alignment: .trailing)
            Slider(
                value: Binding(
                    get: { min(max(0, store.elapsed), max(1, store.duration)) },
                    set: { store.elapsed = $0 }
                ),
                in: 0...max(1, store.duration),
                onEditingChanged: { editing in
                    if editing == false {
                        store.seek(to: store.elapsed)
                    }
                }
            )
            .tint(SoulTheme.primaryContainer)
            .disabled(store.currentTrack.localPath.isEmpty)
            .layoutPriority(1)

            if store.isPreparingPlayback {
                Text(store.downloadStatus)
                    .foregroundStyle(SoulTheme.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 96, alignment: .leading)
            }
            Text(formatTime(store.duration))
                .frame(width: 38, alignment: .leading)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(SoulTheme.muted)
    }

    private func rightControls(showQueueIcon: Bool) -> some View {
        HStack(spacing: 13) {
            Button {
                store.cyclePlaybackMode()
            } label: {
                Image(systemName: store.playbackMode.symbolName)
                    .foregroundStyle(store.playbackMode == .ordered ? SoulTheme.muted : SoulTheme.secondary)
            }
            .buttonStyle(.plain)
            .help(store.playbackMode.title)

            if showQueueIcon {
                Image(systemName: "music.note.list")
            }
            Image(systemName: "speaker.wave.2.fill")
            Slider(
                value: Binding(
                    get: { store.volume * 100 },
                    set: { store.setVolume($0 / 100) }
                ),
                in: 0...100
            )
            .tint(SoulTheme.text)
            .frame(minWidth: 58, idealWidth: 82, maxWidth: 96)
        }
        .foregroundStyle(SoulTheme.muted)
    }

    private func formatTime(_ value: Double) -> String {
        let value = max(0, Int(value))
        return "\(value / 60):\(String(format: "%02d", value % 60))"
    }
}

struct AlbumArtMini: View {
    let coverURL: String?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7)
                .fill(LinearGradient(colors: [SoulTheme.primaryContainer, SoulTheme.secondary, .black], startPoint: .topLeading, endPoint: .bottomTrailing))

            if let coverURL, let url = URL(string: coverURL), !coverURL.isEmpty {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        Image(systemName: "waveform")
                            .foregroundStyle(.white)
                    }
                }
            } else {
                Image(systemName: "waveform")
                    .foregroundStyle(.white)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(.white.opacity(0.12)))
    }
}
