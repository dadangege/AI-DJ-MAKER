import SwiftUI

struct DashboardView: View {
    @ObservedObject var store: SoulDJStore

    private let recommendations = [
        ("Midnight Synthesis", "The Neural Network", [SoulTheme.primaryContainer, SoulTheme.secondary]),
        ("Deep House Protocol", "System Override", [Color(hex: 0x222222), SoulTheme.primary]),
        ("Lo-Fi Algorithms", "Data Streams", [Color(hex: 0x111827), Color(hex: 0x64748B)]),
        ("Ambient Void", "Silence & Echo", [Color(hex: 0xEF3124), Color(hex: 0x111111)])
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("Recommended For You")
                    .font(.system(size: 42, weight: .heavy, design: .rounded))
                    .foregroundStyle(SoulTheme.text)
                    .shadow(color: .black.opacity(0.65), radius: 0, x: 0, y: 2)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 18), count: 4), spacing: 18) {
                    ForEach(Array(recommendations.enumerated()), id: \.offset) { _, item in
                        AlbumCard(title: item.0, subtitle: item.1, colors: item.2)
                    }
                }

                HStack {
                    Text("Curated Playlists")
                        .font(.system(size: 26, weight: .bold))
                    Spacer()
                    Button("刷新歌单") {
                        Task { await store.refreshPlaylists() }
                    }
                    .buttonStyle(SoulPillButtonStyle(kind: .ghost))
                }
                .foregroundStyle(SoulTheme.text)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    if store.playlists.isEmpty {
                        PlaylistCard(title: "扫码登录网易云", subtitle: "登录后自动读取你的歌单", symbol: "qrcode", accent: SoulTheme.primaryContainer) {
                            store.openLogin()
                        }
                        PlaylistCard(title: "AI DJ 工具箱", subtitle: "TTS 试听和系统监听已移入高级工具", symbol: "wand.and.stars", accent: SoulTheme.secondary) {
                            store.selectedRoute = .settings
                        }
                    } else {
                        ForEach(store.playlists.prefix(6)) { playlist in
                            PlaylistCard(
                                title: playlist.name,
                                subtitle: "\(playlist.trackCount) 首 · \(playlist.creator.isEmpty ? "网易云歌单" : playlist.creator)",
                                symbol: "music.note.list",
                                accent: SoulTheme.primaryContainer
                            ) {
                                store.select(playlist)
                            }
                        }
                    }
                }
            }
            .padding(32)
        }
    }
}

struct AlbumCard: View {
    let title: String
    let subtitle: String
    let colors: [Color]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                Circle()
                    .stroke(.black.opacity(0.72), lineWidth: 26)
                    .frame(width: 98, height: 98)
                    .shadow(color: .white.opacity(0.24), radius: 16)
                Image(systemName: "waveform")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white.opacity(0.84))
            }
            .aspectRatio(1, contentMode: .fit)
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(.white.opacity(0.08)))

            Text(title)
                .font(.system(size: 20, weight: .bold))
                .lineLimit(1)
                .foregroundStyle(SoulTheme.text)
            Text(subtitle)
                .font(.system(size: 14))
                .lineLimit(1)
                .foregroundStyle(SoulTheme.muted)
        }
        .padding(20)
        .glassPanel(cornerRadius: 16)
    }
}

struct PlaylistCard: View {
    let title: String
    let subtitle: String
    let symbol: String
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(LinearGradient(colors: [accent, SoulTheme.secondary], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: symbol)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 64, height: 64)

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 20, weight: .bold))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 14))
                        .lineLimit(1)
                        .foregroundStyle(SoulTheme.muted)
                }
                Spacer()
            }
            .foregroundStyle(SoulTheme.text)
            .padding(16)
            .glassPanel(cornerRadius: 16)
        }
        .buttonStyle(.plain)
    }
}
