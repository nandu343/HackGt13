import Foundation

/// Canonical scene graph DTOs — mirror `packages/schema` (camelCase JSON).
/// Coordinate convention: **Y-up meters**, room origin at floor center.
/// Floor-sitting objects use **center pivot**: `position.y = heightMeters / 2`.

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
    var scale: Vector3? = nil

    static func at(_ position: Vector3, rotation: Quaternion = .identity) -> TransformDTO {
        TransformDTO(position: position, rotation: rotation, scale: Vector3(1, 1, 1))
    }
}

struct DimensionsDTO: Codable, Equatable, Sendable {
    var width: Double? = nil
    var height: Double? = nil
    var depth: Double? = nil

    /// Catalog / mesh defaults when a dimension is missing from the API.
    var widthMeters: Double { width ?? 0.5 }
    var heightMeters: Double { height ?? 0.5 }
    var depthMeters: Double { depth ?? 0.5 }

    /// Safe for `String(format:)` — never passes `Double?`.
    var displayMetersCompact: String {
        String(format: "%.2f×%.2f×%.2fm", widthMeters, heightMeters, depthMeters)
    }

    var displayMetersSpaced: String {
        String(format: "%.2f × %.2f × %.2f m", widthMeters, heightMeters, depthMeters)
    }
}

struct SceneObjectDTO: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var type: String
    var source: String? = nil
    var movable: Bool? = nil
    var transform: TransformDTO
    var dimensions: DimensionsDTO? = nil
    var productId: String? = nil
    var assetId: String? = nil
    var modelUrl: String? = nil
    var lockedBy: String? = nil
    var lockedUntil: String? = nil
}

struct RoomBoundsDTO: Codable, Equatable, Sendable {
    var width: Double
    var length: Double
    var height: Double
}

struct SceneDTO: Codable, Equatable, Sendable {
    var sceneId: String
    var roomId: String? = nil
    var version: Int
    var bounds: RoomBoundsDTO
    var objects: [SceneObjectDTO]
    var budgetUsed: Double? = nil
    var currency: String? = nil
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
    var objectId: String? = nil
    var targetPosition: Vector3? = nil
    var targetRotation: Quaternion? = nil
    var assetId: String? = nil
    var productId: String? = nil
    var objectType: String? = nil
    var dimensions: DimensionsDTO? = nil
    var movable: Bool? = nil
    var source: String? = nil
    /// Optional GLB/USDZ path copied from catalog onto ADD_OBJECT.
    var modelUrl: String? = nil

    static func move(objectId: String, to position: Vector3) -> SceneOperationDTO {
        SceneOperationDTO(
            type: .moveObject,
            objectId: objectId,
            targetPosition: position
        )
    }

    static func delete(objectId: String) -> SceneOperationDTO {
        SceneOperationDTO(
            type: .deleteObject,
            objectId: objectId
        )
    }

    static func add(from item: CatalogItemDTO, objectId: String, position: Vector3) -> SceneOperationDTO {
        let dims = item.dimensions
        // Prefer mesh-recognizable type (sofa/lamp/…) over coarse category ("seating").
        let typeHint = Self.objectTypeHint(for: item)
        return SceneOperationDTO(
            type: .addObject,
            objectId: objectId,
            targetPosition: position,
            targetRotation: .identity,
            assetId: item.assetId,
            productId: item.productId,
            objectType: typeHint,
            dimensions: dims,
            movable: true,
            source: "catalog",
            modelUrl: item.modelUrl
        )
    }

    /// Maps catalog SKU → scene object type used by mesh builders / planners.
    static func objectTypeHint(for item: CatalogItemDTO) -> String {
        let pid = item.productId.lowercased()
        let name = item.name.lowercased()
        if pid.contains("sofa") || name.contains("sofa") { return "sofa" }
        if pid.contains("bean") || name.contains("bean") { return "beanbag" }
        if pid.contains("stool") || name.contains("stool") { return "stool" }
        if pid.contains("chair") || name.contains("chair") {
            return name.contains("dining") || pid.contains("dining") ? "dining_chair" : "chair"
        }
        if pid.contains("desk") || name.contains("desk") { return "desk" }
        if pid.contains("table") || name.contains("table") {
            if name.contains("dining") || pid.contains("dining") { return "dining_table" }
            if name.contains("coffee") { return "coffee_table" }
            return "table"
        }
        if pid.contains("party_lights") || name.contains("string") { return "string_lights" }
        if pid.contains("pendant") || name.contains("pendant") { return "pendant" }
        if pid.contains("lamp") || name.contains("lamp") {
            return name.contains("desk") || name.contains("task") ? "desk_lamp" : "floor_lamp"
        }
        if pid.contains("plant") || name.contains("plant") { return "plant" }
        if pid.contains("rug") || name.contains("rug") { return "rug" }
        if pid.contains("backdrop") || name.contains("backdrop") { return "backdrop" }
        if pid.contains("projector") || name.contains("screen") { return "projector_screen" }
        if pid.contains("virtual_marker") { return "marker" }
        if pid.contains("glow") { return "glow_orb" }
        return item.category ?? item.tags?.first ?? "furniture"
    }
}

struct OperationEnvelopeDTO: Codable, Sendable {
    var baseVersion: Int
    var actorId: String? = nil
    var opId: String? = nil
    var operations: [SceneOperationDTO]
}

struct OperationsResultDTO: Codable, Sendable {
    var accepted: Bool
    var sceneId: String
    var version: Int
    var applied: Int
    var scene: SceneDTO
    var warnings: [String]? = nil
}

struct SceneInviteDTO: Codable, Equatable, Sendable {
    var token: String
    var sceneId: String
    var createdAt: String? = nil
    var createdBy: String? = nil
    var label: String? = nil
}
