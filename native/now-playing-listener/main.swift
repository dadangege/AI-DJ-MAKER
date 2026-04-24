import Foundation
import Dispatch

typealias InfoCallback = @convention(block) (CFDictionary?) -> Void
typealias BoolCallback = @convention(block) (Bool) -> Void
typealias StringCallback = @convention(block) (CFString?) -> Void

@_silgen_name("MRMediaRemoteGetNowPlayingInfo")
func MRMediaRemoteGetNowPlayingInfo(_ queue: DispatchQueue, _ completion: @escaping InfoCallback)

@_silgen_name("MRMediaRemoteGetNowPlayingApplicationIsPlaying")
func MRMediaRemoteGetNowPlayingApplicationIsPlaying(_ queue: DispatchQueue, _ completion: @escaping BoolCallback)

@_silgen_name("MRMediaRemoteGetNowPlayingApplicationDisplayID")
func MRMediaRemoteGetNowPlayingApplicationDisplayID(_ queue: DispatchQueue, _ completion: @escaping StringCallback)

@_silgen_name("MRMediaRemoteRegisterForNowPlayingNotifications")
func MRMediaRemoteRegisterForNowPlayingNotifications(_ queue: DispatchQueue)

let queue = DispatchQueue.main
let outputQueue = DispatchQueue(label: "ai-dj.now-playing.output")

MRMediaRemoteRegisterForNowPlayingNotifications(queue)

Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
    emitNowPlayingState()
}

emitNowPlayingState()
RunLoop.main.run()

func emitNowPlayingState() {
    let group = DispatchGroup()
    var rawInfo: [AnyHashable: Any] = [:]
    var isPlaying = false
    var sourceApp: String?

    group.enter()
    MRMediaRemoteGetNowPlayingInfo(queue) { info in
        rawInfo = (info as? [AnyHashable: Any]) ?? [:]
        group.leave()
    }

    group.enter()
    MRMediaRemoteGetNowPlayingApplicationIsPlaying(queue) { playing in
        isPlaying = playing
        group.leave()
    }

    group.enter()
    MRMediaRemoteGetNowPlayingApplicationDisplayID(queue) { appId in
        sourceApp = appId as String?
        group.leave()
    }

    group.notify(queue: outputQueue) {
        let state = normalizeState(info: rawInfo, isPlaying: isPlaying, sourceApp: sourceApp)
        emitJSON(state)
    }
}

func normalizeState(info: [AnyHashable: Any], isPlaying: Bool, sourceApp: String?) -> [String: Any] {
    let title = stringValue(info, [
        "kMRMediaRemoteNowPlayingInfoTitle",
        "title",
        "Title"
    ])
    let artist = stringValue(info, [
        "kMRMediaRemoteNowPlayingInfoArtist",
        "artist",
        "Artist"
    ])
    let album = stringValue(info, [
        "kMRMediaRemoteNowPlayingInfoAlbum",
        "album",
        "Album"
    ])
    let duration = doubleValue(info, [
        "kMRMediaRemoteNowPlayingInfoDuration",
        "duration",
        "Duration"
    ])
    let elapsed = doubleValue(info, [
        "kMRMediaRemoteNowPlayingInfoElapsedTime",
        "elapsed",
        "ElapsedTime"
    ])
    let playbackRate = doubleValue(info, [
        "kMRMediaRemoteNowPlayingInfoPlaybackRate",
        "playbackRate",
        "PlaybackRate"
    ]) ?? (isPlaying ? 1.0 : 0.0)
    let queueIndex = intValue(info, [
        "kMRMediaRemoteNowPlayingInfoQueueIndex",
        "queueIndex",
        "QueueIndex"
    ])
    let totalQueueCount = intValue(info, [
        "kMRMediaRemoteNowPlayingInfoTotalQueueCount",
        "totalQueueCount",
        "TotalQueueCount"
    ])
    let upNextItemCount = intValue(info, [
        "_upNextItemCount",
        "upNextItemCount",
        "UpNextItemCount"
    ])

    let hasTrack = !(title ?? "").isEmpty
    let playbackState = isPlaying || playbackRate > 0.01 ? "playing" : (hasTrack ? "paused" : "stopped")
    let trackIdParts = [
        artist ?? "",
        title ?? "",
        album ?? "",
        duration.map { String(format: "%.3f", $0) } ?? ""
    ]
    let trackId = trackIdParts.joined(separator: "|")
    let queue = requestPlaybackQueueSnapshot()

    var payload: [String: Any] = [
        "state": playbackState,
        "title": title as Any,
        "artist": artist as Any,
        "album": album as Any,
        "duration": duration as Any,
        "elapsed": elapsed as Any,
        "playbackRate": playbackRate,
        "sourceApp": sourceApp as Any,
        "trackId": trackId,
        "queueIndex": queueIndex as Any,
        "totalQueueCount": totalQueueCount as Any,
        "upNextItemCount": upNextItemCount as Any
    ]

    if let queue {
        payload.merge(queue, uniquingKeysWith: { _, new in new })
    }

    return payload
}

func stringValue(_ info: [AnyHashable: Any], _ candidates: [String]) -> String? {
    for candidate in candidates {
        if let value = valueForKey(info, candidate) {
            if let string = value as? String {
                return string
            }
            if let number = value as? NSNumber {
                return number.stringValue
            }
        }
    }
    return nil
}

func doubleValue(_ info: [AnyHashable: Any], _ candidates: [String]) -> Double? {
    for candidate in candidates {
        if let value = valueForKey(info, candidate) {
            if let double = value as? Double {
                return double
            }
            if let number = value as? NSNumber {
                return number.doubleValue
            }
            if let string = value as? String, let double = Double(string) {
                return double
            }
        }
    }
    return nil
}

