import SwiftUI

struct LoginOverlay: View {
    @ObservedObject var store: SoulDJStore

    var body: some View {
        ZStack {
            Color.black.opacity(0.62)
                .ignoresSafeArea()
                .onTapGesture { store.showLoginSheet = false }

            VStack(spacing: 28) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [SoulTheme.primaryContainer, SoulTheme.secondary], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 64, height: 64)
                        .shadow(color: SoulTheme.primaryContainer.opacity(0.35), radius: 22)
                    Image(systemName: "waveform")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Color(hex: 0x23005C))
                }

                VStack(spacing: 8) {
                    Text("Soul DJ")
                        .font(.system(size: 42, weight: .heavy, design: .rounded))
                        .foregroundStyle(LinearGradient(colors: [SoulTheme.primary, SoulTheme.secondary], startPoint: .leading, endPoint: .trailing))
                    Text("SECURE AUTHENTICATION")
                        .font(.system(size: 12, weight: .bold))
                        .tracking(2.4)
                        .foregroundStyle(SoulTheme.muted)
                }

                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.white)
                        .shadow(color: SoulTheme.primary.opacity(0.30), radius: 26)
                    if store.qrLogin.url.isEmpty {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .controlSize(.large)
                    } else {
                        Image(nsImage: QRCodeRenderer.image(from: store.qrLogin.url, size: 220))
                            .interpolation(.none)
                    }
                }
                .frame(width: 252, height: 252)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(SoulTheme.primary, lineWidth: 2))

                Text(store.qrLogin.message)
                    .font(.system(size: 16))
                    .foregroundStyle(SoulTheme.text)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)

                if store.installProgress.isActive {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Text(store.installProgress.title)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(SoulTheme.text)
                            Spacer()
                            Text("\(Int(store.installProgress.progress * 100))%")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(SoulTheme.secondary)
                        }
                        ProgressView(value: store.installProgress.progress)
                            .progressViewStyle(.linear)
                            .tint(SoulTheme.secondary)
                        Text(store.installProgress.detail)
                            .font(.system(size: 12))
                            .foregroundStyle(SoulTheme.muted)
                            .lineLimit(2)
                    }
                    .padding(14)
                    .frame(maxWidth: 340)
                    .glassPanel(cornerRadius: 12, opacity: 0.38)
                }

                HStack(spacing: 14) {
                    Button("Cancel") {
                        store.showLoginSheet = false
                    }
                    .buttonStyle(SoulPillButtonStyle(kind: .ghost))

                    Button("重新生成") {
                        Task { await store.startLogin() }
                    }
                    .buttonStyle(SoulPillButtonStyle(kind: .primary))
                }
            }
            .padding(48)
            .frame(width: 480)
            .glassPanel(cornerRadius: 22, opacity: 0.72)
        }
    }
}
