import Foundation

final class AppSettingsStore: ObservableObject {
    @Published var apiKey: String
    @Published var baseURL: String
    @Published var textModel: String
    @Published var ttsModel: String
    @Published var voiceID: String
    @Published var speed: Double
    @Published var pitch: Double

    private let defaults = UserDefaults.standard
    private let settingsURL = URL(fileURLWithPath: "\(NSHomeDirectory())/Library/Application Support/MiniMax TTS Studio/settings.json")

    init() {
        let nodeSettings = Self.loadNodeSettings()
        apiKey = defaults.string(forKey: Keys.apiKey) ?? nodeSettings["apiKey"] ?? ""
        baseURL = defaults.string(forKey: Keys.baseURL) ?? nodeSettings["baseUrl"] ?? "https://api.minimaxi.com/v1"
        textModel = defaults.string(forKey: Keys.textModel) ?? nodeSettings["textModel"] ?? "MiniMax-M2.7-highspeed"
        ttsModel = defaults.string(forKey: Keys.ttsModel) ?? nodeSettings["ttsModel"] ?? "speech-2.8-hd"
        voiceID = defaults.string(forKey: Keys.voiceID) ?? nodeSettings["voiceId"] ?? "Chinese (Mandarin)_Gentle_Senior"
        speed = defaults.object(forKey: Keys.speed) as? Double ?? 0.92
        pitch = defaults.object(forKey: Keys.pitch) as? Double ?? -1
    }

    func save() {
        defaults.set(apiKey, forKey: Keys.apiKey)
        defaults.set(baseURL, forKey: Keys.baseURL)
        defaults.set(textModel, forKey: Keys.textModel)
        defaults.set(ttsModel, forKey: Keys.ttsModel)
        defaults.set(voiceID, forKey: Keys.voiceID)
        defaults.set(speed, forKey: Keys.speed)
        defaults.set(pitch, forKey: Keys.pitch)
        saveNodeSettings()
    }

    var maskedKey: String {
        guard apiKey.count > 10 else { return apiKey.isEmpty ? "未配置" : "已配置" }
        return "\(apiKey.prefix(6))...\(apiKey.suffix(4))"
    }

    private enum Keys {
        static let apiKey = "soulDJ.openAI.apiKey"
        static let baseURL = "soulDJ.openAI.baseURL"
        static let textModel = "soulDJ.openAI.textModel"
        static let ttsModel = "soulDJ.openAI.ttsModel"
        static let voiceID = "soulDJ.openAI.voiceID"
        static let speed = "soulDJ.voice.speed"
        static let pitch = "soulDJ.voice.pitch"
    }

    private func saveNodeSettings() {
        do {
            try FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            var payload: [String: String] = [
                "baseUrl": baseURL,
                "textModel": textModel,
                "ttsModel": ttsModel,
                "voiceId": voiceID
            ]
            if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                payload["apiKey"] = apiKey
            }
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: settingsURL, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: settingsURL.path)
        } catch {
            print("Failed to save Node AI DJ settings: \(error.localizedDescription)")
        }
    }

    private static func loadNodeSettings() -> [String: String] {
        let url = URL(fileURLWithPath: "\(NSHomeDirectory())/Library/Application Support/MiniMax TTS Studio/settings.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return json.reduce(into: [String: String]()) { result, pair in
            if let value = pair.value as? String {
                result[pair.key] = value
            }
        }
    }
}