func intValue(_ info: [AnyHashable: Any], _ candidates: [String]) -> Int? {
    for candidate in candidates {
        if let value = valueForKey(info, candidate) {
            if let int = value as? Int {
                return int
            }
            if let number = value as? NSNumber {
                return number.intValue
            }
            if let string = value as? String, let int = Int(string) {
                return int
            }
        }
    }
    return nil
}

func requestPlaybackQueueSnapshot() -> [String: Any]? {
    guard let requestClass = NSClassFromString("MRNowPlayingRequest") as? NSObject.Type else {
        return nil
    }

    let selector = NSSelectorFromString("localPlaybackQueue")
    guard requestClass.responds(to: selector), let unmanaged = (requestClass as AnyObject).perform(selector) else {
        return nil
    }

    guard let queueObject = unmanaged.takeUnretainedValue() as? NSObject else {
        return nil
    }

    guard let rawItems = queueObject.value(forKey: "contentItems") as? [Any] else {
        return nil
    }

    let queueLocation = intFromObject(queueObject, ["location"]) ?? 0
    let queueCount = rawItems.count

    var snapshot: [String: Any] = [
        "queueAvailable": true,
        "queueLocation": queueLocation,
        "queueItemCount": queueCount
    ]

    if let currentItem = summaryForContentItem(rawItems[safe: queueLocation]) {
        snapshot["queueCurrentTitle"] = currentItem["title"] as Any
        snapshot["queueCurrentArtist"] = currentItem["artist"] as Any
        snapshot["queueCurrentAlbum"] = currentItem["album"] as Any
        snapshot["queueCurrentIdentifier"] = currentItem["identifier"] as Any
    }

    if queueLocation + 1 < queueCount, let nextItem = summaryForContentItem(rawItems[safe: queueLocation + 1]) {
        snapshot["nextTrackAvailable"] = true
        snapshot["nextTitle"] = nextItem["title"] as Any
        snapshot["nextArtist"] = nextItem["artist"] as Any
        snapshot["nextAlbum"] = nextItem["album"] as Any
        snapshot["nextIdentifier"] = nextItem["identifier"] as Any
        snapshot["nextDuration"] = nextItem["duration"] as Any
    } else {
        snapshot["nextTrackAvailable"] = false
    }

    return snapshot
}

func summaryForContentItem(_ item: Any?) -> [String: Any]? {
    guard let item = item as? NSObject else {
        return nil
    }

    let metadata = item.value(forKey: "metadata") as? NSObject
    let title = stringFromObject(metadata, [
        "title",
        "__title",
        "localizedTitle"
    ]) ?? ""
    let artist = stringFromObject(metadata, [
        "trackArtistName",
        "artist",
        "albumArtistName"
    ]) ?? ""
    let album = stringFromObject(metadata, [
        "albumName",
        "album",
        "seriesName"
    ]) ?? ""
    let duration = doubleFromObject(metadata, [
        "duration",
        "playbackProgress"
    ])
    let identifier = intFromObject(item, ["identifier"]) ?? intFromObject(item, ["requestIdentifier"])

    return [
      "title": title,
      "artist": artist,
        "album": album,
        "duration": duration as Any,
        "identifier": identifier as Any
    ]
}

func stringFromObject(_ object: NSObject?, _ candidates: [String]) -> String? {
    guard let object else { return nil }
    for candidate in candidates {
        if let value = object.value(forKey: candidate) {
            if let string = value as? String {
                return string
            }
            if let number = value as? NSNumber {
                return number.stringValue
            }
        }
    }
    return nil
}

func doubleFromObject(_ object: NSObject?, _ candidates: [String]) -> Double? {
    guard let object else { return nil }
    for candidate in candidates {
        if let value = object.value(forKey: candidate) {
            if let double = value as? Double {
                return double
            }
            if let number = value as? NSNumber {
                return number.doubleValue
            }
            if let string = value as? String, let double = Double(string) {
                return double
            }
        }
    }
    return nil
}

func intFromObject(_ object: NSObject, _ candidates: [String]) -> Int? {
    for candidate in candidates {
        if let value = object.value(forKey: candidate) {
            if let int = value as? Int {
                return int
            }
            if let number = value as? NSNumber {
                return number.intValue
            }
            if let string = value as? String, let int = Int(string) {
                return int
            }
        }
    }
    return nil
}

extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}

func valueForKey(_ info: [AnyHashable: Any], _ keyName: String) -> Any? {
    for (key, value) in info {
        if String(describing: key) == keyName {
            return value
        }
    }
    return nil
}

func emitJSON(_ payload: [String: Any]) {
    var normalized: [String: Any] = [:]
    for (key, value) in payload {
        if let optional = value as? OptionalProtocol, optional.isNil {
            normalized[key] = NSNull()
        } else {
            normalized[key] = value
        }
    }

    do {
        let data = try JSONSerialization.data(withJSONObject: normalized, options: [])
        if let line = String(data: data, encoding: .utf8) {
            print(line)
            fflush(stdout)
        }
    } catch {
        let fallback: [String: Any] = [
            "error": "json_encode_failed",
            "message": error.localizedDescription
        ]
        if let data = try? JSONSerialization.data(withJSONObject: fallback, options: []),
           let line = String(data: data, encoding: .utf8) {
            print(line)
            fflush(stdout)
        }
    }
}

protocol OptionalProtocol {
    var isNil: Bool { get }
}

extension Optional: OptionalProtocol {
    var isNil: Bool {
        self == nil
    }
}
