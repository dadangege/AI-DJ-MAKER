import Foundation
import CommonCrypto
import CryptoKit

final class NeteaseService: @unchecked Sendable {
    private let projectDir: String
    private let cookiePath: String
    private let cacheDir: URL
    private let musicCacheDir: URL
    private let userAgent = "Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Safari/537.36 Chrome/91.0.4472.164 NeteaseMusicDesktop/2.10.2.200154"
    private let referer = "https://music.163.com/"
    private var loginKey = ""
    private var loginURL = ""

    init(projectDir: String) {
        self.projectDir = projectDir
        self.cookiePath = "\(NSHomeDirectory())/Library/Application Support/MiniMax TTS Studio/netease-cookie.txt"
        self.cacheDir = URL(fileURLWithPath: "\(NSHomeDirectory())/Library/Application Support/MiniMax TTS Studio/netease-cache", isDirectory: true)
        self.musicCacheDir = URL(fileURLWithPath: "\(NSHomeDirectory())/Library/Application Support/MiniMax TTS Studio/music-cache", isDirectory: true)
    }

    var hasCookie: Bool {
        guard let text = try? String(contentsOfFile: cookiePath, encoding: .utf8) else { return false }
        return text.contains("MUSIC_U=")
    }

    func startQrLogin() async throws -> QRLoginState {
        let response = try await postNeteaseEAPIJSON(
            "https://interface3.music.163.com/eapi/login/qrcode/unikey",
            payload: [
                "type": 1,
                "header": makeEAPIHeaderJSON()
            ],
            cookies: [:]
        )
        guard let key = response.json["unikey"] as? String, key.isEmpty == false else {
            throw NeteaseServiceError.message("没有拿到网易云二维码登录地址。")
        }

        loginKey = key
        loginURL = "https://music.163.com/login?codekey=\(key)"
        return QRLoginState(url: loginURL, status: "waiting", message: "等待扫码。", hasCookie: hasCookie)
    }

    func checkQrLogin() async throws -> QRLoginState {
        guard !loginKey.isEmpty else {
            return QRLoginState(status: hasCookie ? "success" : "idle", message: hasCookie ? "已保存登录态。" : "还没有二维码登录会话。", hasCookie: hasCookie)
        }

        let response = try await postNeteaseEAPIJSON(
            "https://interface3.music.163.com/eapi/login/qrcode/client/login",
            payload: [
                "key": loginKey,
                "type": 1,
                "header": makeEAPIHeaderJSON()
            ],
            cookies: [:]
        )
        let code = response.json["code"] as? Int ?? -1

        switch code {
        case 803:
            guard let musicU = extractCookie(named: "MUSIC_U", from: response.setCookie), musicU.isEmpty == false else {
                throw NeteaseServiceError.message("扫码成功但没有拿到 MUSIC_U。")
            }
            try saveCookie("MUSIC_U=\(musicU);os=pc;appver=8.9.70;")
            return QRLoginState(url: loginURL, status: "success", message: "登录成功。", hasCookie: true)
        case 802:
            return QRLoginState(url: loginURL, status: "scanned", message: "已扫码，请在手机上确认。", hasCookie: hasCookie)
        case 801:
            return QRLoginState(url: loginURL, status: "waiting", message: "等待扫码。", hasCookie: hasCookie)
        case 800:
            return QRLoginState(url: loginURL, status: "expired", message: "二维码已过期，请重新生成。", hasCookie: hasCookie)
        default:
            return QRLoginState(url: loginURL, status: "error", message: "登录状态未知：\(code)。", hasCookie: hasCookie)
        }
    }

