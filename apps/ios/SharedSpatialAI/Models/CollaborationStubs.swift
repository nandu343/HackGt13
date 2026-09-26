import Foundation

// MARK: - Collaboration stubs (voice + spatial drawing + ghost avatars)
//
// Web twin uses the same FastAPI channel:
//   WS  /ws/scene/{sceneId}
//
// Voice (WebRTC mesh) — signaling only on this channel; media is peer-to-peer.
//   Client → server (relayed to toUserId):
//     { "type": "rtc_offer"|"rtc_answer", "fromUserId", "toUserId", "sdp": { type, sdp } }
//     { "type": "rtc_ice", "fromUserId", "toUserId", "candidate": { … } | null }
//   Presence flags (join/presence user object):
//     voiceEnabled: Bool, voiceSpeaking: Bool
//     position: [x,y,z]?          // ghost standing point (Y-up meters)
//     lookDirection: [x,y,z]?     // optional facing / camera forward
//   Offerer rule (match web): lexicographically smaller userId creates the offer.
//   STUN: stun:stun.l.google.com:19302 (add TURN later for cellular NAT).
//
// Drawing — ephemeral strokes in Y-up meters (wall / floor / free polyline):
//     { "type": "draw_stroke", "stroke": DrawingStrokeDTO }
//     { "type": "draw_clear", "actorId", "scope": "own"|"all" }
//   welcome includes strokes[]; draw_clear echoes remaining strokes[].
//
// Ghost avatars — remotes from presence[] (skip local userId):
//   For each peer with `position`, spawn a translucent capsule/sphere Entity
//   tinted by `color`, billboard label = displayName; pulse opacity when voiceSpeaking.
//   Broadcast local AR camera / focus as presence.position (~10 Hz, throttle OK).
//
// Invite links — web uses /?scene={id}&invite={token} (POST /scene/{id}/invites).
//   No peer cap on WS presence; mesh voice may degrade at high N. iOS can paste
//   the scene id / join the same WS channel with a friendly displayName.
//
// Existing furniture — RoomPlan marks scanned objects source="existing".
//   Tap those entities in AR to MOVE_OBJECT / DELETE_OBJECT (clear out of the way);
//   walls stay immovable. Mirrors web ObjectGizmo + SelectionBar behavior.
//
// AR render hint: map each stroke.points → RealityKit Entity with MeshResource
// generating a thin tube / LineMesh along world positions (same origin as scene graph).
// Full AVAudioEngine / WebRTC iOS client is intentionally out of scope for this scaffold.

struct PresenceUserDTO: Codable, Equatable, Sendable {
    var userId: String
    var displayName: String
    var color: String?
    var selectedObjectId: String?
    var lastSeenAt: String?
    var voiceEnabled: Bool?
    var voiceSpeaking: Bool?
    /// Ghost standing point in shared Y-up meters (orbit focus / camera presence).
    var position: Vector3?
    /// Optional look / facing direction.
    var lookDirection: Vector3?
}

/// Thin RealityKit hook: build translucent ghost anchors from a presence snapshot.
/// Wire from SceneSyncStore when AR session is active; no-op stub for Simulator.
enum GhostAvatarAnchors {
    /// Peers to render (everyone except `localUserId` who has a position).
    static func remoteGhosts(
        from presence: [PresenceUserDTO],
        localUserId: String
    ) -> [PresenceUserDTO] {
        presence.filter { user in
            user.userId != localUserId && user.position != nil
        }
    }

    /// Suggested mesh: capsule ~0.18r × 0.7h + sphere head, opacity ~0.4, depthWrite off.
    /// Parent at `position`; yaw from lookDirection.xz when present.
    static func makeStubEntityDescription(for user: PresenceUserDTO) -> String {
        let pos = user.position.map { "(\($0.x), \($0.y), \($0.z))" } ?? "nil"
        let speaking = user.voiceSpeaking == true ? " speaking" : ""
        return "ghost:\(user.displayName)@\(pos)\(speaking)"
    }
}

enum DrawPlane: String, Codable, Sendable {
    case wall
    case floor
    case free
}

/// Spatial annotation polyline — mirrors `DrawingStroke` in packages/schema.
struct DrawingStrokeDTO: Codable, Equatable, Identifiable, Sendable {
    var strokeId: String
    var sceneId: String
    var actorId: String
    var color: String
    var width: Double
    var points: [Vector3]
    var plane: DrawPlane?
    var createdAt: String?

    var id: String { strokeId }
}

/// WebRTC signaling payloads (JSON via scene WS). Media plane not implemented on iOS yet.
enum RtcSignalType: String, Codable, Sendable {
    case offer = "rtc_offer"
    case answer = "rtc_answer"
    case ice = "rtc_ice"
}

struct RtcSignalDTO: Codable, Sendable {
    var type: RtcSignalType
    var sceneId: String?
    var fromUserId: String
    var toUserId: String
    /// SDP dict: `{ "type": "offer"|"answer", "sdp": "..." }`
    var sdp: [String: String]?
    /// ICE candidate JSON object, or null for end-of-candidates
    var candidate: [String: String]?
}
