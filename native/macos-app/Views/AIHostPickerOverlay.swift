import SwiftUI

struct AIHostPickerOverlay: View {
    @ObservedObject var store: SoulDJStore
    @State private var selectedHostID: String
    @State private var selectedMode: AIHostMode

    init(store: SoulDJStore) {
        self.store = store
        _selectedHostID = State(initialValue: store.configuredHost?.id ?? AIHostProfile.all[0].id)
        _selectedMode = State(initialValue: store.configuredHostMode ?? .dj)
    }

    private var selectedHost: AIHostProfile {
        AIHostProfile.profile(for: selectedHostID)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.66)
                .ignoresSafeArea()
                .onTapGesture {
                    store.closeHostPicker()
                }

            VStack(alignment: .leading, spacing: 22) {
                header

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        hostGrid
                        detailSection
                        modeSection
                    }
                    .padding(.bottom, 4)
                }
            }
            .padding(28)
            .frame(width: 940, height: 650, alignment: .topLeading)
            .background(.ultraThinMaterial.opacity(0.92), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.12)))
            .shadow(color: SoulTheme.primaryContainer.opacity(0.24), radius: 42, x: 0, y: 20)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text("选择你的 AI 主播")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                Text("不同主播有不同声音、性格和播报风格")
                    .font(.system(size: 15))
                    .foregroundStyle(SoulTheme.muted)
            }
            Spacer()
            Button {
                store.closeHostPicker()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(SoulIconButtonStyle())
        }
        .foregroundStyle(SoulTheme.text)
    }

    private var hostGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4), spacing: 14) {
            ForEach(AIHostProfile.all) { host in
                AIHostCard(host: host, selected: host.id == selectedHostID) {
                    selectedHostID = host.id
                }
            }
        }
    }

    private var detailSection: some View {
        HStack(alignment: .top, spacing: 20) {
            AIHostAvatar(host: selectedHost, size: 118)

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(selectedHost.name)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                        Text(selectedHost.tagline)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(SoulTheme.secondary)
                    }
                    Spacer()
                    Text(selectedHost.voiceTag)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(SoulTheme.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(SoulTheme.primary.opacity(0.10), in: Capsule())
                        .overlay(Capsule().stroke(SoulTheme.primary.opacity(0.25)))
                }

                Text("当前选择会先在这里预览，点击“保存并生效”后才会用于实际串场和 TTS 声音。")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SoulTheme.muted)

                VStack(alignment: .leading, spacing: 9) {
                    DetailText(title: "主播人设", text: selectedHost.persona)
                    DetailText(title: "声音风格", text: selectedHost.voiceDescription)
                    DetailText(title: "适合场景", text: selectedHost.suitableScenes)
                }

                HStack(spacing: 12) {
                    Button {
                        store.previewHost(host: selectedHost, mode: selectedMode)
                    } label: {
                        Label(store.hostPreviewing ? "试听生成中" : "试听声音", systemImage: store.hostPreviewing ? "hourglass" : "speaker.wave.2.fill")
                    }
                    .buttonStyle(SoulPillButtonStyle(kind: .ghost))
                    .disabled(store.hostPreviewing)

                    Button {
                        store.saveHostSelection(host: selectedHost, mode: selectedMode)
                    } label: {
                        Label("保存并生效", systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(SoulPillButtonStyle(kind: .primary))

                    if store.hostPickerMessage.isEmpty == false {
                        Text(store.hostPickerMessage)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(SoulTheme.muted)
                            .lineLimit(1)
                    }
                }
            }
        }
        .foregroundStyle(SoulTheme.text)
        .padding(18)
        .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.08)))
    }

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("播报模式")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(SoulTheme.text)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(AIHostMode.allCases) { mode in
                    Button {
                        selectedMode = mode
                    } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(mode.title)
                                .font(.system(size: 14, weight: .bold))
                            Text(mode.promptInstruction)
                                .font(.system(size: 11))
                                .foregroundStyle(SoulTheme.muted)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(13)
                        .background(mode == selectedMode ? SoulTheme.secondary.opacity(0.16) : .white.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(mode == selectedMode ? SoulTheme.secondary.opacity(0.85) : .white.opacity(0.08), lineWidth: mode == selectedMode ? 1.5 : 1))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(mode == selectedMode ? SoulTheme.text : SoulTheme.muted)
                }
            }
        }
    }
}

struct AIHostCard: View {
    let host: AIHostProfile
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                AIHostAvatar(host: host, size: 72)
                Text(host.name)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Text(host.tagline)
                    .font(.system(size: 12))
                    .foregroundStyle(SoulTheme.muted)
                    .lineLimit(2)
                Text(host.voiceTag)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(selected ? SoulTheme.secondary : SoulTheme.primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(15)
            .background(selected ? SoulTheme.primaryContainer.opacity(0.14) : .black.opacity(0.24), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? SoulTheme.secondary.opacity(0.90) : .white.opacity(0.08), lineWidth: selected ? 1.7 : 1))
            .shadow(color: selected ? SoulTheme.secondary.opacity(0.24) : .clear, radius: 18)
        }
        .buttonStyle(.plain)
        .foregroundStyle(SoulTheme.text)
    }
}

struct AIHostAvatar: View {
    let host: AIHostProfile
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: host.colors.map { Color(hex: $0) }, startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle()
                .stroke(.white.opacity(0.20), lineWidth: 1)
            Image(systemName: host.symbol)
                .font(.system(size: size * 0.34, weight: .bold))
                .foregroundStyle(.white.opacity(0.92))
                .shadow(color: .black.opacity(0.34), radius: 8)
        }
        .frame(width: size, height: size)
        .shadow(color: Color(hex: host.colors.first ?? 0xA078FF).opacity(0.35), radius: 14)
    }
}

struct UnsetAIHostAvatar: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.07))
            Circle()
                .stroke(.white.opacity(0.16), lineWidth: 1)
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(SoulTheme.muted)
        }
        .frame(width: size, height: size)
    }
}

struct DetailText: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(SoulTheme.muted)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(SoulTheme.text.opacity(0.88))
                .lineLimit(2)
        }
    }
}
