import Foundation

/// Runtime config for the API host.
///
/// - Simulator → `localhost` / `127.0.0.1` reaches the Mac running uvicorn.
/// - Physical device → set your Mac's LAN IP (e.g. `http://192.168.1.20:8000`).
enum APIConfig {
    static let defaultSceneId = "scene_party_001"
    static let actorId = "ios_scaffold"

    /// Override at build time or edit before demo.
    static var baseURL: URL {
        if let raw = ProcessInfo.processInfo.environment["SHARED_SPATIAL_API_URL"],
           let url = URL(string: raw) {
            return url
        }
        #if targetEnvironment(simulator)
        return URL(string: "http://127.0.0.1:8000")!
        #else
        // Change this to your Mac's IP when running on a physical iPhone/iPad.
        return URL(string: "http://127.0.0.1:8000")!
        #endif
    }
}
