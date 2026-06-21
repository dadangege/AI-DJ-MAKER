import Foundation

@MainActor
final class SoulDJStore: ObservableObject {
    @Published var selectedRoute: SoulRoute = .library
    @Published var showLoginSheet = false
    @Published var showHostPicker = false
    @Published var qrLogin = QRLoginState()
    @Published var installProgress = InstallProgressState()
    @Published var account: NeteaseAccount = .guest
    @Published var playlists: [NeteasePlaylist] = []
    @Published var publicPlaylists: [NeteasePlaylist] = []
    @Published var selectedPlaylist: NeteasePlaylist?
    @Published var selectedTracks: [SoulTrack] = []
    @Published var trackPage = 0
    @Published var loadingTracks = false
    @Published var currentTrack: SoulTrack = .placeholder
    @Published var nextTrack: SoulTrack?
    @Published var elapsed: Double = 0
    @Published var duration: Double = 0
    @Published var isPlaying = false
    @Published var isPreparingPlayback = false
    @Published var preparingTrackID: String?
    @Published var selectedTrackID: String?
    @Published var downloadStatus = "Ready"
    @Published var playbackMode: PlaybackMode
    @Published var volume: Double
    @Published var aiHostMessage = "Soul DJ 已就绪。登录网易云后，我会读取你的歌单并准备串场。"
    @Published var aiDjModelStatus: AiDjModelStatus = .notConfigured
    @Published var aiDjStatusMessage = AiDjModelStatus.notConfigured.defaultMessage
    @Published var aiDjTransitionSummary = ""
    @Published var aiDjTesting = false
    @Published var lyricLines: [TimedLyricLine] = []
    @Published var lyricStatus = "播放歌曲后显示歌词"
    @Published var spectrumLevels: [Float] = Array(repeating: 0, count: 36)
    @Published var hostPreviewing = false
    @Published var hostPickerMessage = ""
    @Published var environmentContext: EnvironmentContext?
    @Published var environmentStatus = ""
    @Published var logs: [DJLogEntry] = []

    let settings: AppSettingsStore
    private let netease: NeteaseService
    private let audioEngine: LocalAudioEngine
    private let miniMax: MiniMaxService
    private let environment: EnvironmentContextService
    private let songStory: SongStoryService
    private var loginPollTask: Task<Void, Never>?
    private var progressPollTask: Task<Void, Never>?
    private var streamFallbackTask: Task<Void, Never>?
    private var lyricTask: Task<Void, Never>?
    private var playbackRequestID: UUID?
    private var preparedTransition: PreparedTransition?
    private var transitionTask: Task<Void, Never>?
    private var lastTimeAnnouncementAt: Date?
    private var unavailableTrackIDs = Set<String>()
    private var storyLookupAttemptedTrackIDs = Set<String>()
    private var generatedTransitionCount = 0
    private var lastStoryTransitionCount = -10
    private var finishFallbackTrackKey: String?
    private let defaults = UserDefaults.standard
    private let playbackQualities = ["standard", "exhigh", "higher", "lossless", "hires"]
    private let publicPlaylistCategories = ["华语", "流行", "民谣", "摇滚", "电子", "轻音乐"]
    private let storyTransitionCooldown = 2
    private var publicPlaylistPage = 0

    init(settings: AppSettingsStore, netease: NeteaseService, audioEngine: LocalAudioEngine, miniMax: MiniMaxService, environment: EnvironmentContextService, songStory: SongStoryService) {
        self.settings = settings
        self.netease = netease
        self.audioEngine = audioEngine
        self.miniMax = miniMax
        self.environment = environment
        self.songStory = songStory
        self.playbackMode = PlaybackMode(rawValue: defaults.string(forKey: Keys.playbackMode) ?? "") ?? .ordered
        self.volume = defaults.object(forKey: Keys.volume) as? Double ?? 0.82
        qrLogin.hasCookie = netease.hasCookie
        qrLogin.status = netease.hasCookie ? "success" : "idle"
        qrLogin.message = netease.hasCookie ? "已保存网易云登录态。" : "点击扫码登录网易云。"
        account = netease.loadCachedAccount()
        playlists = netease.loadCachedPlaylists()
        publicPlaylists = netease.loadCachedPublicPlaylists()
        selectedPlaylist = playlists.first
        if let id = selectedPlaylist?.id {
            selectedTracks = netease.cachedPlaylistTracks(id: id)
        }

        if netease.hasCookie {
            Task { await refreshPlaylists() }
        }
        Task { await refreshPublicPlaylists() }
        Task { await refreshEnvironmentContext() }

        audioEngine.onMusicFinished = { [weak self] _ in
            Task { @MainActor in
                self?.handleMusicFinished()
            }
        }
        audioEngine.onSpectrumLevels = { [weak self] levels in
            Task { @MainActor in
                self?.spectrumLevels = levels
            }
        }
        startProgressPolling()
    }

    var loginButtonTitle: String {
        qrLogin.hasCookie ? "已登录" : "Scan to Login"
    }

