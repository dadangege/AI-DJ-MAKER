import AVFoundation
import Foundation
import Network

final class LocalAudioEngine {
    private let queue = DispatchQueue(label: "ai-dj.local-audio")
    private let engine = AVAudioEngine()
    private let musicNode = AVAudioPlayerNode()
    private let ttsNode = AVAudioPlayerNode()
    private var streamPlayer: AVPlayer?
    private var streamEndObserver: NSObjectProtocol?
    private var nextStreamPlayer: AVPlayer?
    private var nextStreamTrack: [String: Any] = [:]
    private var nextStreamPath = ""
    private var nextStreamDuration: Double = 0
    private var bridgeInProgress = false
    private var currentPath = ""
    private var currentTrack: [String: Any] = [:]
    private var duration: Double = 0
    private var startedAt: Date?
    private var pausedElapsed: Double = 0
    private var playing = false
    private var ttsPlaying = false
    private var musicVolume: Float = 1
    private var userMusicVolume: Float = 1
    private var playbackGeneration = 0
    private var fadeGeneration = 0
    private var streaming = false
    var onMusicFinished: (([String: Any]) -> Void)?
    var onSpectrumLevels: (([Float]) -> Void)?

    init() {
        engine.attach(musicNode)
        engine.attach(ttsNode)
        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        engine.connect(musicNode, to: engine.mainMixerNode, format: format)
        engine.connect(ttsNode, to: engine.mainMixerNode, format: format)
        musicNode.volume = musicVolume
        ttsNode.volume = 1.08
        installSpectrumTap()
        try? engine.start()
    }

    func loadMusic(path: String, track: [String: Any], autoplay: Bool, volume: Float) throws -> [String: Any] {
        try queue.sync {
            try ensureEngine()
            let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
            stopStreamLocked()
            musicNode.stop()
            currentPath = path
            currentTrack = track
            duration = Double(file.length) / file.processingFormat.sampleRate
            pausedElapsed = 0
            startedAt = nil
            playing = false
            userMusicVolume = clamp(volume)
            musicVolume = userMusicVolume
            musicNode.volume = userMusicVolume
            playbackGeneration += 1
            streaming = false
            scheduleMusic(file, from: 0, generation: playbackGeneration)
            if autoplay {
                musicNode.play()
                startedAt = Date()
                playing = true
            }
            return statusLocked()
        }
    }

    func loadMusicStream(url: URL, track: [String: Any], duration hintDuration: Double, autoplay: Bool, volume: Float) throws -> [String: Any] {
        try queue.sync {
            try ensureEngine()
            musicNode.stop()
            stopStreamLocked()

            let item = AVPlayerItem(url: url)
            let player = AVPlayer(playerItem: item)
            player.automaticallyWaitsToMinimizeStalling = false
            userMusicVolume = clamp(volume)
            musicVolume = userMusicVolume
            player.volume = userMusicVolume
            streamPlayer = player
            currentPath = url.absoluteString
            currentTrack = track
            duration = hintDuration
            pausedElapsed = 0
            startedAt = nil
            playing = false
            streaming = true
            playbackGeneration += 1
            let generation = playbackGeneration
            installCurrentStreamEndObserverLocked(for: item, generation: generation)

            if autoplay {
                player.play()
                startedAt = Date()
                playing = true
            }
            return statusLocked()
        }
    }

    func play() throws -> [String: Any] {
        try queue.sync {
            try ensureEngine()
            guard !currentPath.isEmpty else {
                throw LocalPlayerError.message("没有加载音乐文件。")
            }
            if streaming {
                streamPlayer?.play()
                startedAt = Date()
                playing = true
                return statusLocked()
            }
            if pausedElapsed >= duration {
                let file = try AVAudioFile(forReading: URL(fileURLWithPath: currentPath))
                pausedElapsed = 0
                playbackGeneration += 1
                scheduleMusic(file, from: 0, generation: playbackGeneration)
            }
            if !playing {
                musicNode.play()
                startedAt = Date()
                playing = true
            }
            return statusLocked()
        }
    }

    func pause() -> [String: Any] {
        queue.sync {
            if playing {
                pausedElapsed = elapsedLocked()
                if streaming {
                    streamPlayer?.pause()
                } else {
                    musicNode.pause()
                }
                playing = false
                startedAt = nil
            }
            return statusLocked()
        }
    }

