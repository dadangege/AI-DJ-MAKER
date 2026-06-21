import Foundation

final class SongStoryService: @unchecked Sendable {
    private let settings: AppSettingsStore
    private let cacheDir = URL(fileURLWithPath: "\(NSHomeDirectory())/Library/Application Support/MiniMax TTS Studio/song-story-cache", isDirectory: true)
    private let cacheTTL: TimeInterval = 30 * 24 * 60 * 60
    private let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    init(settings: AppSettingsStore) {
        self.settings = settings
    }

    func cachedInsight(for track: SoulTrack) -> SongStoryInsight? {
        let url = cacheURL(for: track)
        guard let data = try? Data(contentsOf: url),
              let insight = try? JSONDecoder().decode(SongStoryInsight.self, from: data),
              Date().timeIntervalSince(insight.updatedAt) < cacheTTL else {
            return nil
        }
        return insight.isUsable ? insight : nil
    }

    func saveInsight(_ insight: SongStoryInsight, for track: SoulTrack) throws {
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(insight)
        try data.write(to: cacheURL(for: track), options: .atomic)
    }

    func fetchSourceCandidates(for track: SoulTrack) async throws -> [SongStorySourceCandidate] {
        guard shouldSearch(track) else { return [] }

        var candidates: [SongStorySourceCandidate] = []
        var seenURLs = Set<String>()
        let queries = storyQueries(for: track)

        for query in queries where candidates.count < 5 {
            let results = await searchResults(query: query)
            for result in results where candidates.count < 5 {
                guard let normalizedURL = normalizeDuckDuckGoURL(result.url),
                      seenURLs.insert(normalizedURL.absoluteString).inserted else {
                    continue
                }

                guard shouldUseResultURL(normalizedURL, snippet: result.snippet) else {
                    continue
                }
                let page = (try? await fetchReadablePage(normalizedURL)) ?? ""
                let combined = [result.snippet, page].filter { !$0.isEmpty }.joined(separator: " ")
                guard let excerpt = relevantExcerpt(from: combined, track: track),
                      excerpt.count >= 120 else {
                    continue
                }

                let title = result.title.isEmpty ? normalizedURL.host ?? normalizedURL.absoluteString : result.title
                let score = qualityScore(title: title, url: normalizedURL, excerpt: excerpt, track: track)
                guard score >= 0.45 else { continue }
                candidates.append(
                    SongStorySourceCandidate(
                        title: title,
                        url: normalizedURL.absoluteString,
                        excerpt: String(excerpt.prefix(1200)),
                        site: normalizedURL.host ?? "",
                        qualityScore: score
                    )
                )
            }
        }

        return candidates.sorted { $0.qualityScore > $1.qualityScore }
    }

    func storyQueries(for track: SoulTrack) -> [String] {
        let title = track.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = track.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let album = track.album.trimmingCharacters(in: .whitespacesAndNewlines)
        let identity = [artist, title, album].filter { !$0.isEmpty }.joined(separator: " ")
        return [
            "\(identity) 创作背景 歌曲故事",
            "\(identity) 采访 专辑 故事",
            "\(identity) 发行 背后故事",
            "\"\(title)\" \"\(artist)\" 创作背景",
            "\"\(title)\" \"\(artist)\" 采访 专辑"
        ]
    }

    private func searchResults(query: String) async -> [SearchResult] {
        if tavilyAPIKey.isEmpty == false {
            do {
                let results = try await searchTavily(query: query)
                if results.isEmpty == false { return results }
            } catch {
                print("Tavily search failed: \(error.localizedDescription)")
            }
        }
        do {
            return try await searchDuckDuckGo(query: query)
        } catch {
            return []
        }
    }

    private func shouldSearch(_ track: SoulTrack) -> Bool {
        let title = track.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = track.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard track.id != SoulTrack.placeholder.id,
              title.count >= 2,
              artist.count >= 2,
              track.duration >= 60 else {
            return false
        }

        let noisyTokens = ["未知", "unknown", "伴奏", "铃声", "翻唱", "cover", "remix", "dj版", "片段"]
        let searchable = "\(title) \(artist)".lowercased()
        return noisyTokens.contains { searchable.contains($0) } == false
    }

