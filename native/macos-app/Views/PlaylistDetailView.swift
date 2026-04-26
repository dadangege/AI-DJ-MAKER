import SwiftUI

struct PlaylistDetailView: View {
    @ObservedObject var store: SoulDJStore

    private var playlist: NeteasePlaylist? { store.selectedPlaylist ?? store.playlists.first }
    private var tracks: [SoulTrack] { store.pagedTracks }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Button {
                    store.goHome()
                } label: {
                    Label("返回首页", systemImage: "chevron.left")
                }
                .buttonStyle(SoulPillButtonStyle(kind: .ghost))

                HStack(alignment: .bottom, spacing: 32) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(LinearGradient(colors: [SoulTheme.primaryContainer.opacity(0.75), SoulTheme.secondary.opacity(0.45), .black], startPoint: .topLeading, endPoint: .bottomTrailing))
                        if let url = playlist?.coverURL.neteaseImageURL {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFill()
                                default:
                                    playlistPlaceholder
                                }
                            }
                        } else {
                            playlistPlaceholder
                        }
                    }
                    .frame(width: 240, height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .glassPanel(cornerRadius: 18)

                    VStack(alignment: .leading, spacing: 16) {
                        Text("CURATED PLAYLIST")
                            .font(.system(size: 12, weight: .bold))
                            .tracking(1.4)
                            .foregroundStyle(SoulTheme.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(SoulTheme.secondary.opacity(0.10), in: Capsule())
                            .overlay(Capsule().stroke(SoulTheme.secondary.opacity(0.30)))

                        Text(playlist?.name ?? "Soul Vibes")
                            .font(.system(size: 44, weight: .heavy, design: .rounded))
                            .foregroundStyle(SoulTheme.text)

                        Text(playlist.map { "\($0.trackCount) 首歌曲 · \($0.creator.isEmpty ? "网易云歌单" : $0.creator)" } ?? "选择一个歌单后，Soul DJ 会准备歌曲缓存和串场。")
                            .font(.system(size: 18))
                            .foregroundStyle(SoulTheme.muted)
                            .lineSpacing(5)
                            .frame(maxWidth: 620, alignment: .leading)

                        HStack(spacing: 14) {
                            Button {
                                if let selected = store.selectedTrackForPlayback ?? store.selectedTracks.first {
                                    store.playTrack(selected)
                                } else {
                                    store.togglePlay()
                                }
                            } label: {
                                Label("Play", systemImage: "play.fill")
                            }
                            .buttonStyle(SoulPillButtonStyle(kind: .primary))

                            Button {} label: { Image(systemName: "heart.fill") }
                                .buttonStyle(SoulIconButtonStyle())
                            Button {
                                store.refreshSelectedPlaylistTracks()
                            } label: { Image(systemName: "arrow.clockwise") }
                                .buttonStyle(SoulIconButtonStyle())
                        }
                    }
                }

                VStack(spacing: 0) {
                    TrackHeader()
                    if store.loadingTracks && store.selectedTracks.isEmpty {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("正在拉取歌单歌曲...")
                                .foregroundStyle(SoulTheme.muted)
                            Spacer()
                        }
                        .padding(24)
                    } else if tracks.isEmpty {
                        VStack(spacing: 10) {
                            Text("还没有歌曲列表")
                                .font(.system(size: 18, weight: .semibold))
                            Button("重新拉取歌单") {
                                store.refreshSelectedPlaylistTracks()
                            }
                            .buttonStyle(SoulPillButtonStyle(kind: .primary))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(36)
                        .foregroundStyle(SoulTheme.text)
                    } else {
                        ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                            TrackRow(
                                index: store.trackPage * store.tracksPerPage + index + 1,
                                track: track,
                                active: track.id == store.currentTrack.id,
                                selected: track.id == store.selectedTrackID,
                                preparing: track.id == store.preparingTrackID,
                                playAction: {
                                    store.playTrack(track)
                                }
                            )
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                store.playTrack(track)
                            }
                            .onTapGesture(count: 1) {
                                store.selectTrackForPlayback(track)
                            }
                        }
                        TrackPagination(store: store)
                    }
                }
                .glassPanel(cornerRadius: 16)
            }
            .padding(32)
        }
    }

    private var playlistPlaceholder: some View {
        Image(systemName: "music.note.list")
            .font(.system(size: 78, weight: .bold))
            .foregroundStyle(.white.opacity(0.86))
    }
}