    func stop() -> [String: Any] {
        queue.sync {
            musicNode.stop()
            ttsNode.stop()
            stopStreamLocked()
            stopNextStreamLocked()
            currentPath = ""
            currentTrack = [:]
            duration = 0
            pausedElapsed = 0
            startedAt = nil
            playing = false
            ttsPlaying = false
            bridgeInProgress = false
            playbackGeneration += 1
            userMusicVolume = 1
            musicVolume = 1
            musicNode.volume = 1
            return statusLocked()
        }
    }

    func setMusicVolume(_ volume: Float) -> [String: Any] {
        queue.sync {
            userMusicVolume = clamp(volume)
            if !ttsPlaying {
                musicVolume = userMusicVolume
                musicNode.volume = userMusicVolume
                streamPlayer?.volume = userMusicVolume
            }
            return statusLocked()
        }
    }

    func seekMusic(to seconds: Double) throws -> [String: Any] {
        try queue.sync {
            try ensureEngine()
            guard !currentPath.isEmpty else {
                throw LocalPlayerError.message("没有加载音乐文件。")
            }

            let wasPlaying = playing
            let target = min(max(0, seconds), duration)
            if streaming {
                streamPlayer?.seek(to: CMTime(seconds: target, preferredTimescale: 600))
                pausedElapsed = target
                startedAt = wasPlaying ? Date() : nil
                playing = wasPlaying
                if wasPlaying {
                    streamPlayer?.play()
                }
                return statusLocked()
            }
            let file = try AVAudioFile(forReading: URL(fileURLWithPath: currentPath))
            musicNode.stop()
            playbackGeneration += 1
            pausedElapsed = target
            startedAt = nil
            playing = false
            scheduleMusic(file, from: target, generation: playbackGeneration)
            if wasPlaying {
                musicNode.play()
                startedAt = Date()
                playing = true
            }
            return statusLocked()
        }
    }

    func playTTS(path: String, duckVolume: Float, fadeMs: Int, ttsGain: Float) throws -> [String: Any] {
        try queue.sync {
            try ensureEngine()
            let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
            ttsNode.stop()
            ttsNode.volume = min(2.0, max(0.1, ttsGain))
            ttsPlaying = true
            let restoreVolume = userMusicVolume
            if musicVolume > min(clamp(duckVolume), restoreVolume) + 0.02 {
                fadeMusicLockedAsync(to: min(clamp(duckVolume), restoreVolume), fadeMs: fadeMs)
            }
            ttsNode.scheduleFile(file, at: nil) { [weak self] in
                self?.queue.async {
                    self?.ttsPlaying = false
                    self?.fadeMusicLockedAsync(to: restoreVolume, fadeMs: fadeMs)
                }
            }
            ttsNode.play()
            return statusLocked()
        }
    }

    func duckMusic(duckVolume: Float, fadeMs: Int) -> [String: Any] {
        queue.sync {
            let target = min(clamp(duckVolume), userMusicVolume)
            fadeMusicLockedAsync(to: target, fadeMs: fadeMs)
            return statusLocked()
        }
    }

    func preloadNextMusic(url: URL, track: [String: Any], duration hintDuration: Double, volume: Float) throws -> [String: Any] {
        try queue.sync {
            try ensureEngine()
            stopNextStreamLocked()
            let item = AVPlayerItem(url: url)
            let player = AVPlayer(playerItem: item)
            player.automaticallyWaitsToMinimizeStalling = false
            player.volume = 0
            nextStreamPlayer = player
            nextStreamTrack = track
            nextStreamPath = url.absoluteString
            nextStreamDuration = hintDuration
            return statusLocked()
        }
    }