    var isLoggedIn: Bool {
        qrLogin.hasCookie
    }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, elapsed / duration))
    }

    let tracksPerPage = 50

    var pagedTracks: [SoulTrack] {
        let start = trackPage * tracksPerPage
        guard selectedTracks.indices.contains(start) else { return [] }
        let end = min(start + tracksPerPage, selectedTracks.count)
        return Array(selectedTracks[start..<end])
    }

    var totalTrackPages: Int {
        max(1, Int(ceil(Double(selectedTracks.count) / Double(tracksPerPage))))
    }

    var trackPageRangeText: String {
        guard !selectedTracks.isEmpty else { return "0 / 0" }
        let start = trackPage * tracksPerPage + 1
        let end = min((trackPage + 1) * tracksPerPage, selectedTracks.count)
        return "\(start)-\(end) / \(selectedTracks.count)"
    }

    var selectedTrackForPlayback: SoulTrack? {
        guard let selectedTrackID else { return nil }
        return selectedTracks.first { $0.id == selectedTrackID }
    }

    var isAiDjConnected: Bool {
        aiDjModelStatus == .connected
    }

    var currentHost: AIHostProfile {
        settings.selectedHost
    }

    var configuredHost: AIHostProfile? {
        settings.selectedHostOrNil
    }

    var hasSelectedHost: Bool {
        settings.hasSelectedHost
    }

    var currentHostMode: AIHostMode {
        settings.hostMode
    }

    var configuredHostMode: AIHostMode? {
        settings.hostModeOrNil
    }

    func openHostPicker() {
        hostPickerMessage = ""
        showHostPicker = true
    }

    func closeHostPicker() {
        showHostPicker = false
    }

    func saveHostSelection(host: AIHostProfile, mode: AIHostMode) {
        settings.applyHost(host, mode: mode)
        aiHostMessage = "\(host.name) 已上线，当前为\(mode.title)。"
        hostPickerMessage = "已切换为 \(host.name) · \(mode.title)"
        appendLog("info", "已切换 AI 主播：\(host.name) · \(mode.title)。")
        showHostPicker = false
        prepareAiDjTransitionIfNeeded(force: true)
    }

    func previewHost(host: AIHostProfile, mode: AIHostMode) {
        guard hostPreviewing == false else { return }
        hostPreviewing = true
        hostPickerMessage = "正在生成试听..."
        Task {
            do {
                let script = "\(host.name) 已经准备好了。\(mode.promptInstruction) 接下来，我会用这段声音，陪你把每一首歌自然接上。"
                let cacheKey = "\(host.id)-\(mode.rawValue)-\(host.voiceID)-\(host.speed)-\(host.pitch)"
                let speech = try await miniMax.synthesizeSpeech(
                    script,
                    voiceID: host.voiceID,
                    speed: host.speed,
                    pitch: host.pitch,
                    cacheKey: cacheKey
                )
                await MainActor.run {
                    self.hostPreviewing = false
                    self.hostPickerMessage = "正在播放 \(host.name) 的试听。"
                    do {
                        _ = try self.audioEngine.playTTS(path: speech.path, duckVolume: 0.18, fadeMs: 3000, ttsGain: 1.45)
                    } catch {
                        self.hostPickerMessage = "试听播放失败：\(error.localizedDescription)"
                    }
                }
            } catch {
                await MainActor.run {
                    self.hostPreviewing = false
                    self.hostPickerMessage = "试听失败：\(error.localizedDescription)"
                    self.appendLog("error", self.hostPickerMessage)
                }
            }
        }
    }

    func openLogin() {
        showLoginSheet = true
        Task { await startLogin() }
    }

    func handleLoginButton() {
        if isLoggedIn {
            Task { await refreshPlaylists() }
        } else {
            openLogin()
        }
    }

    func startLogin() async {
        do {
            installProgress = InstallProgressState(
                isActive: true,
                progress: 0.05,
                title: "准备网易云登录服务",
                detail: "首次使用会自动安装依赖。"
            )
            qrLogin.status = "waiting"
            qrLogin.message = "正在准备网易云登录服务，首次使用可能需要几分钟。"
            appendLog("info", "正在准备网易云登录服务，首次使用会自动安装依赖。")
            try await netease.prepareForLogin { [weak self] progress in
                Task { @MainActor in
                    self?.installProgress = InstallProgressState(
                        isActive: progress.value < 1,
                        progress: progress.value,
                        title: progress.title,
                        detail: progress.detail
                    )
                    self?.qrLogin.message = progress.detail
                }
            }
            let state = try await netease.startQrLogin()
            qrLogin = state
            installProgress = InstallProgressState()
            appendLog("info", "网易云扫码登录二维码已生成。")
            startPollingLogin()
        } catch {
            installProgress = InstallProgressState()
            qrLogin.status = "error"
            qrLogin.message = error.localizedDescription
            appendLog("error", error.localizedDescription)
        }
    }

    func refreshPlaylists() async {
        do {
            let library = try await netease.loadUserLibrary()
            account = library.account
            playlists = library.playlists
            selectedPlaylist = selectedPlaylist ?? library.playlists.first
            qrLogin.hasCookie = true
            qrLogin.status = "success"
            qrLogin.message = "已读取 \(library.playlists.count) 个歌单。"
            aiHostMessage = "欢迎回来，\(library.account.nickname)。我已读取你的歌单。"
            appendLog("info", "已读取 \(library.account.nickname) 的网易云歌单：\(library.playlists.count) 个。")
            if selectedTracks.isEmpty, let playlist = selectedPlaylist {
                await loadTracks(for: playlist, preferCache: true)
            }
            await checkAiDjModel()
        } catch {
            appendLog("error", error.localizedDescription)
        }
    }

    func refreshPublicPlaylists() async {
        do {
            publicPlaylists = try await netease.loadPublicPlaylists()
            appendLog("info", "已读取公共歌单：\(publicPlaylists.count) 个。")
        } catch {
            appendLog("error", "公共歌单读取失败：\(error.localizedDescription)")
        }
    }

    func refreshEnvironmentContext() async {
        do {
            environmentContext = try await environment.loadEnvironmentContext()
            if let environmentContext {
                environmentStatus = environmentContext.displayText
                appendLog("info", "环境信息已读取：\(environmentContext.displayText)。")
            }
        } catch {
            environmentContext = nil
            environmentStatus = "环境信息不可用"
            appendLog("info", "环境信息不可用，已跳过天气展示。")
        }
    }

    func shufflePublicPlaylists() {
        publicPlaylistPage += 1
        let category = publicPlaylistCategories[publicPlaylistPage % publicPlaylistCategories.count]
        let offset = (publicPlaylistPage / publicPlaylistCategories.count) * 8
        Task {
            do {
                publicPlaylists = try await netease.loadPublicPlaylists(limit: 8, category: category, offset: offset)
                appendLog("info", "已换一组公共歌单：\(category)。")
            } catch {
                appendLog("error", "公共歌单换一换失败：\(error.localizedDescription)")
            }
        }
    }

    func saveSettings() {
        settings.save()
        appendLog("info", "OpenAI-compatible 配置已保存。")
        selectedRoute = .library
        aiHostMessage = "设置已保存，正在检查 AI DJ 模型连接。"
        Task { await checkAiDjModel() }
    }

    func playTrack(_ track: SoulTrack) {
        cancelPreparedAiDjTransition()
        streamFallbackTask?.cancel()
        unavailableTrackIDs.remove(track.id)
        selectedTrackID = track.id
        let requestID = UUID()
        playbackRequestID = requestID
        finishFallbackTrackKey = nil
        isPreparingPlayback = true
        preparingTrackID = track.id
        downloadStatus = "正在准备 \(track.title)..."
        currentTrack = track
        elapsed = 0
        duration = track.duration > 0 ? track.duration : duration
        isPlaying = false
        loadLyrics(for: track)
        updateNextTrack()
        appendLog("info", "准备播放：\(track.artist) - \(track.title)。")

        Task {
            do {
                if let cachedURL = cachedPlayableAudio(for: track) {
                    await MainActor.run {
                        guard self.playbackRequestID == requestID else { return }
                        self.startLocalPlayback(track: track, audioURL: cachedURL)
                    }
                    return
                }

                let stream = try await resolvePlayableStream(for: track)
                await MainActor.run {
                    guard self.playbackRequestID == requestID else { return }
                    self.startStreamingPlayback(track: track, stream: stream, requestID: requestID)
                }

            } catch {
                await MainActor.run {
                    guard self.playbackRequestID == requestID else { return }
                    self.markTrackUnavailable(track, reason: error.localizedDescription)
                    self.handlePlaybackError(error)
                    Task { await self.playNextAvailableTrack(manual: false) }
                }
            }
        }
    }

    private func startLocalPlayback(track: SoulTrack, audioURL: URL) {
        streamFallbackTask?.cancel()
        let playableTrack = track.withLocalPath(audioURL.path)
        rememberLocalPath(for: playableTrack)
        do {
            let status = try audioEngine.loadMusic(
                path: audioURL.path,
                track: trackPayload(playableTrack),
                autoplay: true,
                volume: Float(volume)
            )
            currentTrack = playableTrack
            finishFallbackTrackKey = nil
            applyAudioStatus(status)
            isPlaying = true
            isPreparingPlayback = false
            preparingTrackID = nil
            downloadStatus = "正在播放"
            updateNextTrack()
            aiHostMessage = "正在播放 \(playableTrack.artist) 的《\(playableTrack.title)》。"
            appendLog("info", "开始播放缓存歌曲：\(playableTrack.artist) - \(playableTrack.title)。")
            prepareAiDjTransitionIfNeeded(force: true)
        } catch {
            handlePlaybackError(error)
        }
    }

    private func startStreamingPlayback(track: SoulTrack, stream: NeteaseAudioStream, requestID: UUID) {
        do {
            let streamingTrack = track.withLocalPath(stream.remoteURL.absoluteString)
            let status = try audioEngine.loadMusicStream(
                url: stream.remoteURL,
                track: trackPayload(streamingTrack),
                duration: track.duration,
                autoplay: true,
                volume: Float(volume)
            )
            currentTrack = streamingTrack
            finishFallbackTrackKey = nil
            applyAudioStatus(status)
            isPlaying = true
            isPreparingPlayback = false
            preparingTrackID = nil
            downloadStatus = "边播边缓存"
            updateNextTrack()
            aiHostMessage = "正在播放 \(streamingTrack.artist) 的《\(streamingTrack.title)》，同时后台缓存。"
            appendLog("info", "开始流式播放并后台缓存：\(streamingTrack.artist) - \(streamingTrack.title)。")
            startStreamingFallbackWatchdog(track: track, stream: stream, requestID: requestID)
            prepareAiDjTransitionIfNeeded(force: true)
        } catch {
            handlePlaybackError(error)
        }
    }

    private func startStreamingFallbackWatchdog(track: SoulTrack, stream: NeteaseAudioStream, requestID: UUID) {
        streamFallbackTask?.cancel()
        streamFallbackTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, !Task.isCancelled else { return }
            let status = self.audioEngine.status()
            let elapsed = status["elapsed"] as? Double ?? 0
            let path = status["path"] as? String ?? ""
            let stillCurrent = await MainActor.run { self.playbackRequestID == requestID && self.currentTrack.id == track.id }
            guard stillCurrent else { return }
            guard path == stream.remoteURL.absoluteString else { return }
            guard elapsed < 0.25 else {
                Task.detached(priority: .utility) { [netease] in
                    _ = try? await netease.cacheAudio(from: stream)
                }
                return
            }

            await MainActor.run {
                self.downloadStatus = "流播卡住，切换本地缓存"
                self.appendLog("info", "远程流播放没有推进，开始下载缓存后切换本地播放：\(track.title)。")
            }

            do {
                let cachedURL = try await self.netease.cacheAudio(from: stream)
                await MainActor.run {
                    guard self.playbackRequestID == requestID, self.currentTrack.id == track.id else { return }
                    self.appendLog("info", "缓存完成，切换本地文件播放：\(track.title)。")
                    self.startLocalPlayback(track: track, audioURL: cachedURL)
                }
            } catch {
                await MainActor.run {
                    guard self.playbackRequestID == requestID, self.currentTrack.id == track.id else { return }
                    self.appendLog("error", "流播卡住且缓存失败：\(error.localizedDescription)")
                    self.handlePlaybackError(error)
                }
            }
        }
    }

    func checkAiDjModel() async {
        aiDjModelStatus = .checking
        aiDjStatusMessage = AiDjModelStatus.checking.defaultMessage
        do {
            try await miniMax.checkModel()
            aiDjModelStatus = .connected
            aiDjStatusMessage = AiDjModelStatus.connected.defaultMessage
            aiHostMessage = "AI DJ 已生效。我会提前准备两首歌之间的串场。"
            appendLog("info", "AI DJ 模型已连接：\(settings.textModel)。")
            prepareAiDjTransitionIfNeeded(force: true)
        } catch {
            aiDjModelStatus = .error
            aiDjStatusMessage = "DJ 还未生效，请先去设置里配置"
            aiHostMessage = "\(aiDjStatusMessage)：\(error.localizedDescription)"
            appendLog("error", error.localizedDescription)
        }
    }

    func testAiDjTransition() {
        guard aiDjTesting == false else { return }
        aiDjTesting = true
        appendLog("info", "开始测试 AI DJ 口播。")
        Task {
            do {
                if aiDjModelStatus != .connected {
                    try await miniMax.checkModel()
                    await MainActor.run {
                        self.aiDjModelStatus = .connected
                        self.aiDjStatusMessage = AiDjModelStatus.connected.defaultMessage
                    }
                }
                let generated = try await miniMax.generateTransitionScript(current: currentTrack, next: nextTrack)
                let script = generated.text
                let audio = try await miniMax.synthesizeSpeech(script)
                await MainActor.run {
                    self.aiDjTesting = false
                    self.aiHostMessage = script
                    self.appendLog("script", "测试口播文案（\(generated.source.logLabel)）：\(script)")
                    self.appendLog("tts", "测试口播音频已生成：\(URL(fileURLWithPath: audio.path).lastPathComponent)")
                    do {
                        _ = try self.audioEngine.playTTS(path: audio.path, duckVolume: 0.16, fadeMs: 3000, ttsGain: 1.45)
                    } catch {
                        self.appendLog("error", "测试口播播放失败：\(error.localizedDescription)")
                    }
                    self.appendLog("info", "测试口播已发送到播放器。")
                }
            } catch {
                await MainActor.run {
                    self.aiDjTesting = false
                    self.aiHostMessage = "测试口播失败：\(error.localizedDescription)"
                    self.appendLog("error", error.localizedDescription)
                }
            }
        }
    }

    func selectTrackForPlayback(_ track: SoulTrack) {
        selectedTrackID = track.id
        aiHostMessage = "已选中《\(track.title)》，双击歌曲行开始播放。"
        downloadStatus = "双击播放"
    }

    func togglePlay() {
        if isPreparingPlayback { return }

        if currentTrack.id == SoulTrack.placeholder.id, let first = selectedTracks.first {
            playTrack(first)
            return
        }

        if currentTrack.localPath.isEmpty, currentTrack.id != SoulTrack.placeholder.id {
            playTrack(currentTrack)
            return
        }

        do {
            let wasPlaying = isPlaying
            let status = isPlaying ? audioEngine.pause() : try audioEngine.play()
            applyAudioStatus(status)
            appendLog("info", isPlaying ? "播放器进入播放状态。" : "播放器已暂停。")
            if wasPlaying {
                cancelPreparedAiDjTransition()
            } else {
                prepareAiDjTransitionIfNeeded(force: true)
            }
        } catch {
            handlePlaybackError(error)
        }
    }

    func previous() {
        guard let track = previousTrackCandidate() else {
            seek(to: 0)
            return
        }
        playTrack(track)
    }

    func next() {
        cancelPreparedAiDjTransition()
        streamFallbackTask?.cancel()
        Task { await playNextAvailableTrack(manual: true) }
    }

    func cyclePlaybackMode() {
        playbackMode = playbackMode.nextMode()
        defaults.set(playbackMode.rawValue, forKey: Keys.playbackMode)
        updateNextTrack()
        appendLog("info", "播放模式：\(playbackMode.title)。")
    }

    func setVolume(_ value: Double) {
        volume = min(1, max(0, value))
        defaults.set(volume, forKey: Keys.volume)
        _ = audioEngine.setMusicVolume(Float(volume))
    }

    func seek(to seconds: Double) {
        do {
            cancelPreparedAiDjTransition()
            let status = try audioEngine.seekMusic(to: seconds)
            applyAudioStatus(status)
            appendLog("info", "已跳转到 \(formatTime(elapsed))。")
            if isPlaying {
                prepareAiDjTransitionIfNeeded(force: true)
            }
        } catch {
            handlePlaybackError(error)
        }
    }

    func select(_ playlist: NeteasePlaylist) {
        selectedPlaylist = playlist
        selectedRoute = .playlists
        selectedTracks = netease.cachedPlaylistTracks(id: playlist.id)
        trackPage = 0
        aiHostMessage = "已选中 \(playlist.name)。正在读取歌曲列表。"
        Task { await loadTracks(for: playlist, preferCache: selectedTracks.isEmpty == false) }
    }

    func goHome() {
        selectedRoute = .library
    }

    func openPlayingPlaylist() {
        guard let selectedPlaylist else { return }
        selectedRoute = .playlists
        if selectedTracks.isEmpty {
            Task { await loadTracks(for: selectedPlaylist, preferCache: true) }
        }
    }

    func nextTrackPage() {
        trackPage = min(totalTrackPages - 1, trackPage + 1)
    }

    func previousTrackPage() {
        trackPage = max(0, trackPage - 1)
    }

    func refreshSelectedPlaylistTracks() {
        guard let selectedPlaylist else { return }
        Task { await loadTracks(for: selectedPlaylist, preferCache: false) }
    }

    func loadTracks(for playlist: NeteasePlaylist, preferCache: Bool) async {
        loadingTracks = true
        defer { loadingTracks = false }

        do {
            let tracks = try await netease.loadPlaylistTracks(id: playlist.id, preferCache: preferCache)
                if selectedPlaylist?.id == playlist.id {
                unavailableTrackIDs.removeAll()
                storyLookupAttemptedTrackIDs.removeAll()
                selectedTracks = tracks
                trackPage = min(trackPage, max(0, totalTrackPages - 1))
                if currentTrack.id == SoulTrack.placeholder.id {
                    elapsed = 0
                    duration = 0
                }
                updateNextTrack()
                prepareAiDjTransitionIfNeeded(force: false)
            }
            aiHostMessage = "已读取 \(playlist.name) 的 \(tracks.count) 首歌曲，歌单已缓存到本机。"
            appendLog("info", "已读取歌单歌曲：\(playlist.name) · \(tracks.count) 首。")
        } catch {
            appendLog("error", error.localizedDescription)
            aiHostMessage = "读取歌单歌曲失败：\(error.localizedDescription)"
        }
    }

    private func startPollingLogin() {
        loginPollTask?.cancel()
        loginPollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self else { return }
                do {
                    let state = try await self.netease.checkQrLogin()
                    await MainActor.run {
                        self.qrLogin = state
                        if state.status == "success" {
                            self.appendLog("info", "网易云扫码登录成功。")
                            self.showLoginSheet = false
                        }
                    }
                    if state.status == "success" {
                        await self.refreshPlaylists()
                        return
                    }
                    if ["expired", "error"].contains(state.status) {
                        return
                    }
                } catch {
                    await MainActor.run {
                        self.qrLogin.status = "error"
                        self.qrLogin.message = error.localizedDescription
                        self.appendLog("error", error.localizedDescription)
                    }
                    return
                }
            }
        }
    }

    private func handleMusicFinished() {
        guard !isPreparingPlayback else { return }
        if preparedTransition?.crossfadeStarted == true {
            appendLog("info", "歌曲结束事件已由串场淡入接管。")
            return
        }
        finishFallbackTrackKey = currentPlaybackFinishKey()
        elapsed = duration
        isPlaying = false
        Task { await playNextAvailableTrack(manual: false) }
    }

    private func startProgressPolling() {
        progressPollTask?.cancel()
        progressPollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self else { return }
                let status = self.audioEngine.status()
                await MainActor.run {
                    self.applyAudioStatus(status)
                    self.tickPreparedTransition()
                    self.handlePlaybackFinishFallbackIfNeeded()
                }
            }
        }
    }

    private func applyAudioStatus(_ status: [String: Any]) {
        guard let path = status["path"] as? String, !path.isEmpty else { return }
        elapsed = status["elapsed"] as? Double ?? elapsed
        let engineDuration = status["duration"] as? Double ?? 0
        if engineDuration > 0 {
            duration = engineDuration
        }
        isPlaying = status["playing"] as? Bool ?? isPlaying
        if let engineVolume = status["musicVolume"] as? Float {
            volume = Double(engineVolume)
        }
    }

    private func prepareAiDjTransitionIfNeeded(force: Bool) {
        guard aiDjModelStatus == .connected else { return }
        guard currentTrack.id != SoulTrack.placeholder.id, let nextTrack else {
            aiDjTransitionSummary = ""
            return
        }

        let requestedKey = "\(currentTrack.id)->\(nextTrack.id)"
        if !force, preparedTransition?.key == requestedKey { return }
        transitionTask?.cancel()
        preparedTransition = nil
        audioEngine.cancelPreparedBridge()
        aiDjTransitionSummary = "\(currentTrack.title) -> \(nextTrack.title) · 准备中"

        let current = currentTrack
        let next = nextTrack
        let currentDuration = duration > 0 ? duration : current.duration
        appendLog("info", "提前检查下一首可播性并准备串场：\(current.title) -> \(next.title)")
        appendLog("info", "歌曲背景故事模块：等待下一首可播确认后评估。")

        transitionTask = Task { [weak self] in
            guard let self else { return }
            do {
                guard let playableNext = try await self.resolveNextPlayableTrackAndURL(manual: true, maxCandidates: 3) else {
                    await MainActor.run {
                        guard self.currentTrack.id == current.id else { return }
                        self.aiDjTransitionSummary = "\(current.title) · 没有可播放的下一首"
                        self.appendLog("info", "未找到可播放的下一首，已跳过串场准备。")
                    }
                    return
                }
                let next = playableNext.track
                let nextAudioURL = playableNext.audioURL
                let key = "\(current.id)->\(next.id)"
                await MainActor.run {
                    guard self.currentTrack.id == current.id else { return }
                    self.nextTrack = next
                    self.aiDjTransitionSummary = "\(current.title) -> \(next.title) · 下一首可播放，生成文案中"
                    self.appendLog("info", "下一首可播放确认：\(next.artist) - \(next.title)。")
                }

                async let currentLyricExcerpt = self.safeLyricExcerpt(for: current)
                async let nextLyricExcerpt = self.safeLyricExcerpt(for: next)
                async let optionalStoryInsight = self.songStoryInsightForTransition(for: current)
                let lyricExcerpts = await (currentLyricExcerpt, nextLyricExcerpt)
                let storyInsight = await optionalStoryInsight
                await MainActor.run {
                    let currentText = lyricExcerpts.0 == nil ? "当前歌无歌词片段" : "当前歌歌词片段已加入 prompt"
                    let nextText = lyricExcerpts.1 == nil ? "下一首无歌词片段" : "下一首歌词片段已加入 prompt"
                    self.appendLog("info", "\(currentText)，\(nextText)。")
                    if let storyInsight {
                        self.appendLog("info", "歌曲背景素材已加入 prompt：\(storyInsight.title)。")
                    }
                }
                let generated = try await self.miniMax.generateTransitionScript(
                    current: current,
                    next: next,
                    currentLyricExcerpt: lyricExcerpts.0,
                    nextLyricExcerpt: lyricExcerpts.1,
                    songStoryInsight: storyInsight,
                    timeAnnouncement: self.beijingTimeAnnouncementIfNeeded()
                )
                let script = generated.text
                await MainActor.run {
                    self.aiDjTransitionSummary = "\(current.title) -> \(next.title) · \(generated.source.logLabel)文案已生成"
                    self.appendLog("script", "串场文案已缓存（\(generated.source.logLabel)）：\(script)")
                }
                let speech = try await self.miniMax.synthesizeSpeech(script)
                let ttsDuration = Double(speech.durationMs ?? 8000) / 1000
                let duckLead = 1.5
                let crossfadeOverlap = 1.8
                let ttsStart = max(0, currentDuration - (ttsDuration / 2))
                let duckStart = max(0, ttsStart - duckLead)
                let nextStart = max(0, currentDuration - crossfadeOverlap)
                await MainActor.run {
                    guard self.currentTrack.id == current.id, self.nextTrack?.id == next.id else { return }
                    do {
                        _ = try self.audioEngine.preloadNextMusic(
                            url: nextAudioURL,
                            track: self.trackPayload(next.withLocalPath(nextAudioURL.absoluteString)),
                            duration: next.duration,
                            volume: Float(self.volume)
                        )
                        self.appendLog("info", "下一首已预加载：\(next.title)。")
                    } catch {
                        self.appendLog("error", "下一首预加载失败，将回退普通切歌：\(error.localizedDescription)")
                    }
                    self.preparedTransition = PreparedTransition(
                        key: key,
                        from: current,
                        to: next,
                        script: script,
                        audioPath: speech.path,
                        nextAudioURL: nextAudioURL,
                        duckStartSeconds: duckStart,
                        ttsStartSeconds: ttsStart,
                        nextStartSeconds: nextStart,
                        ttsDurationSeconds: ttsDuration,
                        duckStarted: false,
                        ttsPlayed: false,
                        crossfadeStarted: false
                    )
                    self.generatedTransitionCount += 1
                    if storyInsight != nil {
                        self.lastStoryTransitionCount = self.generatedTransitionCount
                    }
                    self.aiDjTransitionSummary = "\(current.title) -> \(next.title) · 口播 \(self.formatTime(ttsStart)) · 淡入 \(self.formatTime(nextStart))"
                    self.aiHostMessage = script
                    self.appendLog("tts", "串场音频已缓存：\(URL(fileURLWithPath: speech.path).lastPathComponent)，时长 \(String(format: "%.1f", ttsDuration)) 秒。")
                }
            } catch {
                await MainActor.run {
                    self.aiDjTransitionSummary = "\(current.title) -> \(next.title) · 准备失败"
                    self.appendLog("error", "串场准备失败：\(error.localizedDescription)")
                }
            }
        }
    }

    private func safeLyricExcerpt(for track: SoulTrack) async -> String? {
        do {
            return try await netease.lyricExcerpt(for: track)
        } catch {
            await MainActor.run {
                self.appendLog("info", "歌词片段读取失败，继续无歌词串场：\(track.title)。")
            }
            return nil
        }
    }

    private func songStoryInsightForTransition(for track: SoulTrack) async -> SongStoryInsight? {
        appendLog("info", "歌曲背景故事模块：评估 \(track.artist) - \(track.title)。")
        let transitionsSinceStory = generatedTransitionCount - lastStoryTransitionCount
        if transitionsSinceStory < storyTransitionCooldown {
            let remaining = storyTransitionCooldown - transitionsSinceStory
            appendLog("info", "歌曲背景故事低频保护：上次使用后还差 \(remaining) 次串场再尝试。")
            return nil
        }
        if let cached = songStory.cachedInsight(for: track) {
            appendLog("info", "命中歌曲背景缓存：\(track.title)。")
            return cached
        }
        guard storyLookupAttemptedTrackIDs.insert(track.id).inserted else {
            appendLog("info", "这首歌本次运行已查过背景故事，避免重复联网：\(track.title)。")
            return nil
        }

        do {
            appendLog("info", "正在查找歌曲背景故事：\(track.artist) - \(track.title)。")
            let queries = songStory.storyQueries(for: track)
            appendLog("info", "歌曲背景搜索词：\(queries.prefix(2).joined(separator: " / "))")
            let sources = try await songStory.fetchSourceCandidates(for: track)
            appendLog("info", "歌曲背景候选素材：\(sources.count) 条。")
            guard sources.isEmpty == false else {
                appendLog("info", "没有找到可用歌曲背景素材：\(track.title)。")
                return nil
            }
            let insight = try await miniMax.generateSongStoryInsight(track: track, sources: sources)
            guard let insight else {
                appendLog("info", "网页素材核验未通过，已放弃背景故事串场：\(track.title)。")
                return nil
            }
            try? songStory.saveInsight(insight, for: track)
            appendLog("info", "歌曲背景故事已缓存：\(track.title) · \(insight.angle)")
            return insight
        } catch {
            appendLog("info", "歌曲背景故事查找失败，继续普通串场：\(error.localizedDescription)")
            return nil
        }
    }

    private func loadLyrics(for track: SoulTrack) {
        lyricTask?.cancel()
        guard track.id != SoulTrack.placeholder.id else {
            lyricLines = []
            lyricStatus = "播放歌曲后显示歌词"
            return
        }

        lyricLines = []
        lyricStatus = "正在加载歌词..."
        lyricTask = Task { [weak self] in
            guard let self else { return }
            do {
                let lines = try await self.netease.timedLyrics(for: track)
                await MainActor.run {
                    guard self.currentTrack.id == track.id else { return }
                    self.lyricLines = lines
                    self.lyricStatus = lines.isEmpty ? "这首歌暂无时间轴歌词" : ""
                }
            } catch {
                await MainActor.run {
                    guard self.currentTrack.id == track.id else { return }
                    self.lyricLines = []
                    self.lyricStatus = "歌词加载失败"
                    self.appendLog("info", "歌词加载失败：\(track.title)。")
                }
            }
        }
    }

    private func beijingTimeAnnouncementIfNeeded(now: Date = Date()) -> String? {
        if let lastTimeAnnouncementAt, now.timeIntervalSince(lastTimeAnnouncementAt) < 30 * 60 {
            return nil
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        let components = calendar.dateComponents([.hour, .minute], from: now)
        guard let hour = components.hour, let minute = components.minute else { return nil }

        let closeToHour = minute <= 3 || minute >= 57
        let closeToHalf = abs(minute - 30) <= 3
        guard closeToHour || closeToHalf else { return nil }

        if closeToHalf {
            lastTimeAnnouncementAt = now
            return "现在是北京时间 \(hour) 点半。"
        }

        let announcedHour = minute >= 57 ? (hour + 1) % 24 : hour
        lastTimeAnnouncementAt = now
        return "现在是北京时间 \(announcedHour) 点。"
    }

    private func tickPreparedTransition() {
        guard var transition = preparedTransition else { return }
        guard isPlaying, currentTrack.id == transition.from.id else { return }

        if transition.duckStarted == false, elapsed >= transition.duckStartSeconds {
            transition.duckStarted = true
            preparedTransition = transition
            aiDjTransitionSummary = "\(transition.from.title) -> \(transition.to.title) · 音乐推低中"
            appendLog("info", "提前推低背景音乐：\(transition.from.title) -> \(transition.to.title)")
            _ = audioEngine.duckMusic(duckVolume: 0.14, fadeMs: 3000)
        }

        if transition.ttsPlayed == false, elapsed >= transition.ttsStartSeconds {
            transition.ttsPlayed = true
            preparedTransition = transition
            aiDjTransitionSummary = "\(transition.from.title) -> \(transition.to.title) · 口播中"
            appendLog("info", "开始播放串场：\(transition.from.title) -> \(transition.to.title)")
            do {
                _ = try audioEngine.playTTS(path: transition.audioPath, duckVolume: 0.14, fadeMs: 3000, ttsGain: 1.55)
            } catch {
                aiDjTransitionSummary = "\(transition.from.title) -> \(transition.to.title) · 口播失败"
                appendLog("error", "串场播放失败：\(error.localizedDescription)")
            }
        }

        if transition.crossfadeStarted == false, elapsed >= transition.nextStartSeconds {
            transition.crossfadeStarted = true
            preparedTransition = transition
            aiDjTransitionSummary = "\(transition.from.title) -> \(transition.to.title) · 下一首淡入中"
            appendLog("info", "开始淡入下一首：\(transition.to.title)")
            do {
                _ = try audioEngine.startBridgeToPreloadedNext(
                    crossfadeMs: 2400,
                    targetVolume: transition.ttsPlayed ? 0.14 : Float(volume)
                ) { [weak self] status in
                    Task { @MainActor in
                        self?.completePreparedBridge(status: status)
                    }
                }
            } catch {
                aiDjTransitionSummary = "\(transition.from.title) -> \(transition.to.title) · 淡入失败，等待自然切歌"
                preparedTransition = nil
                appendLog("error", "下一首淡入失败，将回退普通切歌：\(error.localizedDescription)")
            }
        }
    }

    private func completePreparedBridge(status: [String: Any]) {
        guard let transition = preparedTransition, transition.crossfadeStarted else { return }
        let promotedTrack = transition.to.withLocalPath(transition.nextAudioURL.absoluteString)
        currentTrack = promotedTrack
        selectedTrackID = promotedTrack.id
        finishFallbackTrackKey = nil
        elapsed = 0
        duration = promotedTrack.duration
        isPlaying = true
        isPreparingPlayback = false
        preparingTrackID = nil
        downloadStatus = "正在播放"
        rememberLocalPath(for: promotedTrack)
        loadLyrics(for: promotedTrack)
        applyAudioStatus(status)
        updateNextTrack()
        aiDjTransitionSummary = "\(transition.from.title) -> \(transition.to.title) · 串场完成"
        aiHostMessage = "已衔接到 \(promotedTrack.artist) 的《\(promotedTrack.title)》。"
        appendLog("info", "串场完成，已进入下一首：\(promotedTrack.title)。")
        preparedTransition = nil
        prepareAiDjTransitionIfNeeded(force: true)
    }

    private func resolveBridgeAudioURL(for track: SoulTrack) async throws -> URL {
        if let cachedURL = cachedPlayableAudio(for: track) {
            return cachedURL
        }
        if unavailableTrackIDs.contains(track.id) {
            throw NeteaseServiceError.message("歌曲已标记为不可播放：\(track.artist) - \(track.title)。")
        }
        let stream = try await resolvePlayableStream(for: track)
        Task.detached(priority: .utility) { [netease] in
            _ = try? await netease.cacheAudio(from: stream)
        }
        return stream.remoteURL
    }

    private func cachedPlayableAudio(for track: SoulTrack) -> URL? {
        for quality in playbackQualities {
            if let cachedURL = netease.cachedAudioPath(for: track, quality: quality) {
                return cachedURL
            }
        }
        return nil
    }

    private func resolvePlayableStream(for track: SoulTrack) async throws -> NeteaseAudioStream {
        if unavailableTrackIDs.contains(track.id) {
            throw NeteaseServiceError.message("歌曲已标记为不可播放：\(track.artist) - \(track.title)。")
        }

        var errors: [String] = []
        for quality in playbackQualities {
            do {
                let stream = try await netease.resolveAudioStream(for: track, quality: quality)
                await MainActor.run {
                    self.appendLog("info", "已解析 \(quality) 音频：\(track.title)。")
                }
                return stream
            } catch {
                errors.append("\(quality): \(error.localizedDescription)")
            }
        }
        let detail = errors.prefix(3).joined(separator: "；")
        throw NeteaseServiceError.message("没有拿到歌曲音频地址：\(track.artist) - \(track.title)。\(detail.isEmpty ? "可能是版权受限或该曲源不可用。" : detail)")
    }

    private func resolveNextPlayableTrackAndURL(manual: Bool, maxCandidates: Int? = nil) async throws -> (track: SoulTrack, audioURL: URL)? {
        let allCandidates = nextTrackCandidates(manual: manual)
        let candidates = maxCandidates.map { Array(allCandidates.prefix($0)) } ?? allCandidates
        guard candidates.isEmpty == false else { return nil }

        for candidate in candidates {
            do {
                let audioURL = try await resolveBridgeAudioURL(for: candidate)
                nextTrack = candidate
                return (candidate, audioURL)
            } catch {
                markTrackUnavailable(candidate, reason: error.localizedDescription)
            }
        }
        updateNextTrack()
        return nil
    }

    private func playNextAvailableTrack(manual: Bool) async {
        do {
            guard let playableNext = try await resolveNextPlayableTrackAndURL(manual: manual) else {
                isPlaying = false
                elapsed = duration
                downloadStatus = manual ? "已经到达歌单末尾" : "播放完成"
                appendLog("info", manual ? "已经到达歌单末尾或没有可播放歌曲。" : "没有可播放的下一首，播放已结束。")
                return
            }
            appendLog("info", manual ? "切到下一首：\(playableNext.track.title)。" : "歌曲播放结束，自动切到下一首：\(playableNext.track.title)。")
            playTrack(playableNext.track)
        } catch {
            appendLog("error", "查找下一首可播放歌曲失败：\(error.localizedDescription)")
        }
    }

    private func markTrackUnavailable(_ track: SoulTrack, reason: String) {
        let inserted = unavailableTrackIDs.insert(track.id).inserted
        if nextTrack?.id == track.id {
            updateNextTrack()
        }
        if inserted {
            appendLog("error", "已跳过不可播放歌曲：\(track.artist) - \(track.title)。\(reason)")
        }
    }

    private func cancelPreparedAiDjTransition() {
        transitionTask?.cancel()
        transitionTask = nil
        preparedTransition = nil
        audioEngine.cancelPreparedBridge()
        aiDjTransitionSummary = ""
    }

    private func currentTrackIndex() -> Int? {
        selectedTracks.firstIndex { $0.id == currentTrack.id }
    }

    private func nextTrackCandidate(manual: Bool) -> SoulTrack? {
        nextTrackCandidates(manual: manual).first
    }

    private func nextTrackCandidates(manual: Bool) -> [SoulTrack] {
        guard selectedTracks.isEmpty == false else { return [] }
        func isAvailable(_ track: SoulTrack) -> Bool {
            unavailableTrackIDs.contains(track.id) == false
        }
        guard let index = currentTrackIndex() else {
            return selectedTracks.filter(isAvailable)
        }

        switch playbackMode {
        case .repeatOne where manual == false:
            let current = selectedTracks[index]
            return isAvailable(current) ? [current] : []
        case .shuffle:
            guard selectedTracks.count > 1 else {
                return selectedTracks.filter(isAvailable)
            }
            let candidates = selectedTracks.filter { $0.id != currentTrack.id && isAvailable($0) }
            return candidates.shuffled()
        case .repeatAll:
            guard selectedTracks.count > 1 else {
                let current = selectedTracks[index]
                return isAvailable(current) ? [current] : []
            }
            var candidates: [SoulTrack] = []
            for offset in 1...selectedTracks.count {
                let candidate = selectedTracks[(index + offset) % selectedTracks.count]
                if candidate.id != currentTrack.id, isAvailable(candidate) {
                    candidates.append(candidate)
                }
            }
            return candidates
        case .ordered, .repeatOne:
            let nextIndex = index + 1
            guard selectedTracks.indices.contains(nextIndex) else { return [] }
            return selectedTracks[nextIndex..<selectedTracks.count].filter(isAvailable)
        }
    }

    private func handlePlaybackFinishFallbackIfNeeded() {
        guard isPlaying,
              isPreparingPlayback == false,
              currentTrack.id != SoulTrack.placeholder.id,
              duration > 0,
              elapsed >= max(0, duration - 0.35) else {
            return
        }
        let key = currentPlaybackFinishKey()
        guard finishFallbackTrackKey != key else { return }
        finishFallbackTrackKey = key
        appendLog("info", "检测到歌曲已到结尾，执行自动下一首兜底检查。")
        handleMusicFinished()
    }

    private func currentPlaybackFinishKey() -> String {
        "\(currentTrack.id)|\(currentTrack.localPath)"
    }

    private func previousTrackCandidate() -> SoulTrack? {
        guard selectedTracks.isEmpty == false else { return nil }
        guard let index = currentTrackIndex() else { return selectedTracks.first }

        switch playbackMode {
        case .shuffle:
            guard selectedTracks.count > 1 else { return selectedTracks.first }
            return selectedTracks.filter { $0.id != currentTrack.id }.randomElement()
        case .repeatAll:
            let previousIndex = (index - 1 + selectedTracks.count) % selectedTracks.count
            return selectedTracks[previousIndex]
        case .ordered, .repeatOne:
            let previousIndex = index - 1
            guard selectedTracks.indices.contains(previousIndex) else { return nil }
            return selectedTracks[previousIndex]
        }
    }

    private func updateNextTrack() {
        nextTrack = nextTrackCandidate(manual: true)
    }

    private func rememberLocalPath(for track: SoulTrack) {
        selectedTracks = selectedTracks.map { $0.id == track.id ? track : $0 }
    }

    private func trackPayload(_ track: SoulTrack) -> [String: Any] {
        [
            "id": track.id,
            "title": track.title,
            "artist": track.artist,
            "album": track.album,
            "duration": track.duration,
            "localPath": track.localPath,
            "coverURL": track.coverURL ?? ""
        ]
    }

    private func handlePlaybackError(_ error: Error) {
        streamFallbackTask?.cancel()
        isPreparingPlayback = false
        preparingTrackID = nil
        downloadStatus = "播放失败"
        isPlaying = false
        aiHostMessage = "播放失败：\(error.localizedDescription)"
        appendLog("error", error.localizedDescription)
    }

    private func appendLog(_ level: String, _ message: String) {
        logs.append(DJLogEntry(level: level, message: message))
        logs = Array(logs.suffix(80))
    }

    private func formatTime(_ value: Double) -> String {
        let int = max(0, Int(value))
        return "\(int / 60):\(String(format: "%02d", int % 60))"
    }

    private enum Keys {
        static let playbackMode = "soulDJ.player.playbackMode"
        static let volume = "soulDJ.player.volume"
    }
}

private struct PreparedTransition {
    let key: String
    let from: SoulTrack
    let to: SoulTrack
    let script: String
    let audioPath: String
    let nextAudioURL: URL
    let duckStartSeconds: Double
    let ttsStartSeconds: Double
    let nextStartSeconds: Double
    let ttsDurationSeconds: Double
    var duckStarted: Bool
    var ttsPlayed: Bool
    var crossfadeStarted: Bool
}
