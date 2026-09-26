import Foundation

/// Canonical scene graph DTOs — mirror `packages/schema` (camelCase JSON).
/// Coordinate convention: **Y-up meters**, room origin at floor center.

struct Vector3: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
    var z: Double

    init(_ x: Double, _ y: Double, _ z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    init(array: [Double]) {
        precondition(array.count >= 3)
        self.x = array[0]
        self.y = array[1]
        self.z = array[2]
    }

    var asArray: [Double] { [x, y, z] }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        x = try container.decode(Double.self)
        y = try container.decode(Double.self)
        z = try container.decode(Double.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(x)
        try container.encode(y)
        try container.encode(z)
    }
}

/// Quaternion as `[x, y, z, w]` (matches schema / Three.js).
struct Quaternion: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
    var z: Double
    var w: Double

    static let identity = Quaternion(x: 0, y: 0, z: 0, w: 1)

    init(x: Double, y: Double, z: Double, w: Double) {
        self.x = x
        self.y = y
        self.z = z
        self.w = w
    }

    init(array: [Double]) {
        precondition(array.count >= 4)
        self.x = array[0]
        self.y = array[1]
        self.z = array[2]
        self.w = array[3]
    }

    var asArray: [Double] { [x, y, z, w] }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        x = try container.decode(Double.self)
        y = try container.decode(Double.self)
        z = try container.decode(Double.self)
        w = try container.decode(Double.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(x)
        try container.encode(y)
        try container.encode(z)
        try container.encode(w)
    }
}

struct TransformDTO: Codable, Equatable, Sendable {
    var position: Vector3
    var rotation: Quaternion
    var scale: Vector3?

    static func at(_ position: Vector3, rotation: Quaternion = .identity) -> TransformDTO {
        TransformDTO(position: position, rotation: rotation, scale: Vector3(1, 1, 1))
    }
}

struct DimensionsDTO: Codable, Equatable, Sendable {
    var width: Double?
    var height: Double?
    var depth: Double?
}

struct SceneObjectDTO: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var type: String
    var source: String?
    var movable: Bool?
    var transform: TransformDTO
    var dimensions: DimensionsDTO?
    var productId: String?
    var assetId: String?
    var lockedBy: String?
}

struct RoomBoundsDTO: Codable, Equatable, Sendable {
    var width: Double
    var length: Double
    var height: Double
}

struct SceneDTO: Codable, Equatable, Sendable {
    var sceneId: String
    var roomId: String?
    var version: Int
    var bounds: RoomBoundsDTO
    var objects: [SceneObjectDTO]
    var budgetUsed: Double?
    var currency: String?
}

enum OpType: String, Codable, Sendable {
    case moveObject = "MOVE_OBJECT"
    case rotateObject = "ROTATE_OBJECT"
    case addObject = "ADD_OBJECT"
    case deleteObject = "DELETE_OBJECT"
    case replaceObject = "REPLACE_OBJECT"
}

struct SceneOperationDTO: Codable, Equatable, Sendable {
    var type: OpType
    var objectId: String?
    var targetPosition: Vector3?
    var targetRotation: Quaternion?
    var assetId: String?
    var productId: String?
    var objectType: String?
    var dimensions: DimensionsDTO?
    var movable: Bool?
    var source: String?
}

struct OperationEnvelopeDTO: Codable, Sendable {
    var baseVersion: Int
    var actorId: String?
    var opId: String?
    var operations: [SceneOperationDTO]
}

struct OperationsResultDTO: Codable, Sendable {
    var accepted: Bool
    var sceneId: String
    var version: Int
    var applied: Int
    var scene: SceneDTO
    var warnings: [String]?
}
