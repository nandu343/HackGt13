import Foundation

/// Runtime config for the API host and active scene.
///
/// - Simulator → `localhost` / `127.0.0.1` reaches the Mac running uvicorn.
/// - Physical device → set your Mac's LAN IP in Settings (or env `SHARED_SPATIAL_API_URL`).
enum APIConfig {
    static let defaultSceneId = "scene_party_001"
    static let actorId = "ios_scaffold"

    private static let baseURLKey = "ssa_api_base_url"
    private static let sceneIdKey = "ssa_scene_id"

    /// Override at build time, via Settings UI, or env `SHARED_SPATIAL_API_URL`.
    static var baseURL: URL {
        if let raw = ProcessInfo.processInfo.environment["SHARED_SPATIAL_API_URL"],
           let url = URL(string: raw), !raw.isEmpty {
            return url
        }
        if let saved = UserDefaults.standard.string(forKey: baseURLKey),
           let url = URL(string: saved), !saved.isEmpty {
            return url
        }
        #if targetEnvironment(simulator)
        return URL(string: "http://127.0.0.1:8000")!
        #else
        return URL(string: "http://127.0.0.1:8000")!
        #endif
    }

    static var sceneId: String {
        let saved = UserDefaults.standard.string(forKey: sceneIdKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let saved, !saved.isEmpty { return saved }
        return defaultSceneId
    }

    static func setBaseURLString(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: baseURLKey)
        } else {
            UserDefaults.standard.set(trimmed, forKey: baseURLKey)
        }
    }

    static func setSceneId(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: sceneIdKey)
        } else {
            UserDefaults.standard.set(trimmed, forKey: sceneIdKey)
        }
    }

    /// Web twin join URL for the current scene (+ optional invite token).
    static func webJoinURL(sceneId: String, inviteToken: String? = nil) -> URL? {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        // API is :8000; web twin is typically :3000 on the same host.
        if components?.port == 8000 {
            components?.port = 3000
        }
        components?.path = "/"
        var items = [URLQueryItem(name: "scene", value: sceneId)]
        if let inviteToken, !inviteToken.isEmpty {
            items.append(URLQueryItem(name: "invite", value: inviteToken))
        }
        components?.queryItems = items
        return components?.url
    }
}