    func loadUserLibrary() async throws -> NeteaseLibrary {
        let cookies = try readCookieMap()
        guard cookies["MUSIC_U"] != nil else {
            throw NeteaseServiceError.message("还没有网易云登录态，请先扫码登录。")
        }

        let profile = try await fetchNeteaseJSON("https://music.163.com/api/nuser/account/get", cookies: cookies)
        let profileDict = profile["profile"] as? [String: Any]
        let accountDict = profile["account"] as? [String: Any]
        let userID = profileDict?["userId"] ?? accountDict?["id"]
        guard let userID else {
            throw NeteaseServiceError.message("没有从网易云账号里拿到 userId。")
        }
        let account = NeteaseAccount(
            userID: "\(userID)",
            nickname: profileDict?["nickname"] as? String ?? "网易云用户",
            avatarURL: profileDict?["avatarUrl"] as? String ?? ""
        )

        let payload = try await fetchNeteaseJSON("https://music.163.com/api/user/playlist/?offset=0&limit=1001&uid=\(userID)", cookies: cookies)
        let playlists = payload["playlist"] as? [[String: Any]] ?? []
        let normalized: [NeteasePlaylist] = playlists.compactMap { item in
            guard let id = item["id"], let name = item["name"] as? String else { return nil }
            let creator = (item["creator"] as? [String: Any])?["nickname"] as? String ?? ""
            return NeteasePlaylist(
                id: "\(id)",
                name: name,
                trackCount: item["trackCount"] as? Int ?? 0,
                creator: creator,
                coverURL: item["coverImgUrl"] as? String ?? ""
            )
        }
        try saveCachedPlaylists(normalized)
        try saveCachedAccount(account)
        return NeteaseLibrary(account: account, playlists: normalized)
    }

    func loadCachedPlaylists() -> [NeteasePlaylist] {
        decodeCache([NeteasePlaylist].self, from: cacheDir.appendingPathComponent("playlists.json")) ?? []
    }

    func loadCachedAccount() -> NeteaseAccount {
        decodeCache(NeteaseAccount.self, from: cacheDir.appendingPathComponent("account.json")) ?? .guest
    }

    func loadPlaylistTracks(id: String, preferCache: Bool = true) async throws -> [SoulTrack] {
        let cachedURL = cacheDir.appendingPathComponent("playlist-\(sanitize(id)).json")
        if preferCache, let cached = decodeCache([SoulTrack].self, from: cachedURL), !cached.isEmpty {
            return cached
        }

        let cookies = try readCookieMap()
        guard cookies["MUSIC_U"] != nil else {
            throw NeteaseServiceError.message("还没有网易云登录态，请先扫码登录。")
        }

        let detail = try await postNeteaseFormJSON(
            "https://music.163.com/api/v6/playlist/detail",
            fields: ["id": id],
            cookies: cookies
        )
        let playlist = detail["playlist"] as? [String: Any] ?? [:]
        let trackIDs = (playlist["trackIds"] as? [[String: Any]] ?? [])
            .compactMap { $0["id"] }
            .map { "\($0)" }
        guard !trackIDs.isEmpty else {
            try saveCache([SoulTrack](), to: cachedURL)
            return []
        }

        var tracks: [SoulTrack] = []
        for batch in trackIDs.chunked(into: 100) {
            let c = batch.map { ["id": Int($0) ?? 0, "v": 0] }
            let cData = try JSONSerialization.data(withJSONObject: c)
            let cJSON = String(data: cData, encoding: .utf8) ?? "[]"
            let songsPayload = try await postNeteaseFormJSON(
                "https://interface3.music.163.com/api/v3/song/detail",
                fields: ["c": cJSON],
                cookies: cookies
            )
            let songs = songsPayload["songs"] as? [[String: Any]] ?? []
            tracks.append(contentsOf: normalizeSongs(songs))
        }

        try saveCache(tracks, to: cachedURL)
        return tracks
    }

    func cachedPlaylistTracks(id: String) -> [SoulTrack] {
        decodeCache([SoulTrack].self, from: cacheDir.appendingPathComponent("playlist-\(sanitize(id)).json")) ?? []
    }

    func prepareForLogin(progress: @escaping @Sendable (NeteaseInstallProgress) -> Void) async throws {
        progress(.init(value: 1, title: "网易云 Swift 登录已就绪", detail: "正在生成登录二维码。"))
    }