    private func searchDuckDuckGo(query: String) async throws -> [SearchResult] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://duckduckgo.com/html/?q=\(encoded)") else {
            return []
        }
        let html = try await fetchText(url)
        return parseDuckDuckGoResults(html)
    }

    private func searchTavily(query: String) async throws -> [SearchResult] {
        guard let url = URL(string: "https://api.tavily.com/search") else { return [] }
        let payload: [String: Any] = [
            "query": query,
            "topic": "general",
            "search_depth": "basic",
            "max_results": 6,
            "include_answer": false,
            "include_raw_content": "text",
            "include_images": false,
            "exclude_domains": [
                "music.163.com",
                "y.qq.com",
                "open.spotify.com",
                "music.apple.com",
                "kugou.com",
                "kuwo.cn",
                "youtube.com",
                "genius.com"
            ]
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(tavilyAPIKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw SongStoryServiceError.message("Tavily 请求失败：HTTP \(http.statusCode) \(text)")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        let results = json["results"] as? [[String: Any]] ?? []
        return results.compactMap { item in
            guard let url = item["url"] as? String, url.isEmpty == false else { return nil }
            let title = item["title"] as? String ?? ""
            let content = item["content"] as? String ?? ""
            let raw = item["raw_content"] as? String ?? ""
            let snippet = [content, raw].filter { !$0.isEmpty }.joined(separator: " ")
            return SearchResult(title: title, url: url, snippet: snippet)
        }
    }

    private func fetchReadablePage(_ url: URL) async throws -> String {
        let html = try await fetchText(url)
        return cleanHTML(html)
    }

    private func fetchText(_ url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw SongStoryServiceError.message("网页请求失败：HTTP \(http.statusCode)")
        }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
    }

    private func parseDuckDuckGoResults(_ html: String) -> [SearchResult] {
        let pattern = #"<a[^>]+class="[^"]*result__a[^"]*"[^>]+href="([^"]+)"[^>]*>([\s\S]*?)</a>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let ns = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: ns.length))
        return matches.prefix(8).compactMap { match in
            guard match.numberOfRanges >= 3 else { return nil }
            let rawURL = ns.substring(with: match.range(at: 1))
            let rawTitle = ns.substring(with: match.range(at: 2))
            let tailStart = min(match.range.location + match.range.length, ns.length)
            let tailLength = min(1400, max(0, ns.length - tailStart))
            let tail = ns.substring(with: NSRange(location: tailStart, length: tailLength))
            let snippet = extractSnippet(from: tail)
            return SearchResult(
                title: cleanHTML(rawTitle),
                url: decodeHTMLEntities(rawURL),
                snippet: snippet
            )
        }
    }

    private func extractSnippet(from html: String) -> String {
        let pattern = #"<a[^>]+class="[^"]*result__snippet[^"]*"[^>]*>([\s\S]*?)</a>|<div[^>]+class="[^"]*result__snippet[^"]*"[^>]*>([\s\S]*?)</div>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: (html as NSString).length)) else {
            return ""
        }
        let ns = html as NSString
        for index in 1..<match.numberOfRanges where match.range(at: index).location != NSNotFound {
            return cleanHTML(ns.substring(with: match.range(at: index)))
        }
        return ""
    }

    private func normalizeDuckDuckGoURL(_ raw: String) -> URL? {
        let decoded = decodeHTMLEntities(raw)
        if decoded.hasPrefix("//") {
            return normalizeDuckDuckGoURL("https:\(decoded)")
        }
        guard let url = URL(string: decoded) else { return nil }
        if url.host?.contains("duckduckgo.com") == true,
           url.path == "/l/",
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let uddg = components.queryItems?.first(where: { $0.name == "uddg" })?.value {
            return URL(string: uddg)
        }
        return url
    }

    private func shouldUseResultURL(_ url: URL, snippet: String) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        let blockedHosts = [
            "music.163.com", "y.qq.com", "open.spotify.com", "music.apple.com",
            "kugou.com", "kuwo.cn", "douyin.com",
            "soundcloud.com", "last.fm", "genius.com"
        ]
        if blockedHosts.contains(where: { host.contains($0) }) { return false }
        if (host.contains("bilibili.com") || host.contains("youtube.com")) && hasStorySignal(snippet) == false {
            return false
        }
        let blockedPathTokens = ["lyrics", "download", "mp3", "chord", "karaoke"]
        let path = url.path.lowercased()
        return blockedPathTokens.contains { path.contains($0) } == false
    }

    private func hasStorySignal(_ text: String) -> Bool {
        let lower = text.lowercased()
        return ["创作", "背景", "采访", "专辑", "发行", "故事", "抄袭", "争议", "改编", "原唱", "收录", "灵感", "幕后"].contains { lower.contains($0) }
    }

    private func relevantExcerpt(from text: String, track: SoulTrack) -> String? {
        let clean = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        guard clean.count >= 120 else { return nil }
        let lower = clean.lowercased()
        let keys = [track.title, track.artist, "创作", "背景", "采访", "专辑", "发行", "收录", "灵感"]
            .map { $0.lowercased() }
            .filter { !$0.isEmpty }
        guard keys.contains(where: { lower.contains($0) }) else { return nil }

        let titleRange = lower.range(of: track.title.lowercased())
        let artistRange = lower.range(of: track.artist.lowercased())
        let range = titleRange ?? artistRange
        guard let range else {
            return String(clean.prefix(900))
        }
        let start = clean.index(range.lowerBound, offsetBy: -min(260, clean.distance(from: clean.startIndex, to: range.lowerBound)), limitedBy: clean.startIndex) ?? clean.startIndex
        let end = clean.index(range.upperBound, offsetBy: min(900, clean.distance(from: range.upperBound, to: clean.endIndex)), limitedBy: clean.endIndex) ?? clean.endIndex
        return String(clean[start..<end])
    }

    private func qualityScore(title: String, url: URL, excerpt: String, track: SoulTrack) -> Double {
        let host = url.host?.lowercased() ?? ""
        let text = "\(title) \(excerpt)".lowercased()
        var score = 0.35
        if text.contains(track.title.lowercased()) { score += 0.18 }
        if text.contains(track.artist.lowercased()) { score += 0.16 }
        if ["创作", "背景", "采访", "专辑", "发行", "灵感", "收录"].contains(where: { text.contains($0) }) { score += 0.2 }
        if ["wikipedia.org", "baike", "billboard.com", "pitchfork.com", "rollingstone.com", "npr.org", "thepaper.cn", "qq.com", "sina.com.cn", "sohu.com"].contains(where: { host.contains($0) }) { score += 0.18 }
        if excerpt.count > 500 { score += 0.08 }
        return min(1, score)
    }

    private func cleanHTML(_ html: String) -> String {
        var text = html
        text = text.replacingOccurrences(of: #"(?is)<script[\s\S]*?</script>"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?is)<style[\s\S]*?</style>"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?is)<noscript[\s\S]*?</noscript>"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        text = decodeHTMLEntities(text)
        text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func decodeHTMLEntities(_ text: String) -> String {
        text.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }

    private func cacheURL(for track: SoulTrack) -> URL {
        cacheDir.appendingPathComponent("story-\(sanitize(track.id)).json")
    }

    private var tavilyAPIKey: String {
        settings.tavilyAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sanitize(_ value: String) -> String {
        value.map { character in
            character.isLetter || character.isNumber || character == "-" || character == "_" ? character : "_"
        }.reduce(into: "") { $0.append($1) }
    }
}

private struct SearchResult {
    let title: String
    let url: String
    let snippet: String
}

enum SongStoryServiceError: Error, LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let message): return message
        }
    }
}
