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

    static let fallbackPublic: [NeteasePlaylist] = [
        NeteasePlaylist(id: "3778678", name: "云音乐热歌榜", trackCount: 200, creator: "网易云音乐", coverURL: ""),
        NeteasePlaylist(id: "3779629", name: "云音乐新歌榜", trackCount: 100, creator: "网易云音乐", coverURL: ""),
        NeteasePlaylist(id: "19723756", name: "云音乐飙升榜", trackCount: 100, creator: "网易云音乐", coverURL: ""),
        NeteasePlaylist(id: "2884035", name: "网易原创歌曲榜", trackCount: 100, creator: "网易云音乐", coverURL: "")
    ]
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

struct EnvironmentContext: Equatable {
    let city: String
    let region: String
    let countryCode: String
    let latitude: Double
    let longitude: Double
    let temperatureC: Double?
    let weatherCode: Int?
    let weatherLabel: String?
    let cloudCover: Int?
    let updatedAt: Date

    var displayText: String {
        let cityText = city.isEmpty ? region : city
        let weatherParts = [
            temperatureC.map { "\(Int($0.rounded()))°C" },
            weatherLabel
        ].compactMap { $0 }.filter { !$0.isEmpty }
        guard weatherParts.isEmpty == false else { return cityText }
        return ([cityText] + weatherParts).filter { !$0.isEmpty }.joined(separator: " · ")
    }
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
        title: "还没有播放歌曲",
        artist: "选择歌单后双击歌曲开始播放",
        album: "",
        duration: 0,
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

struct TimedLyricLine: Identifiable, Equatable {
    let id: Int
    let time: Double
    let text: String
}

struct SongStorySourceCandidate: Equatable, Codable {
    let title: String
    let url: String
    let excerpt: String
    let site: String
    let qualityScore: Double
}

struct SongStoryInsight: Equatable, Codable {
    let trackID: String
    let title: String
    let artist: String
    let summary: String
    let angle: String
    let confidence: Double
    let sourceTitles: [String]
    let sourceURLs: [String]
    let updatedAt: Date

    var isUsable: Bool {
        confidence >= 0.72
            && summary.trimmingCharacters(in: .whitespacesAndNewlines).count >= 20
            && angle.trimmingCharacters(in: .whitespacesAndNewlines).count >= 8
            && sourceURLs.isEmpty == false
    }

    var promptText: String {
        [
            "可信度：\(String(format: "%.2f", confidence))",
            "摘要：\(summary)",
            "可用串场角度：\(angle)",
            "来源标题：\(sourceTitles.prefix(3).joined(separator: "；"))"
        ].joined(separator: "\n")
    }
}

enum AIHostMode: String, CaseIterable, Codable, Identifiable {
    case dj
    case midnight
    case curator
    case companion
    case party

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dj: return "夜店 DJ"
        case .midnight: return "午夜电台"
        case .curator: return "音乐推荐官"
        case .companion: return "情绪陪伴"
        case .party: return "轻松聊天"
        }
    }

    var promptInstruction: String {
        switch self {
        case .dj: return "像夜店或现场 DJ 一样控场，节奏强、短句、有气氛，但不要喊麦过度。"
        case .midnight: return "语气低沉、慢节奏、偏陪伴感，适合深夜收听，不要太兴奋。"
        case .curator: return "解释为什么推荐下一首歌，突出风格、情绪或听感理由。"
        case .companion: return "根据歌曲情绪做温柔过渡，照顾用户的感受，少一点资讯感。"
        case .party: return "像朋友陪听一样轻松自然，少一点表演感，适合日常流行歌单。"
        }
    }
}

struct AIHostProfile: Identifiable, Equatable {
    let id: String
    let name: String
    let tagline: String
    let voiceTag: String
    let persona: String
    let voiceDescription: String
    let suitableScenes: String
    let voiceID: String
    let speed: Double
    let pitch: Double
    let colors: [UInt]
    let symbol: String

    static let all: [AIHostProfile] = [
        AIHostProfile(
            id: "ava",
            name: "Ava",
            tagline: "都市夜班 DJ，擅长午夜陪伴和情绪化串场",
            voiceTag: "温柔女声 / 低沉午夜感",
            persona: "Ava 像城市凌晨还亮着的一盏灯，会把两首歌之间的空隙讲得柔软、有画面，也懂得留白。",
            voiceDescription: "语速偏慢，音高略低，适合温柔、沉稳、带一点夜色的中文电台口播。",
            suitableScenes: "午夜歌单、情绪歌单、独处、开车回家、下班后的放松时间。",
            voiceID: "Chinese (Mandarin)_News_Anchor",
            speed: 0.90,
            pitch: -1,
            colors: [0xA078FF, 0x4CD7F6],
            symbol: "moon.stars.fill"
        ),
        AIHostProfile(
            id: "leo",
            name: "Leo",
            tagline: "潮流音乐主播，适合流行歌单和轻松互动",
            voiceTag: "活力青年 / 轻松流行感",
            persona: "Leo 更像朋友里的音乐雷达，话不多但很会接住流行歌单的节奏，让每次切歌都轻松一点。",
            voiceDescription: "语速自然略快，音色清爽，适合流行、轻快、聊天感强的串场。",
            suitableScenes: "通勤、下午工作、流行歌单、朋友聚会前的热身。",
            voiceID: "Chinese (Mandarin)_Radio_Host",
            speed: 1.02,
            pitch: 0,
            colors: [0x4CD7F6, 0x7EF29D],
            symbol: "bolt.fill"
        ),
        AIHostProfile(
            id: "nora",
            name: "Nora",
            tagline: "温柔陪伴型主播，适合睡前电台和安静场景",
            voiceTag: "温柔女声 / 安静陪伴",
            persona: "Nora 会把音乐说得很近，像坐在旁边陪你听完这一首，不催促，也不打扰。",
            voiceDescription: "语速更慢，音高偏低，语气柔和，强调陪伴感和安全感。",
            suitableScenes: "睡前、阅读、雨天、安静工作、需要被温柔接住的时候。",
            voiceID: "Chinese (Mandarin)_Warm_Bestie",
            speed: 0.88,
            pitch: -1,
            colors: [0xFF8EC7, 0xA078FF],
            symbol: "heart.fill"
        ),
        AIHostProfile(
            id: "max",
            name: "Max",
            tagline: "高能派对 DJ，适合运动、开车、派对音乐",
            voiceTag: "磁性男声 / 高能派对感",
            persona: "Max 负责把能量抬起来，直接、明亮、有节拍感，适合让下一首歌更有登场气势。",
            voiceDescription: "语速更快，音高略高，表达更有推动力，适合节奏强和情绪高的歌单。",
            suitableScenes: "运动、开车、派对、电子/摇滚/高 BPM 歌单。",
            voiceID: "Chinese (Mandarin)_Male_Announcer",
            speed: 1.10,
            pitch: 1,
            colors: [0xEF3124, 0xFFD166],
            symbol: "flame.fill"
        )
    ]

    static func profile(for id: String) -> AIHostProfile {
        all.first { $0.id == id } ?? all[0]
    }
}
