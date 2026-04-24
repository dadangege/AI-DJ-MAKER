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
        let cleaned = cleanScript(raw)
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
                    timeAnnouncement: timeAnnouncement,
                    retry: true
                )]
            ],
            "temperature": 0.9,
            "top_p": 0.95,
            "max_completion_tokens": 2048
        ]
        let retryJSON = try await postJSON(path: "chat/completions", payload: retryPayload)
        let retryCleaned = cleanScript(extractAssistantText(retryJSON))
        if retryCleaned.isEmpty == false {
            return GeneratedTransitionScript(text: retryCleaned, source: .aiRetry)
        }

        return GeneratedTransitionScript(text: fallbackScript(current: current, next: next), source: .fallback)
    }

    private func transitionPrompt(
        current: SoulTrack,
        next: SoulTrack?,
        currentLyricExcerpt: String?,
        nextLyricExcerpt: String?,
        timeAnnouncement: String?,
        retry: Bool
    ) -> String {
        let nextText = next.map { "下一首是 \($0.artist) 的《\($0.title)》。" } ?? "没有明确下一首。"
        var lines = [
            "你现在是电台的情感主播。",
            "现在用户正在听 \(current.artist) 的《\(current.title)》。",
            nextText,
            "请生成一段两首歌之间的自然串场旁白，用来帮助用户更好地听音乐。",
            "可以是情绪类，也可以是正常描述类。",
            "正文完整返回，100 字以内。",
            "如果提供了报时提示，请把报时自然放在开头。",
            "如果提供了歌词片段，请结合片段理解歌曲情绪和意象，但不要直接引用、复述或改写歌词原文。",
            "只输出最终可播报正文，不要解释，不要 Markdown，不要分行，不要 <think>。"
        ]
        if let timeAnnouncement, timeAnnouncement.isEmpty == false {
            lines.append("报时提示：\(timeAnnouncement)")
        }
        if let currentLyricExcerpt, currentLyricExcerpt.isEmpty == false {
            lines.append("当前歌歌词片段（清洗后）：\(currentLyricExcerpt)")
        }
        if let nextLyricExcerpt, nextLyricExcerpt.isEmpty == false {
            lines.append("下一首歌词片段（清洗后）：\(nextLyricExcerpt)")
        }
        if retry {
            lines.append("上一次输出没有最终正文；这次请直接返回完整正文。")
        }
        return lines.joined(separator: "\n")
    }

    func synthesizeSpeech(_ text: String) async throws -> SynthesizedSpeech {
        guard settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw MiniMaxServiceError.message("DJ 还未生效，请先去设置里配置")
        }

        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        let outURL = outputDir.appendingPathComponent("tts-\(Int(Date().timeIntervalSince1970 * 1000)).mp3")
        let payload: [String: Any] = [
            "model": settings.ttsModel,
            "text": text,
            "stream": false,
            "language_boost": "Chinese",
            "output_format": "hex",
            "voice_setting": [
                "voice_id": settings.voiceID,
                "speed": settings.speed,
                "vol": 2,
                "pitch": settings.pitch
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
