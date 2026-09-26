import Foundation

/// Layout AI DTOs — mirror `packages/schema` LayoutRequest / LayoutResponse.
struct LayoutRequestDTO: Codable, Sendable {
    var sceneId: String
    var prompt: String
    var guestCount: Int
    var budget: Double
}

struct LayoutConstraintsDTO: Codable, Sendable {
    var budget: Double?
    var guestCount: Int?
    var mustHave: [String]?
    var clearCenter: Bool?
}

struct LayoutResponseDTO: Codable, Sendable {
    var scenario: String
    var reasoningSummary: String
    var operations: [SceneOperationDTO]
    var constraints: LayoutConstraintsDTO
    var warnings: [String]?
    var plannerMode: String?
    var fixedOps: Int?
}
