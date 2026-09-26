import Foundation
import RoomPlan
import simd

/// Converts a RoomPlan `CapturedRoom` into the shared Y-up meters SceneDTO.
enum RoomPlanExporter {
    /// Map RoomPlan categories to coarse object types used by the web twin / catalog.
    static func objectType(for category: CapturedRoom.Object.Category) -> String {
        switch category {
        case .storage: return "storage"
        case .refrigerator: return "appliance"
        case .stove: return "appliance"
        case .bed: return "bed"
        case .sink: return "fixture"
        case .washerDryer: return "appliance"
        case .toilet: return "fixture"
        case .bathtub: return "fixture"
        case .oven: return "appliance"
        case .dishwasher: return "appliance"
        case .table: return "table"
        case .sofa: return "sofa"
        case .chair: return "chair"
        case .fireplace: return "fireplace"
        case .television: return "media"
        case .stairs: return "stairs"
        @unknown default: return "object"
        }
    }

    static func export(
        captured: CapturedRoom,
        sceneId: String,
        roomId: String? = nil
    ) -> SceneDTO {
        // Floor center → shared origin (Y-up meters).
        let floors = captured.floors
        let origin = floorOrigin(floors: floors, walls: captured.walls, objects: captured.objects)
        let bounds = estimateBounds(
            floors: floors,
            walls: captured.walls,
            objects: captured.objects,
            origin: origin
        )

        var objects: [SceneObjectDTO] = []

        for (index, wall) in captured.walls.enumerated() {
            let pos = Coordinates.recenter(Coordinates.position(from: wall.transform), origin: origin)
            let dims = DimensionsDTO(
                width: Double(wall.dimensions.x),
                height: Double(wall.dimensions.y),
                depth: max(0.05, Double(wall.dimensions.z))
            )
            objects.append(
                SceneObjectDTO(
                    id: "wall_\(index)",
                    type: "wall",
                    source: "existing",
                    movable: false,
                    transform: TransformDTO.at(
                        pos,
                        rotation: Coordinates.rotation(from: wall.transform)
                    ),
                    dimensions: dims,
                    productId: nil,
                    assetId: nil,
                    lockedBy: nil
                )
            )
        }

        for (index, object) in captured.objects.enumerated() {
            let pos = Coordinates.recenter(Coordinates.position(from: object.transform), origin: origin)
            // Lift so position is roughly object center (RoomPlan transform is usually center).
            let dims = DimensionsDTO(
                width: Double(object.dimensions.x),
                height: Double(object.dimensions.y),
                depth: Double(object.dimensions.z)
            )
            objects.append(
                SceneObjectDTO(
                    id: "rp_\(objectType(for: object.category))_\(index)",
                    type: objectType(for: object.category),
                    source: "existing",
                    movable: true,
                    transform: TransformDTO.at(
                        pos,
                        rotation: Coordinates.rotation(from: object.transform)
                    ),
                    dimensions: dims,
                    productId: nil,
                    assetId: nil,
                    lockedBy: nil
                )
            )
        }

        return SceneDTO(
            sceneId: sceneId,
            roomId: roomId ?? "roomplan_\(sceneId)",
            version: 1,
            bounds: bounds,
            objects: objects,
            budgetUsed: 0,
            currency: "USD"
        )
    }

    // MARK: - Helpers

    private static func floorOrigin(
        floors: [CapturedRoom.Surface],
        walls: [CapturedRoom.Surface],
        objects: [CapturedRoom.Object]
    ) -> Vector3 {
        if let floor = floors.first {
            return Coordinates.position(from: floor.transform)
        }
        // Fallback: centroid of wall/object positions projected to floor (y from min).
        var points: [Vector3] = walls.map { Coordinates.position(from: $0.transform) }
        points.append(contentsOf: objects.map { Coordinates.position(from: $0.transform) })
        guard !points.isEmpty else { return Vector3(0, 0, 0) }
        let cx = points.map(\.x).reduce(0, +) / Double(points.count)
        let cz = points.map(\.z).reduce(0, +) / Double(points.count)
        let minY = points.map(\.y).min() ?? 0
        return Vector3(cx, minY, cz)
    }

    private static func estimateBounds(
        floors: [CapturedRoom.Surface],
        walls: [CapturedRoom.Surface],
        objects: [CapturedRoom.Object],
        origin: Vector3
    ) -> RoomBoundsDTO {
        if let floor = floors.first {
            // RoomPlan floor dimensions: x = width, z = length typically.
            let w = max(2.0, Double(floor.dimensions.x))
            let l = max(2.0, Double(floor.dimensions.z))
            let h = walls.map { Double($0.dimensions.y) }.max() ?? 2.5
            return RoomBoundsDTO(width: w, length: l, height: max(2.2, h))
        }

        var minX = 0.0, maxX = 0.0, minZ = 0.0, maxZ = 0.0, maxY = 2.5
        let samples: [Vector3] =
            walls.map { Coordinates.recenter(Coordinates.position(from: $0.transform), origin: origin) }
            + objects.map { Coordinates.recenter(Coordinates.position(from: $0.transform), origin: origin) }
        if let first = samples.first {
            minX = first.x; maxX = first.x
            minZ = first.z; maxZ = first.z
            maxY = first.y
        }
        for p in samples {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minZ = min(minZ, p.z); maxZ = max(maxZ, p.z)
            maxY = max(maxY, p.y)
        }
        return RoomBoundsDTO(
            width: max(2.0, maxX - minX),
            length: max(2.0, maxZ - minZ),
            height: max(2.2, maxY)
        )
    }
}

/// Demo fixture used on Simulator (RoomPlan capture unavailable).
enum DemoSceneFactory {
    static func partyDemo(sceneId: String = APIConfig.defaultSceneId) -> SceneDTO {
        SceneDTO(
            sceneId: sceneId,
            roomId: "room_001",
            version: 1,
            bounds: RoomBoundsDTO(width: 5.42, length: 6.31, height: 2.68),
            objects: [
                SceneObjectDTO(
                    id: "sofa_1",
                    type: "sofa",
                    source: "existing",
                    movable: true,
                    transform: TransformDTO.at(
                        Vector3(1.2, 0.41, -1.4),
                        rotation: Quaternion(x: 0, y: 0.707, z: 0, w: 0.707)
                    ),
                    dimensions: DimensionsDTO(width: 2.1, height: 0.82, depth: 0.91),
                    productId: "product_sofa_01",
                    assetId: nil,
                    lockedBy: nil
                ),
                SceneObjectDTO(
                    id: "lamp_17",
                    type: "floor_lamp",
                    source: "catalog",
                    movable: true,
                    transform: TransformDTO.at(Vector3(-1.62, 0.86, 2.1)),
                    dimensions: DimensionsDTO(width: 0.4, height: 1.72, depth: 0.4),
                    productId: "product_39",
                    assetId: "asset_lamp_12",
                    lockedBy: nil
                ),
                SceneObjectDTO(
                    id: "table_05",
                    type: "table",
                    source: "catalog",
                    movable: true,
                    transform: TransformDTO.at(Vector3(1.5, 0.375, 0.2)),
                    dimensions: DimensionsDTO(width: 1.4, height: 0.75, depth: 1.1),
                    productId: "product_table_05",
                    assetId: nil,
                    lockedBy: nil
                )
            ],
            budgetUsed: 1277,
            currency: "USD"
        )
    }
}
