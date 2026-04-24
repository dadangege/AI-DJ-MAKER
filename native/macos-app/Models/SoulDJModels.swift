import Foundation

enum SoulRoute: String, CaseIterable, Identifiable {
    case library = "Library"
    case discovery = "Discovery"
    case playlists = "Playlists"
    case curators = "Curators"
    case favorites = "Favorites"
    case settings = "Settings"
    case support = "Support"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .library: return "rectangle.stack.fill"
        case .discovery: return "safari.fill"
        case .playlists: return "music.note.list"
        case .curators: return "person.2.wave.2.fill"
        case .favorites: return "heart.fill"
        case .settings: return "gearshape.fill"
        case .support: return "questionmark.circle.fill"
        }
    }
}

struct NeteasePlaylist: Identifiable, Equatable, Codable {
    let id: String
    let name: String
    let trackCount: Int
    let creator: String
    let coverURL: String
}

struct NeteaseAccount: Equatable, Codable {
    let userID: String
    let nickname: String
    let avatarURL: String

    static let guest = NeteaseAccount(userID: "", nickname: "Your Soul", avatarURL: "")
}

struct NeteaseLibrary: Equatable, Codable {
    let account: NeteaseAccount
    let playlists: [NeteasePlaylist]
}

struct SoulTrack: Identifiable, Equatable, Codable {
    let id: String
    let title: String
    let artist: String
    let album: String
    let duration: Double
    let localPath: String
    let coverURL: String?

    static let placeholder = SoulTrack(
        id: "placeholder",
        title: "Innerbloom",
        artist: "RUFUS DU SOL",
        album: "Bloom",
        duration: 578,
        localPath: "",
        coverURL: nil
    )

    func withLocalPath(_ path: String) -> SoulTrack {
        SoulTrack(id: id, title: title, artist: artist, album: album, duration: duration, localPath: path, coverURL: coverURL)
    }
}

enum PlaybackMode: String, CaseIterable, Codable {
    case ordered
    case repeatAll
    case repeatOne
    case shuffle

    var title: String {
        switch self {
        case .ordered: return "顺序播放"
        case .repeatAll: return "列表循环"
        case .repeatOne: return "单曲循环"
        case .shuffle: return "随机播放"
        }
    }

    var symbolName: String {
        switch self {
        case .ordered: return "arrow.right"
        case .repeatAll: return "repeat"
        case .repeatOne: return "repeat.1"
        case .shuffle: return "shuffle"
        }
    }

    func nextMode() -> PlaybackMode {
        let modes = PlaybackMode.allCases
        guard let index = modes.firstIndex(of: self) else { return .ordered }
        return modes[(index + 1) % modes.count]
    }
}

enum AiDjModelStatus: String {
    case notConfigured
    case checking
    case connected
    case error

    var defaultMessage: String {
        switch self {
        case .notConfigured: return "DJ 还未生效，请先去设置里配置"
        case .checking: return "正在连接 AI DJ 模型..."
        case .connected: return "AI DJ 已生效，正在监听你的歌单衔接。"
        case .error: return "DJ 还未生效，请先去设置里配置"
        }
    }
}

struct QRLoginState: Equatable {
    var url: String = ""
    var status: String = "idle"
    var message: String = "点击扫码登录网易云。"
    var hasCookie: Bool = false
}

struct InstallProgressState: Equatable {
    var isActive = false
    var progress: Double = 0
    var title = ""
    var detail = ""
}

struct DJLogEntry: Identifiable {
    let id = UUID()
    let time = Date()
    let level: String
    let message: String
}
