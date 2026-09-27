import Foundation

/// Runtime config for the API host and active scene.
///
/// Priority: **Settings (UserDefaults)** → env `SHARED_SPATIAL_API_URL` → simulator/device default.
/// Saving in Settings always sticks across launches.
enum APIConfig {
    static let defaultSceneId = "scene_party_001"
    static let actorId = "ios_ar"

    private static let baseURLKey = "ssa_api_base_url"
    private static let sceneIdKey = "ssa_scene_id"

    /// Resolved API base. UserDefaults wins so the in-app Settings field sticks.
    static var baseURL: URL {
        if let saved = UserDefaults.standard.string(forKey: baseURLKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !saved.isEmpty,
           let url = URL(string: saved),
           url.scheme != nil {
            return url
        }
        if let raw = ProcessInfo.processInfo.environment["SHARED_SPATIAL_API_URL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty,
           let url = URL(string: raw) {
            return url
        }
        #if targetEnvironment(simulator)
        return URL(string: "http://127.0.0.1:8000")!
        #else
        // Device default — override in Settings with your Mac LAN IP.
        return URL(string: "http://127.0.0.1:8000")!
        #endif
    }

    static var sceneId: String {
        let saved = UserDefaults.standard.string(forKey: sceneIdKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let saved, !saved.isEmpty { return saved }
        return defaultSceneId
    }

    /// Persist base URL. Empty string clears the override (falls back to env / default).
    static func setBaseURLString(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: baseURLKey)
            return
        }
        var normalized = trimmed
        if !normalized.contains("://") {
            normalized = "http://\(normalized)"
        }
        UserDefaults.standard.set(normalized, forKey: baseURLKey)
    }

    static func setSceneId(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: sceneIdKey)
        } else {
            UserDefaults.standard.set(trimmed, forKey: sceneIdKey)
        }
    }

    /// Whether a UserDefaults override is active (Settings saved).
    static var hasCustomBaseURL: Bool {
        guard let saved = UserDefaults.standard.string(forKey: baseURLKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        return !saved.isEmpty
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

    /// Resolve `/media/...` or `/models/...` against the configured API host.
    static func absoluteMediaURL(path: String) -> URL? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return URL(string: trimmed)
        }
        let base = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let suffix = trimmed.hasPrefix("/") ? trimmed : "/\(trimmed)"
        return URL(string: base + suffix)
    }
}
