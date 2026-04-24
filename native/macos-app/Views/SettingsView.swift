import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: SoulDJStore
    @ObservedObject private var settings: AppSettingsStore

    init(store: SoulDJStore) {
        self.store = store
        self.settings = store.settings
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Settings")
                        .font(.system(size: 44, weight: .heavy, design: .rounded))
                    Text("Configure your AI Host and system preferences.")
                        .font(.system(size: 18))
                        .foregroundStyle(SoulTheme.muted)
                }
                .foregroundStyle(SoulTheme.text)

                HStack(alignment: .top, spacing: 32) {
                    SettingsSidebar()

                    VStack(spacing: 28) {
                        SettingsSection(title: "AI Model", subtitle: "Configure the core intelligence driving your host.", symbol: "cpu.fill", accent: SoulTheme.primary) {
                            VStack(spacing: 16) {
                                SoulTextField(title: "API Key", text: $settings.apiKey, secure: true)
                                SoulTextField(title: "Base URL", text: $settings.baseURL)
                                SoulTextField(title: "Text Model", text: $settings.textModel)
                                SoulTextField(title: "TTS Model", text: $settings.ttsModel)
                            }
                        }

                        SettingsSection(title: "AI Voice", subtitle: "Customize the personality and tone of the broadcast.", symbol: "person.wave.2.fill", accent: SoulTheme.secondary) {
                            VStack(spacing: 18) {
                                SoulTextField(title: "Voice ID", text: $settings.voiceID)
                                SliderRow(title: "Pitch", value: $settings.pitch, range: -6...6, suffix: "")
                                SliderRow(title: "Speed", value: $settings.speed, range: 0.5...1.5, suffix: "x")
                            }
                        }

                        SettingsSection(title: "Advanced Tools", subtitle: "旧 TTS 试听和系统监听模式会作为工具入口保留。", symbol: "wrench.and.screwdriver.fill", accent: SoulTheme.primaryContainer) {
                            HStack(spacing: 12) {
                                ToolChip(title: "Manual TTS", symbol: "waveform")
                                ToolChip(title: "Now Playing Monitor", symbol: "dot.radiowaves.left.and.right")
                                ToolChip(title: "System Ducking", symbol: "speaker.wave.2.fill")
                            }
                        }

                        HStack {
                            Spacer()
                            Button("Save Changes") {
                                store.saveSettings()
                            }
                            .buttonStyle(SoulPillButtonStyle(kind: .primary))
                        }
                    }
                }
            }
            .padding(32)
            .frame(maxWidth: 1120, alignment: .leading)
        }
    }
}

struct SettingsSidebar: View {
    private let items = ["AI Model", "AI Voice", "General Audio", "Account"]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(items, id: \.self) { item in
                HStack {
                    Text(item)
                    Spacer()
                    if item == "AI Model" {
                        Image(systemName: "chevron.right")
                    }
                }
                .font(.system(size: 14, weight: item == "AI Model" ? .semibold : .regular))
                .foregroundStyle(item == "AI Model" ? SoulTheme.primary : SoulTheme.muted)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(item == "AI Model" ? .white.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(14)
        .frame(width: 280)
        .glassPanel(cornerRadius: 16)
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    let subtitle: String
    let symbol: String
    let accent: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol)
                    .foregroundStyle(accent)
                    .font(.system(size: 22))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 24, weight: .bold))
                    Text(subtitle)
                        .font(.system(size: 14))
                        .foregroundStyle(SoulTheme.muted)
                }
            }
            content
        }
        .foregroundStyle(SoulTheme.text)
        .padding(26)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: 16)
    }
}

struct SoulTextField: View {
    let title: String
    @Binding var text: String
    var secure = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(SoulTheme.muted)
            Group {
                if secure {
                    SecureField("", text: $text)
                } else {
                    TextField("", text: $text)
                }
            }
            .textFieldStyle(.plain)
            .font(.system(size: 15))
            .padding(.horizontal, 14)
            .frame(height: 46)
            .background(SoulTheme.surfaceHigh.opacity(0.86), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(.white.opacity(0.10)))
        }
    }
}

struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let suffix: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title.uppercased())
                    .font(.system(size: 12, weight: .bold))
                Spacer()
                Text("\(value, specifier: "%.2g")\(suffix)")
                    .font(.system(size: 12))
            }
            .foregroundStyle(SoulTheme.muted)
            Slider(value: $value, in: range)
                .tint(SoulTheme.secondary)
        }
    }
}

struct ToolChip: View {
    let title: String
    let symbol: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
            Text(title)
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(SoulTheme.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(SoulTheme.secondary.opacity(0.10), in: Capsule())
        .overlay(Capsule().stroke(SoulTheme.secondary.opacity(0.20)))
    }
}
