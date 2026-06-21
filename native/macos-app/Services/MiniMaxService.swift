import Foundation

@MainActor
final class MiniMaxService {
    private let settings: AppSettingsStore
    private let outputDir = URL(fileURLWithPath: "\(NSHomeDirectory())/Library/Application Support/MiniMax TTS Studio/tts-cache", isDirectory: true)

    init(settings: AppSettingsStore) {
        self.settings = settings
    }

    func checkModel() async throws {
        guard settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw MiniMaxServiceError.message("DJ 还未生效，请先去设置里配置")
        }

        let payload: [String: Any] = [
            "model": settings.textModel,
            "messages": [
                ["role": "system", "content": "你是 AI DJ 连接检查器。"],
                ["role": "user", "content": "只回复：DJ在线"]
            ],
            "temperature": 0,
            "max_completion_tokens": 32
        ]
        _ = try await postJSON(path: "chat/completions", payload: payload)
    }

    func generateTransitionScript(
        current: SoulTrack,
        next: SoulTrack?,
        currentLyricExcerpt: String? = nil,
        nextLyricExcerpt: String? = nil,
        songStoryInsight: SongStoryInsight? = nil,
        timeAnnouncement: String? = nil
    ) async throws -> GeneratedTransitionScript {
        guard settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw MiniMaxServiceError.message("DJ 还未生效，请先去设置里配置")
        }

        let userPrompt = transitionPrompt(
            current: current,
            next: next,
            currentLyricExcerpt: currentLyricExcerpt,
            nextLyricExcerpt: nextLyricExcerpt,
            songStoryInsight: songStoryInsight,
            timeAnnouncement: timeAnnouncement,
            retry: false
        )
        let payload: [String: Any] = [
            "model": settings.textModel,
            "messages": [
                ["role": "system", "content": "你正在为本地 AI 电台生成串场词。只需要返回最终可播报正文，正文要完整自然，100 字以内。"],
                ["role": "user", "content": userPrompt]
            ],
            "temperature": 0.82,
            "top_p": 0.94,
            "max_completion_tokens": 4096
        ]

        let json = try await postJSON(path: "chat/completions", payload: payload)
        let raw = extractAssistantText(json)
        let cleaned = enforceTimeAnnouncement(cleanScript(raw), timeAnnouncement: timeAnnouncement)
        if cleaned.isEmpty == false {
            return GeneratedTransitionScript(text: cleaned, source: .ai)
        }

        let retryPayload: [String: Any] = [
            "model": settings.textModel,
            "messages": [
                ["role": "system", "content": "你是电台主播。只输出最终可播报正文，正文完整，100 字以内。"],
                ["role": "user", "content": transitionPrompt(
                    current: current,
                    next: next,
                    currentLyricExcerpt: currentLyricExcerpt,
                    nextLyricExcerpt: nextLyricExcerpt,
                    songStoryInsight: songStoryInsight,
                    timeAnnouncement: timeAnnouncement,
                    retry: true
                )]
            ],
            "temperature": 0.9,
            "top_p": 0.95,
            "max_completion_tokens": 2048
        ]
        let retryJSON = try await postJSON(path: "chat/completions", payload: retryPayload)
        let retryCleaned = enforceTimeAnnouncement(cleanScript(extractAssistantText(retryJSON)), timeAnnouncement: timeAnnouncement)
        if retryCleaned.isEmpty == false {
            return GeneratedTransitionScript(text: retryCleaned, source: .aiRetry)
        }

        return GeneratedTransitionScript(text: enforceTimeAnnouncement(fallbackScript(current: current, next: next), timeAnnouncement: timeAnnouncement), source: .fallback)
    }

    func generateSongStoryInsight(track: SoulTrack, sources: [SongStorySourceCandidate]) async throws -> SongStoryInsight? {
        guard settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              sources.isEmpty == false else {
            return nil
        }

        let sourceText = sources.prefix(4).enumerated().map { index, source in
            """
            [\(index + 1)]
            标题：\(source.title)
            网址：\(source.url)
            摘要：\(source.excerpt)
            """
        }.joined(separator: "\n\n")

        let payload: [String: Any] = [
            "model": settings.textModel,
            "messages": [
                ["role": "system", "content": "你是音乐资料核验编辑。只基于用户给出的网页片段判断歌曲是否有可信背景故事。禁止编造。只输出 JSON。"],
                ["role": "user", "content": """
                歌曲：\(track.artist) - \(track.title)

                网页片段：
                \(sourceText)

                请判断这些网页片段里是否包含可用于电台串场的可信音乐上下文：歌曲创作背景、发行背景、采访信息、专辑上下文、改编/原唱关系、公开争议信息或广为确认的作品故事。

                如果只是歌词、播放器页面、下载页、营销软文、无来源解读、网友随笔，usable 必须是 false。
                如果信息不够确定，usable 必须是 false。
                如果只有基本发行/专辑信息，但来源明确，也可以 usable 为 true，但 summary 要说得克制，不要夸大成创作故事。
                如果 usable 为 true，summary 用中文概括 1-2 句，angle 写一句可用于电台串场的自然角度。

                只返回 JSON，不要 Markdown：
                {"usable":true,"confidence":0.82,"summary":"...","angle":"...","sourceIndexes":[1,2]}
                """]
            ],
            "temperature": 0.15,
            "top_p": 0.8,
            "max_completion_tokens": 1200
        ]

        let json = try await postJSON(path: "chat/completions", payload: payload)
        let raw = extractAssistantText(json)
        guard let draft = decodeSongStoryDraft(raw), draft.usable, draft.confidence >= 0.72 else {
            return nil
        }

        let selectedSources = draft.sourceIndexes
            .compactMap { index -> SongStorySourceCandidate? in
                let zeroBased = index - 1
                guard sources.indices.contains(zeroBased) else { return nil }
                return sources[zeroBased]
            }
        let finalSources = selectedSources.isEmpty ? Array(sources.prefix(2)) : selectedSources
        let insight = SongStoryInsight(
            trackID: track.id,
            title: track.title,
            artist: track.artist,
            summary: draft.summary.trimmingCharacters(in: .whitespacesAndNewlines),
            angle: draft.angle.trimmingCharacters(in: .whitespacesAndNewlines),
            confidence: min(1, max(0, draft.confidence)),
            sourceTitles: finalSources.map(\.title),
            sourceURLs: finalSources.map(\.url),
            updatedAt: Date()
        )
        return insight.isUsable ? insight : nil
    }

    private func transitionPrompt(
        current: SoulTrack,
        next: SoulTrack?,
        currentLyricExcerpt: String?,
        nextLyricExcerpt: String?,
        songStoryInsight: SongStoryInsight?,
        timeAnnouncement: String?,
        retry: Bool
    ) -> String {
        let nextText = next.map { "下一首是 \($0.artist) 的《\($0.title)》。" } ?? "没有明确下一首。"
        var lines = [
            "你现在是 AI 电台主播。",
            "现在用户正在听 \(current.artist) 的《\(current.title)》。",
            nextText,
            "请生成一段两首歌之间的自然串场旁白，用来帮助用户更好地听音乐。",
            "可以是情绪类，也可以是正常描述类。",
            "正文完整返回，100 字以内。",
            "不要编造歌曲背景、歌手经历或发行故事；只有提供了可信背景素材时才可以轻轻带一句。",
            "如果提供了报时提示，必须把报时提示作为第一句话逐字放在正文开头，不要改写，不要用夜色、凌晨、今晚等氛围词替代具体时间。",
            "如果提供了歌词片段，请结合片段理解歌曲情绪和意象，但不要直接引用、复述或改写歌词原文。",
            "只输出最终可播报正文，不要解释，不要 Markdown，不要分行，不要 <think>。"
        ]
        if let host = settings.selectedHostOrNil {
            lines.insert("主播人设：\(host.persona)", at: 1)
            if let mode = settings.hostModeOrNil {
                lines.insert("当前播报模式：\(mode.title)。\(mode.promptInstruction)", at: 2)
            }
        } else {
            lines.insert("用户还没有选择具体主播，请使用中性的电台口吻，不要自称 Ava、Leo、Nora 或 Max。", at: 1)
        }
        if let timeAnnouncement, timeAnnouncement.isEmpty == false {
            lines.append("强制报时开头：\(timeAnnouncement)")
        }
        if let currentLyricExcerpt, currentLyricExcerpt.isEmpty == false {
            lines.append("当前歌歌词片段（清洗后）：\(currentLyricExcerpt)")
        }
        if let nextLyricExcerpt, nextLyricExcerpt.isEmpty == false {
            lines.append("下一首歌词片段（清洗后）：\(nextLyricExcerpt)")
        }
        if let songStoryInsight, songStoryInsight.isUsable {
            lines.append("""
            可选歌曲背景素材（已由网页片段核验）：
            \(songStoryInsight.promptText)
            使用方式：如果它适合这次串场，可以自然融入一句；不要说“我查到”“资料显示”，不要念来源，不要扩写成百科，不要超过整段的一半。
            """)
        }
        if retry {
            lines.append("上一次输出没有最终正文；这次请直接返回完整正文。")
        }
        return lines.joined(separator: "\n")
    }

    private func decodeSongStoryDraft(_ text: String) -> SongStoryInsightDraft? {
        let cleaned = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = cleaned.firstIndex(of: "{"),
              let end = cleaned.lastIndex(of: "}") else {
            return nil
        }
        let jsonText = String(cleaned[start...end])
        guard let data = jsonText.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(SongStoryInsightDraft.self, from: data)
    }

    func synthesizeSpeech(
        _ text: String,
        voiceID overrideVoiceID: String? = nil,
        speed overrideSpeed: Double? = nil,
        pitch overridePitch: Double? = nil,
        cacheKey: String? = nil
    ) async throws -> SynthesizedSpeech {
        guard settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw MiniMaxServiceError.message("DJ 还未生效，请先去设置里配置")
        }

        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        let outURL: URL
        if let cacheKey {
            outURL = outputDir.appendingPathComponent("preview-\(sanitize(cacheKey)).mp3")
            if FileManager.default.fileExists(atPath: outURL.path) {
                return SynthesizedSpeech(path: outURL.path, durationMs: nil)
            }
        } else {
            outURL = outputDir.appendingPathComponent("tts-\(Int(Date().timeIntervalSince1970 * 1000)).mp3")
        }
        let payload: [String: Any] = [
            "model": settings.ttsModel,
            "text": text,
            "stream": false,
            "language_boost": "Chinese",
            "output_format": "hex",
            "voice_setting": [
                "voice_id": overrideVoiceID ?? settings.voiceID,
                "speed": overrideSpeed ?? settings.speed,
                "vol": 2,
                "pitch": overridePitch ?? settings.pitch
            ],
            "audio_setting": [
                "sample_rate": 32000,
                "bitrate": 128000,
                "format": "mp3",
                "channel": 1
            ],
            "latex_read": false,
            "english_normalization": true,
            "subtitle_enable": false
        ]

        let json = try await postJSON(path: "t2a_v2", payload: payload)
        guard let data = json["data"] as? [String: Any],
              let audioHex = data["audio"] as? String,
              let audio = Data(hexString: audioHex) else {
            throw MiniMaxServiceError.message("MiniMax TTS 没有返回可播放音频。")
        }
        try audio.write(to: outURL, options: .atomic)
        let extra = json["extra_info"] as? [String: Any]
        let durationMs = extra?["audio_length"] as? Double ?? (extra?["audio_length"] as? NSNumber)?.doubleValue
        return SynthesizedSpeech(path: outURL.path, durationMs: durationMs)
    }

    private func sanitize(_ value: String) -> String {
        value.map { character in
            character.isLetter || character.isNumber || character == "-" || character == "_" ? character : "_"
        }.reduce(into: "") { $0.append($1) }
    }

    private func postJSON(path: String, payload: [String: Any]) async throws -> [String: Any] {
        guard let url = URL(string: "\(versionedBaseURL())/\(path)") else {
            throw MiniMaxServiceError.message("MiniMax URL 无效。")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        let text = String(data: data, encoding: .utf8) ?? ""
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw MiniMaxServiceError.message("MiniMax 请求失败：HTTP \(http.statusCode) \(text)")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MiniMaxServiceError.message("MiniMax 返回了非 JSON 内容。")
        }
        if let base = json["base_resp"] as? [String: Any],
           let statusCode = base["status_code"] as? Int,
           statusCode != 0 {
            throw MiniMaxServiceError.message(base["status_msg"] as? String ?? "MiniMax 请求失败。")
        }
        return json
    }

    private func versionedBaseURL() -> String {
        let trimmed = settings.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return trimmed.lowercased().hasSuffix("/v1") ? trimmed : "\(trimmed)/v1"
    }

    private func extractAssistantText(_ json: [String: Any]) -> String {
        guard let choices = json["choices"] as? [[String: Any]],
              let first = choices.first else { return "" }
        if let message = first["message"] as? [String: Any] {
            return message["content"] as? String ?? message["reasoning_content"] as? String ?? ""
        }
        return first["text"] as? String ?? ""
    }

    private func cleanScript(_ text: String) -> String {
        var output = text
        if let range = output.range(of: "</think>", options: [.caseInsensitive]) {
            output = String(output[range.upperBound...])
        }
        output = output.replacingOccurrences(of: #"<think>[\s\S]*?</think>"#, with: "", options: .regularExpression)
        output = output.replacingOccurrences(of: #"<think>[\s\S]*$"#, with: "", options: .regularExpression)
        output = output.replacingOccurrences(of: "```", with: "")
        output = output.replacingOccurrences(of: "\n", with: " ")
        output = output.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        output = output.replacingOccurrences(of: #"^(最终播报正文|最终正文|正文|串场词|旁白)[:：]\s*"#, with: "", options: .regularExpression)
        return output.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'“”‘’")))
    }

    private func enforceTimeAnnouncement(_ text: String, timeAnnouncement: String?) -> String {
        guard let timeAnnouncement, timeAnnouncement.isEmpty == false else { return text }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(timeAnnouncement) == false else { return trimmed }
        let withoutExistingTime = trimmed
            .replacingOccurrences(
                of: #"现在是北京时间\s*\d{1,2}\s*点(?:半|整)?[。,.，、\s]*"#,
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(timeAnnouncement)\(withoutExistingTime.isEmpty ? "" : " \(withoutExistingTime)")"
    }

    private func fallbackScript(current: SoulTrack, next: SoulTrack?) -> String {
        if let next {
            return "刚才这首《\(current.title)》还留着余温，接下来让\(next.artist)的《\(next.title)》继续把情绪往前带。"
        }
        return "这一刻先把注意力交给《\(current.title)》，让旋律慢慢把心里的画面铺开。"
    }
}

struct SynthesizedSpeech {
    let path: String
    let durationMs: Double?
}

struct GeneratedTransitionScript {
    let text: String
    let source: GeneratedTransitionScriptSource
}

private struct SongStoryInsightDraft: Decodable {
    let usable: Bool
    let confidence: Double
    let summary: String
    let angle: String
    let sourceIndexes: [Int]

    private enum CodingKeys: String, CodingKey {
        case usable
        case confidence
        case summary
        case angle
        case sourceIndexes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        usable = try container.decode(Bool.self, forKey: .usable)
        confidence = try container.decode(Double.self, forKey: .confidence)
        summary = try container.decode(String.self, forKey: .summary)
        angle = try container.decode(String.self, forKey: .angle)
        sourceIndexes = (try? container.decode([Int].self, forKey: .sourceIndexes)) ?? []
    }
}

enum GeneratedTransitionScriptSource {
    case ai
    case aiRetry
    case fallback

    var logLabel: String {
        switch self {
        case .ai: return "AI"
        case .aiRetry: return "AI重试"
        case .fallback: return "本地兜底"
        }
    }
}

enum MiniMaxServiceError: Error, LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let message): return message
        }
    }
}

private extension Data {
    init?(hexString: String) {
        let clean = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count.isMultiple(of: 2) else { return nil }
        var data = Data()
        var index = clean.startIndex
        while index < clean.endIndex {
            let nextIndex = clean.index(index, offsetBy: 2)
            guard let byte = UInt8(clean[index..<nextIndex], radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }
        self = data
    }
}
