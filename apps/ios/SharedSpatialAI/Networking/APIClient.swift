import Foundation

enum APIClientError: LocalizedError {
    case badStatus(Int, String)
    case decoding(Error)
    case encoding(Error)
    case conflict(String)
    case unreachable(String)
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .badStatus(let code, let body):
            let snippet = body.prefix(120)
            if code == 404 {
                return "Not found (HTTP 404). Check Scene ID in Settings."
            }
            if code >= 500 {
                return "API error \(code). Is the server running?"
            }
            return "HTTP \(code): \(snippet)"
        case .decoding:
            return "Unexpected API response — check the server is Shared Spatial AI."
        case .encoding:
            return "Could not encode request."
        case .conflict:
            return "Scene version conflict — refreshed; try again."
        case .unreachable(let detail):
            return "Cannot reach API at \(APIConfig.baseURL.absoluteString). \(detail)"
        case .invalidURL:
            return "Invalid API URL in Settings."
        }
    }
}

/// Thin client for the Shared Spatial AI FastAPI surface used by iOS.
actor APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 20
            config.timeoutIntervalForResource = 45
            config.waitsForConnectivity = false
            self.session = URLSession(configuration: config)
        }
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    func fetchScene(sceneId: String) async throws -> SceneDTO {
        let url = try endpoint("scene/\(sceneId)")
        let data = try await data(from: url)
        return try decode(SceneDTO.self, from: data)
    }

    /// POST a full normalized scene (scan / demo export). Matches `POST /scene`.
    @discardableResult
    func postScene(_ scene: SceneDTO) async throws -> SceneDTO {
        let url = try endpoint("scene")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encode(scene)
        let data = try await data(for: request)
        return try decode(SceneDTO.self, from: data)
    }

    /// PUT replace for an existing id. Matches `PUT /scene/{sceneId}`.
    @discardableResult
    func putScene(_ scene: SceneDTO) async throws -> SceneDTO {
        let url = try endpoint("scene/\(scene.sceneId)")
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encode(scene)
        let data = try await data(for: request)
        return try decode(SceneDTO.self, from: data)
    }

    func applyOperations(
        sceneId: String,
        baseVersion: Int,
        operations: [SceneOperationDTO],
        actorId: String = APIConfig.actorId
    ) async throws -> OperationsResultDTO {
        let url = try endpoint("scene/\(sceneId)/operations")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let envelope = OperationEnvelopeDTO(
            baseVersion: baseVersion,
            actorId: actorId,
            opId: UUID().uuidString,
            operations: operations
        )
        request.httpBody = try encode(envelope)
        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 409 {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw APIClientError.conflict(body)
            }
            try Self.throwIfNeeded(response, data: data)
            return try decode(OperationsResultDTO.self, from: data)
        } catch let error as APIClientError {
            throw error
        } catch {
            throw mapTransport(error)
        }
    }

    /// GET /catalog — full product list (name, price, modelUrl, productUrl).
    func fetchCatalog() async throws -> [CatalogItemDTO] {
        let url = try endpoint("catalog")
        let data = try await data(from: url)
        return try decode([CatalogItemDTO].self, from: data)
    }

    /// Lightweight connectivity probe for Settings / scan gate.
    func healthPing() async throws {
        let url = try endpoint("catalog")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        _ = try await data(for: request)
    }

    /// POST /ai/layout — hybrid planner ops (not applied until client Accept).
    func postAiLayout(_ payload: LayoutRequestDTO) async throws -> LayoutResponseDTO {
        let url = try endpoint("ai/layout")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        request.httpBody = try encode(payload)
        let data = try await data(for: request)
        return try decode(LayoutResponseDTO.self, from: data)
    }

    /// POST /scene/{id}/invites — shareable join token for the web twin.
    func createInvite(sceneId: String, label: String? = nil) async throws -> SceneInviteDTO {
        let url = try endpoint("scene/\(sceneId)/invites")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        struct Body: Encodable {
            var actorId: String
            var label: String?
        }
        request.httpBody = try encode(Body(actorId: APIConfig.actorId, label: label))
        let data = try await data(for: request)
        return try decode(SceneInviteDTO.self, from: data)
    }

    /// GET /scene/{id}/invites/default
    func defaultInvite(sceneId: String) async throws -> SceneInviteDTO {
        let url = try endpoint("scene/\(sceneId)/invites/default")
        let data = try await data(from: url)
        return try decode(SceneInviteDTO.self, from: data)
    }

    // MARK: - Internals

    private func endpoint(_ path: String) throws -> URL {
        let base = APIConfig.baseURL
        guard base.scheme != nil else { throw APIClientError.invalidURL }
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return base.appending(path: trimmed)
    }

    private func data(from url: URL) async throws -> Data {
        do {
            let (data, response) = try await session.data(from: url)
            try Self.throwIfNeeded(response, data: data)
            return data
        } catch let error as APIClientError {
            throw error
        } catch {
            throw mapTransport(error)
        }
    }

    private func data(for request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request)
            try Self.throwIfNeeded(response, data: data)
            return data
        } catch let error as APIClientError {
            throw error
        } catch {
            throw mapTransport(error)
        }
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        do {
            return try encoder.encode(value)
        } catch {
            throw APIClientError.encoding(error)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw APIClientError.decoding(error)
        }
    }

    private func mapTransport(_ error: Error) -> APIClientError {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorNotConnectedToInternet:
                return .unreachable("No network connection.")
            case NSURLErrorTimedOut:
                return .unreachable("Request timed out — start `npm run dev:api` on your Mac.")
            case NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost:
                return .unreachable("Connection refused — set Mac LAN IP in Settings (device) and bind API to 0.0.0.0.")
            default:
                return .unreachable(ns.localizedDescription)
            }
        }
        return .unreachable(error.localizedDescription)
    }

    private static func throwIfNeeded(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw APIClientError.badStatus(http.statusCode, body)
        }
    }
}