    func startBridgeToPreloadedNext(crossfadeMs: Int, targetVolume: Float, onPromoted: @escaping ([String: Any]) -> Void) throws -> [String: Any] {
        try queue.sync {
            try ensureEngine()
            guard bridgeInProgress == false else { return statusLocked() }
            guard let nextPlayer = nextStreamPlayer else {
                throw LocalPlayerError.message("下一首还没有预加载。")
            }

            let currentPlayer = streamPlayer
            let currentMusicNode = musicNode
            let fromCurrentVolume = streaming ? (currentPlayer?.volume ?? musicVolume) : currentMusicNode.volume
            let toNextVolume = min(clamp(targetVolume), userMusicVolume)
            let nextTrackPayload = nextStreamTrack
            let nextPath = nextStreamPath
            let nextDuration = nextStreamDuration
            let generation = playbackGeneration + 1

            bridgeInProgress = true
            removeCurrentStreamEndObserverLocked()
            nextPlayer.volume = 0
            nextPlayer.seek(to: .zero)
            nextPlayer.play()

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else { return }
                let steps = max(1, min(48, crossfadeMs / 45))
                let delay = max(10_000, crossfadeMs * 1000 / max(1, steps))
                for index in 1...steps {
                    let progress = self.easeInOut(Float(index) / Float(steps))
                    let currentVolume = fromCurrentVolume * (1 - progress)
                    let nextVolume = toNextVolume * progress
                    currentPlayer?.volume = currentVolume
                    currentMusicNode.volume = currentVolume
                    nextPlayer.volume = nextVolume
                    usleep(useconds_t(delay))
                }

                self.queue.async {
                    guard self.bridgeInProgress else { return }
                    currentPlayer?.pause()
                    currentMusicNode.stop()
                    self.streamPlayer = nextPlayer
                    self.currentPath = nextPath
                    self.currentTrack = nextTrackPayload
                    self.duration = nextDuration
                    self.pausedElapsed = 0
                    self.startedAt = Date()
                    self.playing = true
                    self.streaming = true
                    self.musicVolume = toNextVolume
                    self.playbackGeneration = generation
                    self.nextStreamPlayer = nil
                    self.nextStreamTrack = [:]
                    self.nextStreamPath = ""
                    self.nextStreamDuration = 0
                    self.bridgeInProgress = false
                    if let item = nextPlayer.currentItem {
                        self.installCurrentStreamEndObserverLocked(for: item, generation: generation)
                    }
                    onPromoted(self.statusLocked())
                }
            }

            return statusLocked()
        }
    }

    func cancelPreparedBridge() {
        queue.sync {
            bridgeInProgress = false
            stopNextStreamLocked()
        }
    }

    func status() -> [String: Any] {
        queue.sync { statusLocked() }
    }

    private func scheduleMusic(_ file: AVAudioFile, from seconds: Double, generation: Int) {
        let sampleRate = file.processingFormat.sampleRate
        let startFrame = AVAudioFramePosition(min(Double(file.length), max(0, seconds) * sampleRate))
        let frameCount = AVAudioFrameCount(max(0, file.length - startFrame))
        musicNode.scheduleSegment(file, startingFrame: startFrame, frameCount: frameCount, at: nil) { [weak self] in
            self?.queue.async {
                guard let self else { return }
                guard self.playbackGeneration == generation else { return }
                self.pausedElapsed = self.duration
                self.startedAt = nil
                self.playing = false
                self.onMusicFinished?(self.statusLocked())
            }
        }
    }

    private func ensureEngine() throws {
        if !engine.isRunning {
            try engine.start()
        }
    }

    private func installSpectrumTap() {
        let mixer = engine.mainMixerNode
        let format = mixer.outputFormat(forBus: 0)
        mixer.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self, let channel = buffer.floatChannelData?[0] else { return }
            let frameCount = Int(buffer.frameLength)
            guard frameCount > 0 else { return }

            let barCount = 36
            let framesPerBar = max(1, frameCount / barCount)
            var levels: [Float] = []
            levels.reserveCapacity(barCount)

            for index in 0..<barCount {
                let start = min(frameCount - 1, index * framesPerBar)
                let end = index == barCount - 1 ? frameCount : min(frameCount, start + framesPerBar)
                guard end > start else {
                    levels.append(0)
                    continue
                }

                var sum: Float = 0
                for sampleIndex in start..<end {
                    sum += abs(channel[sampleIndex])
                }
                let average = sum / Float(end - start)
                let shaped = pow(min(1, average * 7.5), 0.62)
                levels.append(shaped)
            }

            DispatchQueue.main.async {
                self.onSpectrumLevels?(levels)
            }
        }
    }

    private func elapsedLocked() -> Double {
        if streaming, let streamPlayer {
            let seconds = streamPlayer.currentTime().seconds
            if seconds.isFinite {
                return duration > 0 ? min(duration, max(0, seconds)) : max(0, seconds)
            }
        }
        if playing, let startedAt {
            return min(duration, pausedElapsed + Date().timeIntervalSince(startedAt))
        }
        return min(duration, pausedElapsed)
    }

    private func statusLocked() -> [String: Any] {
        [
            "ok": true,
            "playing": playing,
            "ttsPlaying": ttsPlaying,
            "path": currentPath,
            "track": currentTrack,
            "elapsed": elapsedLocked(),
            "duration": duration,
            "musicVolume": musicVolume,
            "userMusicVolume": userMusicVolume,
            "streamRate": streamPlayer?.rate ?? 0,
            "streamStatus": streamStatusLocked(streamPlayer),
            "streamError": streamPlayer?.currentItem?.error?.localizedDescription ?? "",
            "bridgeInProgress": bridgeInProgress,
            "nextPreloaded": nextStreamPlayer != nil
        ]
    }

    private func streamStatusLocked(_ player: AVPlayer?) -> String {
        guard let item = player?.currentItem else { return "none" }
        switch item.status {
        case .unknown: return "unknown"
        case .readyToPlay: return "ready"
        case .failed: return "failed"
        @unknown default: return "unknown"
        }
    }

    private func fadeMusicLocked(to target: Float, fadeMs: Int) {
        let from = streaming ? (streamPlayer?.volume ?? musicVolume) : musicNode.volume
        let target = clamp(target)
        let steps = max(1, min(36, fadeMs / 35))
        let delay = max(10_000, fadeMs * 1000 / max(1, steps))
        for index in 1...steps {
            let progress = easeInOut(Float(index) / Float(steps))
            let next = from + ((target - from) * progress)
            musicNode.volume = next
            streamPlayer?.volume = next
            musicVolume = next
            usleep(useconds_t(delay))
        }
    }

    private func fadeMusicLockedAsync(to target: Float, fadeMs: Int) {
        let from = streaming ? (streamPlayer?.volume ?? musicVolume) : musicNode.volume
        let target = clamp(target)
        let steps = max(1, min(72, fadeMs / 28))
        let delay = max(10_000, fadeMs * 1000 / max(1, steps))
        fadeGeneration += 1
        let generation = fadeGeneration

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            for index in 1...steps {
                let progress = Float(index) / Float(steps)
                let next = from + ((target - from) * progress)
                self.queue.async {
                    guard self.fadeGeneration == generation else { return }
                    self.musicNode.volume = next
                    self.streamPlayer?.volume = next
                    self.musicVolume = next
                }
                usleep(useconds_t(delay))
            }
        }
    }

    private func easeInOut(_ value: Float) -> Float {
        let t = min(1, max(0, value))
        return t * t * (3 - 2 * t)
    }

    private func stopStreamLocked() {
        streamPlayer?.pause()
        streamPlayer = nil
        removeCurrentStreamEndObserverLocked()
        streaming = false
    }

    private func stopNextStreamLocked() {
        nextStreamPlayer?.pause()
        nextStreamPlayer = nil
        nextStreamTrack = [:]
        nextStreamPath = ""
        nextStreamDuration = 0
        bridgeInProgress = false
    }

    private func installCurrentStreamEndObserverLocked(for item: AVPlayerItem, generation: Int) {
        removeCurrentStreamEndObserverLocked()
        streamEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: nil
        ) { [weak self] _ in
            self?.queue.async {
                guard let self, self.playbackGeneration == generation, self.bridgeInProgress == false else { return }
                self.pausedElapsed = self.duration
                self.startedAt = nil
                self.playing = false
                self.onMusicFinished?(self.statusLocked())
            }
        }
    }

    private func removeCurrentStreamEndObserverLocked() {
        if let streamEndObserver {
            NotificationCenter.default.removeObserver(streamEndObserver)
            self.streamEndObserver = nil
        }
    }

    private func clamp(_ value: Float) -> Float {
        min(1, max(0, value))
    }
}

enum LocalPlayerError: Error, LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let message): return message
        }
    }
}