struct TrackPagination: View {
    @ObservedObject var store: SoulDJStore

    var body: some View {
        HStack(spacing: 14) {
            Text(store.trackPageRangeText)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SoulTheme.muted)

            Spacer()

            Button {
                store.previousTrackPage()
            } label: {
                Label("上一页", systemImage: "chevron.left")
            }
            .buttonStyle(SoulPillButtonStyle(kind: .ghost))
            .disabled(store.trackPage == 0)

            Text("\(store.trackPage + 1) / \(store.totalTrackPages)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(SoulTheme.text)
                .frame(minWidth: 58)

            Button {
                store.nextTrackPage()
            } label: {
                Label("下一页", systemImage: "chevron.right")
            }
            .buttonStyle(SoulPillButtonStyle(kind: .ghost))
            .disabled(store.trackPage >= store.totalTrackPages - 1)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .overlay(Rectangle().fill(.white.opacity(0.06)).frame(height: 1), alignment: .top)
    }
}

struct TrackHeader: View {
    var body: some View {
        GridRowView(number: "#", title: "TITLE", artist: "ARTIST", album: "ALBUM", duration: "TIME")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(SoulTheme.muted)
            .padding(.vertical, 14)
            .overlay(Rectangle().fill(.white.opacity(0.06)).frame(height: 1), alignment: .bottom)
    }
}

struct TrackRow: View {
    let index: Int
    let track: SoulTrack
    let active: Bool
    let selected: Bool
    let preparing: Bool
    let playAction: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            if preparing {
                ProgressView()
                    .scaleEffect(0.55)
                    .frame(width: 44, alignment: .center)
            } else {
                Text(active ? "▮" : "\(index)")
                    .frame(width: 44, alignment: .center)
            }
            Text(track.title).frame(maxWidth: .infinity, alignment: .leading)
            Text(track.artist).frame(maxWidth: .infinity, alignment: .leading)
            Text(track.album).frame(maxWidth: .infinity, alignment: .leading)
            Text(formatTime(track.duration)).frame(width: 62, alignment: .trailing)
            Button(action: playAction) {
                Image(systemName: active ? "pause.fill" : "play.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(active ? SoulTheme.primaryContainer : SoulTheme.text)
                    .frame(width: 24, height: 24)
                    .background(.white.opacity(active ? 0.12 : 0.07), in: Circle())
            }
            .buttonStyle(.plain)
            .help("播放这首歌")
        }
        .padding(.horizontal, 24)
        .lineLimit(1)
        .font(.system(size: 14))
        .foregroundStyle(active ? SoulTheme.primary : SoulTheme.text)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(rowBackground)
        .contentShape(Rectangle())
        .overlay(alignment: .leading) {
            if active {
                Rectangle().fill(SoulTheme.primaryContainer).frame(width: 2)
            } else if selected {
                Rectangle().fill(SoulTheme.secondary.opacity(0.65)).frame(width: 2)
            }
        }
    }

    private var rowBackground: Color {
        if active { return .white.opacity(0.06) }
        if selected { return .white.opacity(0.035) }
        return .clear
    }

    private func formatTime(_ value: Double) -> String {
        let int = Int(value)
        return "\(int / 60):\(String(format: "%02d", int % 60))"
    }
}

struct GridRowView: View {
    let number: String
    let title: String
    let artist: String
    let album: String
    let duration: String

    var body: some View {
        HStack(spacing: 16) {
            Text(number).frame(width: 44, alignment: .center)
            Text(title).frame(maxWidth: .infinity, alignment: .leading)
            Text(artist).frame(maxWidth: .infinity, alignment: .leading)
            Text(album).frame(maxWidth: .infinity, alignment: .leading)
            Text(duration).frame(width: 62, alignment: .trailing)
        }
        .padding(.horizontal, 24)
        .lineLimit(1)
    }
}
