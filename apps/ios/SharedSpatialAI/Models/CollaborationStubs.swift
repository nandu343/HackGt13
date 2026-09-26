import Foundation

// MARK: - Collaboration stubs (voice + spatial drawing)
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
//   Offerer rule (match web): lexicographically smaller userId creates the offer.
//   STUN: stun:stun.l.google.com:19302 (add TURN later for cellular NAT).
//
// Drawing — ephemeral strokes in Y-up meters (wall / floor / free polyline):
//     { "type": "draw_stroke", "stroke": DrawingStrokeDTO }
//     { "type": "draw_clear", "actorId", "scope": "own"|"all" }
//   welcome includes strokes[]; draw_clear echoes remaining strokes[].
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
