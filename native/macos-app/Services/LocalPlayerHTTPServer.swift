import Foundation
import Network

final class LocalPlayerHTTPServer {
    private let audioEngine: LocalAudioEngine
    private var listener: NWListener?

    init(audioEngine: LocalAudioEngine) {
        self.audioEngine = audioEngine
    }

    func start(port: UInt16 = 54641) {
        do {
            let nwPort = NWEndpoint.Port(rawValue: port)!
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            let listener = try NWListener(using: parameters, on: nwPort)
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.stateUpdateHandler = { state in
                print("Local player HTTP server state: \(state)")
            }
            listener.start(queue: DispatchQueue(label: "ai-dj.local-player.http"))
            self.listener = listener
            print("Local player HTTP server starting on 127.0.0.1:\(port)")
        } catch {
            print("Local player HTTP server failed: \(error.localizedDescription)")
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: .global())
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1_000_000) { [weak self] data, _, _, _ in
            guard let self else {
                connection.cancel()
                return
            }
            let request = HTTPRequest(data: data ?? Data())
            let payload = self.route(request)
            let response = self.httpResponse(payload)
            connection.send(content: response, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    private func route(_ request: HTTPRequest) -> [String: Any] {
        do {
            switch (request.method, request.path) {
            case ("GET", "/status"):
                return audioEngine.status()
            case ("POST", "/music/load"):
                let path = request.body["path"] as? String ?? ""
                let track = request.body["track"] as? [String: Any] ?? [:]
                let autoplay = request.body["autoplay"] as? Bool ?? false
                let volume = Float((request.body["volume"] as? NSNumber)?.doubleValue ?? 1)
                return try audioEngine.loadMusic(path: path, track: track, autoplay: autoplay, volume: volume)
            case ("POST", "/music/play"):
                return try audioEngine.play()
            case ("POST", "/music/pause"):
                return audioEngine.pause()
            case ("POST", "/music/volume"):
                let volume = Float((request.body["volume"] as? NSNumber)?.doubleValue ?? 1)
                return audioEngine.setMusicVolume(volume)
            case ("POST", "/music/seek"):
                let seconds = (request.body["seconds"] as? NSNumber)?.doubleValue ?? 0
                return try audioEngine.seekMusic(to: seconds)
            case ("POST", "/music/stop"):
                return audioEngine.stop()
            case ("POST", "/tts/play"):
                let path = request.body["path"] as? String ?? ""
                let duckVolume = Float((request.body["duckVolume"] as? NSNumber)?.doubleValue ?? 0.28)
                let fadeMs = (request.body["fadeMs"] as? NSNumber)?.intValue ?? 720
                let ttsGain = Float((request.body["ttsGain"] as? NSNumber)?.doubleValue ?? 1.08)
                return try audioEngine.playTTS(path: path, duckVolume: duckVolume, fadeMs: fadeMs, ttsGain: ttsGain)
            default:
                return ["ok": false, "error": "Unknown route \(request.method) \(request.path)"]
            }
        } catch {
            return ["ok": false, "error": error.localizedDescription]
        }
    }

    private func httpResponse(_ payload: [String: Any]) -> Data {
        let statusLine = (payload["ok"] as? Bool) == false ? "HTTP/1.1 500 Internal Server Error" : "HTTP/1.1 200 OK"
        let body = (try? JSONSerialization.data(withJSONObject: payload, options: [])) ?? Data("{\"ok\":false}".utf8)
        var headers = "\(statusLine)\r\n"
        headers += "Content-Type: application/json; charset=utf-8\r\n"
        headers += "Content-Length: \(body.count)\r\n"
        headers += "Connection: close\r\n\r\n"
        var response = Data(headers.utf8)
        response.append(body)
        return response
    }
}

struct HTTPRequest {
    let method: String
    let path: String
    let body: [String: Any]

    init(data: Data) {
        let text = String(data: data, encoding: .utf8) ?? ""
        let parts = text.components(separatedBy: "\r\n\r\n")
        let head = parts.first ?? ""
        let bodyText = parts.dropFirst().joined(separator: "\r\n\r\n")
        let requestLine = head.components(separatedBy: "\r\n").first ?? ""
        let requestParts = requestLine.split(separator: " ")
        method = requestParts.indices.contains(0) ? String(requestParts[0]) : "GET"
        path = requestParts.indices.contains(1) ? String(requestParts[1]) : "/"
        if let bodyData = bodyText.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
            body = json
        } else {
            body = [:]
        }
    }
}