    func cachedAudioPath(for track: SoulTrack, quality: String = "lossless") -> URL? {
        let baseName = "\(sanitize(track.id))-\(sanitize(quality))"
        if let cached = findExistingAudio(in: musicCacheDir, baseName: baseName) {
            return cached
        }
        let legacyDir = URL(fileURLWithPath: "\(projectDir)/output/ai-dj/music-cache", isDirectory: true)
        return findExistingAudio(in: legacyDir, baseName: baseName)
    }

    func downloadAudio(for track: SoulTrack, quality: String = "lossless") async throws -> URL {
        if let cached = cachedAudioPath(for: track, quality: quality) {
            return cached
        }

        try FileManager.default.createDirectory(at: musicCacheDir, withIntermediateDirectories: true)

        let baseName = "\(sanitize(track.id))-\(sanitize(quality))"
        let stream = try await resolveAudioStream(for: track, quality: quality)
        let audioURL = stream.remoteURL
        let ext = audioURL.pathExtension.isEmpty ? "mp3" : audioURL.pathExtension
        let destination = musicCacheDir.appendingPathComponent("\(baseName).\(ext)")
        let (data, response) = try await URLSession.shared.data(from: audioURL)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw NeteaseServiceError.message("歌曲下载失败：HTTP \(http.statusCode)")
        }
        try data.write(to: destination, options: .atomic)
        return destination
    }

    func resolveAudioStream(for track: SoulTrack, quality: String = "lossless") async throws -> NeteaseAudioStream {
        try FileManager.default.createDirectory(at: musicCacheDir, withIntermediateDirectories: true)

        let cookies = try readCookieMap()
        let payload = try await songURLPayload(for: track, quality: quality, cookies: cookies)
        guard let audioURLString = findFirstURL(in: payload),
              let remoteURL = URL(string: audioURLString) else {
            throw NeteaseServiceError.message("没有拿到歌曲音频地址：\(track.artist) - \(track.title)。")
        }

        let ext = remoteURL.pathExtension.isEmpty ? "mp3" : remoteURL.pathExtension
        let cacheURL = musicCacheDir.appendingPathComponent("\(sanitize(track.id))-\(sanitize(quality)).\(ext)")
        return NeteaseAudioStream(remoteURL: remoteURL, cacheURL: cacheURL)
    }

    func lyricExcerpt(for track: SoulTrack) async throws -> String? {
        let cachedURL = cacheDir.appendingPathComponent("lyric-excerpt-\(sanitize(track.id)).txt")
        if let cached = try? String(contentsOf: cachedURL, encoding: .utf8),
           cached.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return cached
        }

        let payload = try await postNeteaseFormJSON(
            "https://interface3.music.163.com/api/song/lyric",
            fields: [
                "id": track.id,
                "cp": "false",
                "tv": "0",
                "lv": "0",
                "rv": "0",
                "kv": "0",
                "yv": "0",
                "ytv": "0",
                "yrv": "0"
            ],
            cookies: try readCookieMap()
        )

        let lyric = (value(for: ["lrc", "lyric"], in: payload) as? String)
            ?? (value(for: ["data", "lrc", "lyric"], in: payload) as? String)
            ?? ""
        let excerpt = makeLyricExcerpt(from: lyric)
        if let excerpt {
            try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            try? excerpt.write(to: cachedURL, atomically: true, encoding: .utf8)
        }
        return excerpt
    }

    func cacheAudio(from stream: NeteaseAudioStream) async throws -> URL {
        if FileManager.default.fileExists(atPath: stream.cacheURL.path) {
            return stream.cacheURL
        }

        try FileManager.default.createDirectory(at: stream.cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let (temporaryURL, response) = try await URLSession.shared.download(from: stream.remoteURL)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw NeteaseServiceError.message("后台缓存歌曲失败：HTTP \(http.statusCode)")
        }

        let partialURL = stream.cacheURL.appendingPathExtension("partial")
        try? FileManager.default.removeItem(at: partialURL)
        try? FileManager.default.removeItem(at: stream.cacheURL)
        try FileManager.default.moveItem(at: temporaryURL, to: partialURL)
        try FileManager.default.moveItem(at: partialURL, to: stream.cacheURL)
        return stream.cacheURL
    }

    private func saveCookie(_ cookie: String) throws {
        let url = URL(fileURLWithPath: cookiePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "\(cookie)\n".write(to: url, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cookiePath)
    }

    private func saveCachedPlaylists(_ playlists: [NeteasePlaylist]) throws {
        try saveCache(playlists, to: cacheDir.appendingPathComponent("playlists.json"))
    }

    private func saveCachedAccount(_ account: NeteaseAccount) throws {
        try saveCache(account, to: cacheDir.appendingPathComponent("account.json"))
    }

    private func saveCache<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(value)
        try data.write(to: url, options: .atomic)
    }

    private func decodeCache<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func normalizeSongs(_ songs: [[String: Any]]) -> [SoulTrack] {
        songs.compactMap { item in
            guard let id = item["id"] else { return nil }
            let title = item["name"] as? String ?? item["title"] as? String ?? ""
            guard !title.isEmpty else { return nil }
            let artist = normalizeArtist(item["artists"] ?? item["artist"] ?? item["ar"])
            let album = normalizeAlbum(item["album"] ?? item["al"])
            let coverURL = normalizeCoverURL(item["album"] ?? item["al"])
            let durationMs = item["duration"] as? Double ?? item["dt"] as? Double ?? 0
            let duration = durationMs > 1000 ? durationMs / 1000 : durationMs
            return SoulTrack(id: "\(id)", title: title, artist: artist, album: album, duration: duration, localPath: "", coverURL: coverURL)
        }
    }

    private func songURLPayload(for track: SoulTrack, quality: String, cookies: [String: String]) async throws -> [String: Any] {
        let id = Int(track.id) ?? 0
        let response = try await postNeteaseEAPIJSON(
            "https://interface3.music.163.com/eapi/song/enhance/player/url/v1",
            payload: [
                "ids": [id],
                "level": quality,
                "encodeType": "flac",
                "header": makeEAPIHeaderJSON()
            ],
            cookies: cookies
        )
        if let code = response.json["code"] as? Int, code != 200 {
            throw NeteaseServiceError.message("网易云音频接口返回 code=\(code)。")
        }
        return response.json
    }

    private func postNeteaseEAPIJSON(_ urlString: String, payload: [String: Any], cookies: [String: String]) async throws -> EAPIResponse {
        guard let url = URL(string: urlString) else {
            throw NeteaseServiceError.message("URL 无效：\(urlString)")
        }
        let payloadJSON = try compactJSONString(payload)
        let params = try encryptEAPIParams(url: url, payloadJSON: payloadJSON)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 35
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(referer, forHTTPHeaderField: "Referer")
        request.setValue(cookieHeader(cookies, includeDeviceDefaults: true), forHTTPHeaderField: "Cookie")
        request.httpBody = formBody(["params": params])

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw NeteaseServiceError.message("网易云 eapi 请求失败：HTTP \(http.statusCode)")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NeteaseServiceError.message("网易云 eapi 返回了非 JSON 内容。")
        }
        let setCookie = ((response as? HTTPURLResponse)?.allHeaderFields["Set-Cookie"] as? String)
            ?? ((response as? HTTPURLResponse)?.allHeaderFields["set-cookie"] as? String)
            ?? ""
        return EAPIResponse(json: json, setCookie: setCookie)
    }

    private func makeEAPIHeaderJSON() throws -> String {
        try compactJSONString([
            "os": "pc",
            "appver": "",
            "osver": "",
            "deviceId": "pyncm!",
            "requestId": "\(Int.random(in: 20_000_000..<30_000_000))"
        ])
    }

    private func encryptEAPIParams(url: URL, payloadJSON: String) throws -> String {
        let path = url.path.replacingOccurrences(of: "/eapi/", with: "/api/")
        let digest = md5Hex("nobody\(path)use\(payloadJSON)md5forencrypt")
        let text = "\(path)-36cd479b6b5-\(payloadJSON)-36cd479b6b5-\(digest)"
        guard let data = text.data(using: .utf8),
              let keyData = "e82ckenh8dichen8".data(using: .utf8) else {
            throw NeteaseServiceError.message("网易云 eapi 加密参数编码失败。")
        }
        return try aesECBEncryptHex(data: data, key: keyData)
    }

    private func aesECBEncryptHex(data: Data, key: Data) throws -> String {
        var output = Data(count: data.count + kCCBlockSizeAES128)
        let outputCapacity = output.count
        var outputLength = 0
        let status = output.withUnsafeMutableBytes { outputBytes in
            data.withUnsafeBytes { dataBytes in
                key.withUnsafeBytes { keyBytes in
                    CCCrypt(
                        CCOperation(kCCEncrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionECBMode | kCCOptionPKCS7Padding),
                        keyBytes.baseAddress,
                        key.count,
                        nil,
                        dataBytes.baseAddress,
                        data.count,
                        outputBytes.baseAddress,
                        outputCapacity,
                        &outputLength
                    )
                }
            }
        }
        guard status == kCCSuccess else {
            throw NeteaseServiceError.message("网易云 eapi AES 加密失败：\(status)。")
        }
        output.removeSubrange(outputLength..<output.count)
        return output.map { String(format: "%02x", $0) }.joined()
    }

    private func md5Hex(_ text: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func compactJSONString(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func postNeteaseFormJSON(_ urlString: String, fields: [String: String], cookies: [String: String]) async throws -> [String: Any] {
        guard let url = URL(string: urlString) else {
            throw NeteaseServiceError.message("URL 无效：\(urlString)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 35
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 Chrome/91.0 NeteaseMusicDesktop/2.10.2", forHTTPHeaderField: "User-Agent")
        request.setValue("https://music.163.com/", forHTTPHeaderField: "Referer")
        request.setValue(cookieHeader(cookies), forHTTPHeaderField: "Cookie")
        request.httpBody = formBody(fields)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw NeteaseServiceError.message("网易云请求失败：HTTP \(http.statusCode)")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NeteaseServiceError.message("网易云返回了非 JSON 内容。")
        }
        if let code = json["code"] as? Int, code != 200 {
            throw NeteaseServiceError.message("网易云接口返回 code=\(code)。")
        }
        return json
    }

    private func formBody(_ fields: [String: String]) -> Data {
        fields
            .map { key, value in
                "\(urlEncode(key))=\(urlEncode(value))"
            }
            .joined(separator: "&")
            .data(using: .utf8) ?? Data()
    }

    private func urlEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
    }

    private func cookieHeader(_ cookies: [String: String], includeDeviceDefaults: Bool = false) -> String {
        let defaults = includeDeviceDefaults
            ? ["os": "pc", "appver": "", "osver": "", "deviceId": "pyncm!"]
            : ["os": "pc", "appver": "8.9.70"]
        return defaults
            .merging(cookies) { _, new in new }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "; ")
    }

    private func extractCookie(named name: String, from header: String) -> String? {
        guard header.isEmpty == false else { return nil }
        for part in header.components(separatedBy: CharacterSet(charactersIn: ";,")) {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("\(name)=") else { continue }
            return String(trimmed.dropFirst(name.count + 1))
        }
        return nil
    }

    private func normalizeArtist(_ value: Any?) -> String {
        if let string = value as? String { return string }
        if let dict = value as? [String: Any] { return dict["name"] as? String ?? "" }
        if let array = value as? [[String: Any]] {
            return array.compactMap { $0["name"] as? String }.joined(separator: " / ")
        }
        if let array = value as? [String] {
            return array.joined(separator: " / ")
        }
        return ""
    }

    private func normalizeAlbum(_ value: Any?) -> String {
        if let string = value as? String { return string }
        if let dict = value as? [String: Any] { return dict["name"] as? String ?? "" }
        return ""
    }

    private func normalizeCoverURL(_ value: Any?) -> String? {
        guard let dict = value as? [String: Any] else { return nil }
        if let url = dict["picUrl"] as? String, !url.isEmpty { return url }
        if let url = dict["coverUrl"] as? String, !url.isEmpty { return url }
        if let picString = dict["pic_str"] as? String, !picString.isEmpty {
            return "https://p3.music.126.net/\(picString)/109951163999869100.jpg"
        }
        return nil
    }

    private func makeLyricExcerpt(from lyric: String) -> String? {
        let creditKeywords = ["作词", "作曲", "编曲", "制作人", "录音", "混音", "母带", "监制", "出品", "发行", "OP", "SP", "统筹", "企划"]
        var seen = Set<String>()
        let lines = lyric
            .components(separatedBy: .newlines)
            .map { line in
                line
                    .replacingOccurrences(of: #"\[[0-9:.]+\]"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { line in
                guard line.count >= 3 else { return false }
                guard creditKeywords.contains(where: { line.localizedCaseInsensitiveContains($0) }) == false else { return false }
                guard seen.contains(line) == false else { return false }
                seen.insert(line)
                return true
            }

        guard lines.isEmpty == false else { return nil }
        let selected = Array(lines.prefix(10))
        let text = selected.joined(separator: " / ")
        return String(text.prefix(180))
    }

    private func sanitize(_ value: String) -> String {
        value.map { character in
            character.isLetter || character.isNumber || character == "-" || character == "_" ? character : "_"
        }.reduce(into: "") { $0.append($1) }
    }

    private func readCookieMap() throws -> [String: String] {
        guard let text = try? String(contentsOfFile: cookiePath, encoding: .utf8) else { return [:] }
        var result: [String: String] = [:]
        for pair in text.split(separator: ";") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            result[parts[0].trimmingCharacters(in: .whitespacesAndNewlines)] = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }

    private func fetchNeteaseJSON(_ urlString: String, cookies: [String: String]) async throws -> [String: Any] {
        guard let url = URL(string: urlString) else {
            throw NeteaseServiceError.message("URL 无效：\(urlString)")
        }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/121.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("https://music.163.com/", forHTTPHeaderField: "Referer")
        let cookie = (["os": "pc", "appver": "8.9.70"].merging(cookies) { _, new in new })
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "; ")
        request.setValue(cookie, forHTTPHeaderField: "Cookie")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw NeteaseServiceError.message("网易云请求失败：HTTP \(http.statusCode)")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NeteaseServiceError.message("网易云返回了非 JSON 内容。")
        }
        return json
    }

    private func value(for path: [String], in payload: [String: Any]) -> Any? {
        var current: Any = payload
        for key in path {
            guard let dict = current as? [String: Any], let next = dict[key] else { return nil }
            current = next
        }
        return current
    }

    private func findFirstURL(in value: Any) -> String? {
        if let string = value as? String, string.hasPrefix("http") {
            return string
        }
        if let dict = value as? [String: Any] {
            if let direct = dict["url"] as? String, direct.hasPrefix("http") {
                return direct
            }
            for nested in dict.values {
                if let found = findFirstURL(in: nested) {
                    return found
                }
            }
        }
        if let array = value as? [Any] {
            for nested in array {
                if let found = findFirstURL(in: nested) {
                    return found
                }
            }
        }
        return nil
    }

    private func findExistingAudio(in directory: URL, baseName: String) -> URL? {
        let extensions = ["mp3", "flac", "m4a", "aac", "wav"]
        for ext in extensions {
            let url = directory.appendingPathComponent("\(baseName).\(ext)")
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }
}

struct NeteaseAudioStream: Sendable {
    let remoteURL: URL
    let cacheURL: URL
}

private struct EAPIResponse {
    let json: [String: Any]
    let setCookie: String
}

struct NeteaseInstallProgress: Sendable {
    let value: Double
    let title: String
    let detail: String
}

enum NeteaseServiceError: Error, LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let message): return message
        }
    }
}

private extension String {
    init(jsonEscaping value: String) {
        let data = try? JSONEncoder().encode(value)
        self = data.flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
