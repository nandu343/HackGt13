import Foundation

/// Lightweight scene-channel client for presence join + free-space `draw_stroke` sync.
/// Mirrors the web twin contract on `WS /ws/scene/{sceneId}`.
@MainActor
final class SceneWebSocket {
    var onStrokesSnapshot: (([DrawingStrokeDTO]) -> Void)?
    var onStroke: ((DrawingStrokeDTO) -> Void)?
    var onPresence: (([PresenceUserDTO]) -> Void)?
    var onConnectionChange: ((Bool) -> Void)?

    private var task: URLSessionWebSocketTask?
    private var sceneId: String = ""
    private var receiveLoopRunning = false

    func connect(sceneId: String) {
        disconnect()
        self.sceneId = sceneId
        guard let url = Self.wsURL(sceneId: sceneId) else {
            onConnectionChange?(false)
            return
        }
        let session = URLSession(configuration: .default)
        let ws = session.webSocketTask(with: url)
        task = ws
        ws.resume()
        onConnectionChange?(true)
        sendJoin()
        receiveLoopRunning = true
        receiveNext()
    }

    func disconnect() {
        receiveLoopRunning = false
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        onConnectionChange?(false)
    }

    func sendStroke(_ stroke: DrawingStrokeDTO) {
        guard let data = try? JSONEncoder.api.encode(StrokeEnvelope(type: "draw_stroke", stroke: stroke)),
              let text = String(data: data, encoding: .utf8) else { return }
        task?.send(.string(text)) { _ in }
    }

    func sendClear(scope: String = "own") {
        let payload: [String: Any] = [
            "type": "draw_clear",
            "actorId": APIConfig.actorId,
            "scope": scope
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else { return }
        task?.send(.string(text)) { _ in }
    }

    private func sendJoin() {
        let user: [String: Any] = [
            "userId": APIConfig.actorId,
            "displayName": "iOS AR",
            "color": "#6eb4c8",
            "voiceEnabled": false
        ]
        let payload: [String: Any] = ["type": "join", "user": user]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else { return }
        task?.send(.string(text)) { _ in }
    }

    private func receiveNext() {
        guard receiveLoopRunning, let task else { return }
        task.receive { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .failure:
                    self.onConnectionChange?(false)
                    self.receiveLoopRunning = false
                case .success(let message):
                    self.handle(message)
                    self.receiveNext()
                }
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let data: Data?
        switch message {
        case .string(let text): data = text.data(using: .utf8)
        case .data(let d): data = d
        @unknown default: data = nil
        }
        guard let data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }

        switch type {
        case "welcome", "draw_snapshot", "draw_clear":
            if let raw = json["strokes"] as? [[String: Any]] {
                let strokes = raw.compactMap { Self.decodeStroke($0) }
                onStrokesSnapshot?(strokes)
            }
        case "draw_stroke":
            if let raw = json["stroke"] as? [String: Any], let stroke = Self.decodeStroke(raw) {
                onStroke?(stroke)
            }
        case "presence":
            if let raw = json["presence"] as? [[String: Any]] {
                let users = raw.compactMap { Self.decodePresence($0) }
                onPresence?(users)
            }
        default:
            break
        }
    }

    private static func decodeStroke(_ raw: [String: Any]) -> DrawingStrokeDTO? {
        guard let data = try? JSONSerialization.data(withJSONObject: raw) else { return nil }
        return try? JSONDecoder.api.decode(DrawingStrokeDTO.self, from: data)
    }

    private static func decodePresence(_ raw: [String: Any]) -> PresenceUserDTO? {
        guard let data = try? JSONSerialization.data(withJSONObject: raw) else { return nil }
        return try? JSONDecoder.api.decode(PresenceUserDTO.self, from: data)
    }

    private static func wsURL(sceneId: String) -> URL? {
        var components = URLComponents(url: APIConfig.baseURL, resolvingAgainstBaseURL: false)
        let scheme = (components?.scheme == "https") ? "wss" : "ws"
        components?.scheme = scheme
        components?.path = "/ws/scene/\(sceneId)"
        components?.query = nil
        return components?.url
    }
}

private struct StrokeEnvelope: Encodable {
    let type: String
    let stroke: DrawingStrokeDTO
}

extension JSONEncoder {
    static let api: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .useDefaultKeys
        return e
    }()
}

extension JSONDecoder {
    static let api: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .useDefaultKeys
        return d
    }()
}
