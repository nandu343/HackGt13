import Foundation

enum APIClientError: LocalizedError {
    case badStatus(Int, String)
    case decoding(Error)
    case encoding(Error)
    case conflict(String)

    var errorDescription: String? {
        switch self {
        case .badStatus(let code, let body):
            return "HTTP \(code): \(body)"
        case .decoding(let error):
            return "Decode failed: \(error.localizedDescription)"
        case .encoding(let error):
            return "Encode failed: \(error.localizedDescription)"
        case .conflict(let message):
            return "Version conflict: \(message)"
        }
    }
}

/// Thin client for the Shared Spatial AI FastAPI surface used by iOS.
actor APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(session: URLSession = .shared) {
        self.session = session
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    func fetchScene(sceneId: String) async throws -> SceneDTO {
        let url = APIConfig.baseURL.appending(path: "scene/\(sceneId)")
        let (data, response) = try await session.data(from: url)
        try Self.throwIfNeeded(response, data: data)
        do {
            return try decoder.decode(SceneDTO.self, from: data)
        } catch {
            throw APIClientError.decoding(error)
        }
    }

    /// POST a full normalized scene (RoomPlan export). Matches `POST /scene`.
    @discardableResult
    func postScene(_ scene: SceneDTO) async throws -> SceneDTO {
        let url = APIConfig.baseURL.appending(path: "scene")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try encoder.encode(scene)
        } catch {
            throw APIClientError.encoding(error)
        }
        let (data, response) = try await session.data(for: request)
        try Self.throwIfNeeded(response, data: data)
        do {
            return try decoder.decode(SceneDTO.self, from: data)
        } catch {
            throw APIClientError.decoding(error)
        }
    }

    /// PUT replace for an existing id. Matches `PUT /scene/{sceneId}`.
    @discardableResult
    func putScene(_ scene: SceneDTO) async throws -> SceneDTO {
        let url = APIConfig.baseURL.appending(path: "scene/\(scene.sceneId)")
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try encoder.encode(scene)
        } catch {
            throw APIClientError.encoding(error)
        }
        let (data, response) = try await session.data(for: request)
        try Self.throwIfNeeded(response, data: data)
        do {
            return try decoder.decode(SceneDTO.self, from: data)
        } catch {
            throw APIClientError.decoding(error)
        }
    }

    func applyOperations(
        sceneId: String,
        baseVersion: Int,
        operations: [SceneOperationDTO],
        actorId: String = APIConfig.actorId
    ) async throws -> OperationsResultDTO {
        let url = APIConfig.baseURL.appending(path: "scene/\(sceneId)/operations")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let envelope = OperationEnvelopeDTO(
            baseVersion: baseVersion,
            actorId: actorId,
            opId: UUID().uuidString,
            operations: operations
        )
        do {
            request.httpBody = try encoder.encode(envelope)
        } catch {
            throw APIClientError.encoding(error)
        }
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 409 {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw APIClientError.conflict(body)
        }
        try Self.throwIfNeeded(response, data: data)
        do {
            return try decoder.decode(OperationsResultDTO.self, from: data)
        } catch {
            throw APIClientError.decoding(error)
        }
    }

    /// POST /ai/layout — hybrid planner ops (not applied until client Accept).
    func postAiLayout(_ payload: LayoutRequestDTO) async throws -> LayoutResponseDTO {
        let url = APIConfig.baseURL.appending(path: "ai/layout")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try encoder.encode(payload)
        } catch {
            throw APIClientError.encoding(error)
        }
        let (data, response) = try await session.data(for: request)
        try Self.throwIfNeeded(response, data: data)
        do {
            return try decoder.decode(LayoutResponseDTO.self, from: data)
        } catch {
            throw APIClientError.decoding(error)
        }
    }

    private static func throwIfNeeded(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw APIClientError.badStatus(http.statusCode, body)
        }
    }
}
