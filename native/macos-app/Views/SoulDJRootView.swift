import SwiftUI

struct SoulDJRootView: View {
    @ObservedObject var store: SoulDJStore

    var body: some View {
        ZStack {
            SoulBackground()

            VStack(spacing: 0) {
                TopBar(store: store)

                HStack(spacing: 0) {
                    SidebarView(store: store)

                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()

                    AIHostPanel(store: store)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .layoutPriority(1)

                PlayerBar(store: store)
            }

            if store.showLoginSheet {
                LoginOverlay(store: store)
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var content: some View {
        switch store.selectedRoute {
        case .settings:
            SettingsView(store: store)
        case .playlists:
            PlaylistDetailView(store: store)
        default:
            DashboardView(store: store)
        }
    }
}

struct SoulBackground: View {
    var body: some View {
        ZStack {
            SoulTheme.background
            RadialGradient(colors: [SoulTheme.primaryContainer.opacity(0.16), .clear], center: .topLeading, startRadius: 20, endRadius: 520)
            RadialGradient(colors: [SoulTheme.secondary.opacity(0.10), .clear], center: .bottomTrailing, startRadius: 30, endRadius: 560)
            LinearGradient(colors: [.black.opacity(0.20), .clear, .black.opacity(0.36)], startPoint: .leading, endPoint: .trailing)
        }
        .ignoresSafeArea()
    }
}

struct TopBar: View {
    @ObservedObject var store: SoulDJStore

    var body: some View {
        HStack {
            Text("Soul DJ")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(LinearGradient(colors: [SoulTheme.primaryContainer, SoulTheme.secondary], startPoint: .leading, endPoint: .trailing))

            Spacer()

            Button {
                store.handleLoginButton()
            } label: {
                Label(store.loginButtonTitle, systemImage: store.isLoggedIn ? "checkmark.circle.fill" : "qrcode")
            }
            .buttonStyle(SoulPillButtonStyle(kind: .primary))

            Button {
                store.selectedRoute = .settings
            } label: {
                Image(systemName: "gearshape.fill")
            }
            .buttonStyle(SoulIconButtonStyle())

            Image(systemName: "person.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(SoulTheme.muted)
        }
        .padding(.horizontal, 32)
        .frame(height: 52)
        .background(.black.opacity(0.46))
        .overlay(Rectangle().fill(.white.opacity(0.08)).frame(height: 1), alignment: .bottom)
    }
}

struct SidebarView: View {
    @ObservedObject var store: SoulDJStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SidebarIdentity(store: store)
            .padding(.horizontal, 28)
            .padding(.top, 42)
            .padding(.bottom, 34)

            VStack(spacing: 8) {
                ForEach([SoulRoute.library, .discovery, .playlists, .curators, .favorites]) { route in
                    SidebarRow(route: route, selected: store.selectedRoute == route) {
                        store.selectedRoute = route
                    }
                }
            }

            Spacer()

            Divider().overlay(.white.opacity(0.08)).padding(.horizontal, 20)

            VStack(spacing: 8) {
                SidebarRow(route: .settings, selected: store.selectedRoute == .settings) {
                    store.selectedRoute = .settings
                }
                SidebarRow(route: .support, selected: store.selectedRoute == .support) {
                    store.selectedRoute = .support
                }
            }
            .padding(.bottom, 34)
        }
        .frame(width: 240)
        .background(.black.opacity(0.42))
        .overlay(Rectangle().fill(.white.opacity(0.08)).frame(width: 1), alignment: .trailing)
    }
}

struct SidebarIdentity: View {
    @ObservedObject var store: SoulDJStore

    var body: some View {
        if store.selectedRoute == .playlists {
            Button {
                store.goHome()
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(.white.opacity(0.07))
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(SoulTheme.primary)
                    }
                    .frame(width: 46, height: 46)
                    .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 1))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("返回首页")
                            .font(.system(size: 21, weight: .bold))
                            .foregroundStyle(SoulTheme.text)
                        Text(store.selectedPlaylist?.name ?? "Library")
                            .font(.system(size: 13))
                            .foregroundStyle(SoulTheme.muted)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)
        } else {
            HStack(spacing: 12) {
                AccountAvatar(account: store.account, loggedIn: store.isLoggedIn)
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.isLoggedIn ? store.account.nickname : "Your Soul")
                        .font(.system(size: 21, weight: .bold))
                        .foregroundStyle(SoulTheme.text)
                        .lineLimit(1)
                    Text(store.isLoggedIn ? "网易云已登录" : "Local Listener")
                        .font(.system(size: 13))
                        .foregroundStyle(SoulTheme.muted)
                        .lineLimit(1)
                }
            }
        }
    }
}

struct AccountAvatar: View {
    let account: NeteaseAccount
    let loggedIn: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [SoulTheme.primaryContainer, SoulTheme.secondary], startPoint: .topLeading, endPoint: .bottomTrailing))

            if loggedIn, let url = URL(string: account.avatarURL), !account.avatarURL.isEmpty {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        Image(systemName: "person.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white.opacity(0.86))
                    }
                }
                .clipShape(Circle())
            } else {
                Image(systemName: loggedIn ? "person.fill" : "waveform")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white.opacity(0.86))
            }
        }
        .frame(width: 46, height: 46)
        .overlay(Circle().stroke(.white.opacity(0.14), lineWidth: 1))
        .shadow(color: SoulTheme.primaryContainer.opacity(loggedIn ? 0.28 : 0.12), radius: 12)
    }
}

struct SidebarRow: View {
    let route: SoulRoute
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: route.symbolName)
                    .frame(width: 24)
                Text(route.rawValue)
                    .font(.system(size: 15, weight: selected ? .semibold : .regular))
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .foregroundStyle(selected ? SoulTheme.primary : SoulTheme.muted)
            .background(selected ? .white.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(alignment: .trailing) {
                if selected {
                    Capsule().fill(SoulTheme.primaryContainer).frame(width: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
    }
}

enum SoulButtonKind {
    case primary
    case ghost
}

struct SoulPillButtonStyle: ButtonStyle {
    let kind: SoulButtonKind

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold))
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .foregroundStyle(kind == .primary ? Color(hex: 0x23005C) : SoulTheme.text)
            .background(background, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(kind == .primary ? 0 : 0.12), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }

    private var background: AnyShapeStyle {
        switch kind {
        case .primary:
            AnyShapeStyle(LinearGradient(colors: [SoulTheme.primary, SoulTheme.primaryContainer], startPoint: .topLeading, endPoint: .bottomTrailing))
        case .ghost:
            AnyShapeStyle(Color.white.opacity(0.06))
        }
    }
}

struct SoulIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(SoulTheme.muted)
            .frame(width: 34, height: 34)
            .background(configuration.isPressed ? .white.opacity(0.10) : .clear, in: Circle())
    }
}
