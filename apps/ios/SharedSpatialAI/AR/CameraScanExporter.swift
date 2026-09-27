import Foundation
import simd

/// Snapshot of an ARKit plane used when finishing a camera scan (no LiDAR / RoomPlan).
struct DetectedPlaneSnapshot: Equatable, Sendable {
    enum Alignment: String, Sendable {
        case horizontal
        case vertical
    }

    var center: SIMD3<Float>
    /// Local extents from `ARPlaneAnchor.planeExtent` mapped as (width, 0, height).
    var extent: SIMD3<Float>
    var transform: simd_float4x4
    var alignment: Alignment
}

/// Builds the shared Y-up meters `SceneDTO` from ARKit plane detection (and optional floor taps).
enum CameraScanExporter {
    static func export(
        sceneId: String,
        planes: [DetectedPlaneSnapshot],
        cornerPoints: [SIMD3<Float>],
        roomId: String? = nil
    ) -> SceneDTO {
        let worldPoints = sampleWorldPoints(planes: planes, corners: cornerPoints)
        let (origin, bounds) = boundsAndOrigin(from: worldPoints, planes: planes)
        let objects = wallObjects(from: planes, origin: origin)
            + planeAnchorObjects(from: planes, origin: origin)

        return SceneDTO(
            sceneId: sceneId,
            roomId: roomId ?? "camera_\(sceneId)",
            version: 1,
            bounds: bounds,
            objects: objects,
            budgetUsed: 0,
            currency: "USD"
        )
    }

    // MARK: - Sampling

    private static func sampleWorldPoints(
        planes: [DetectedPlaneSnapshot],
        corners: [SIMD3<Float>]
    ) -> [SIMD3<Float>] {
        var points = corners
        for plane in planes {
            points.append(contentsOf: planeCornerWorldPoints(plane))
            points.append(plane.center)
        }
        return points
    }

    /// Four corners of the plane rectangle in world space (local ±extent/2 on XZ).
    private static func planeCornerWorldPoints(_ plane: DetectedPlaneSnapshot) -> [SIMD3<Float>] {
        let hx = plane.extent.x * 0.5
        let hz = plane.extent.z * 0.5
        let locals: [SIMD3<Float>] = [
            SIMD3(-hx, 0, -hz),
            SIMD3(hx, 0, -hz),
            SIMD3(hx, 0, hz),
            SIMD3(-hx, 0, hz)
        ]
        return locals.map { local in
            let col = plane.transform * SIMD4<Float>(local.x, local.y, local.z, 1)
            return SIMD3(col.x, col.y, col.z)
        }
    }

    // MARK: - Bounds

    private static func boundsAndOrigin(
        from points: [SIMD3<Float>],
        planes: [DetectedPlaneSnapshot]
    ) -> (Vector3, RoomBoundsDTO) {
        guard let first = points.first else {
            return (
                Vector3(0, 0, 0),
                RoomBoundsDTO(width: 4, length: 4, height: 2.5)
            )
        }

        var minX = first.x, maxX = first.x
        var minY = first.y, maxY = first.y
        var minZ = first.z, maxZ = first.z
        for p in points.dropFirst() {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
            minZ = min(minZ, p.z); maxZ = max(maxZ, p.z)
        }

        // Prefer the lowest horizontal plane as floor Y when available.
        let floorCandidates = planes.filter { $0.alignment == .horizontal }
        let floorY: Double
        if let lowest = floorCandidates.map(\.center.y).min() {
            floorY = Double(lowest)
        } else {
            floorY = Double(minY)
        }

        // Room origin: floor center in XZ, Y on the detected floor plane.
        let origin = Vector3(
            Double((minX + maxX) * 0.5),
            floorY,
            Double((minZ + maxZ) * 0.5)
        )

        let width = max(2.0, Double(maxX - minX))
        let length = max(2.0, Double(maxZ - minZ))
        let wallH = planes
            .filter { $0.alignment == .vertical }
            .map { Double($0.extent.z) }
            .max()
        let spanY = Double(maxY - minY)
        let fromFloor = Double(maxY) - floorY
        let height = max(2.2, max(wallH ?? fromFloor, spanY))

        return (origin, RoomBoundsDTO(width: width, length: length, height: height))
    }

    // MARK: - Objects

    /// Vertical planes → fixed wall stubs (optional anchors in the shared graph).
    private static func wallObjects(
        from planes: [DetectedPlaneSnapshot],
        origin: Vector3
    ) -> [SceneObjectDTO] {
        planes
            .enumerated()
            .filter { $0.element.alignment == .vertical }
            .map { index, plane in
                let pos = Coordinates.recenter(
                    Vector3(Double(plane.center.x), Double(plane.center.y), Double(plane.center.z)),
                    origin: origin
                )
                return SceneObjectDTO(
                    id: "wall_cam_\(index)",
                    type: "wall",
                    source: "existing",
                    movable: false,
                    transform: TransformDTO.at(
                        pos,
                        rotation: Coordinates.rotation(from: plane.transform)
                    ),
                    dimensions: DimensionsDTO(
                        width: max(0.3, Double(plane.extent.x)),
                        // planeExtent.height is stored in extent.z for both alignments.
                        height: max(1.5, Double(plane.extent.z)),
                        depth: 0.08
                    ),
                    productId: nil,
                    assetId: nil,
                    modelUrl: nil,
                    lockedBy: nil,
                    lockedUntil: nil
                )
            }
    }

    /// Horizontal planes → optional table/floor-like anchors for the twin (not walls).
    private static func planeAnchorObjects(
        from planes: [DetectedPlaneSnapshot],
        origin: Vector3
    ) -> [SceneObjectDTO] {
        planes
            .enumerated()
            .filter { $0.element.alignment == .horizontal }
            .compactMap { index, plane -> SceneObjectDTO? in
                // Skip the largest floor-like plane; keep elevated tables/surfaces as anchors.
                let area = plane.extent.x * plane.extent.z
                let largestFloor = planes
                    .filter { $0.alignment == .horizontal }
                    .map { $0.extent.x * $0.extent.z }
                    .max() ?? 0
                if area >= largestFloor * 0.85 { return nil }
                if plane.center.y - Float(origin.y) < 0.25 { return nil }

                let pos = Coordinates.recenter(
                    Vector3(Double(plane.center.x), Double(plane.center.y), Double(plane.center.z)),
                    origin: origin
                )
                return SceneObjectDTO(
                    id: "plane_cam_\(index)",
                    type: "table",
                    source: "existing",
                    movable: true,
                    transform: TransformDTO.at(pos),
                    dimensions: DimensionsDTO(
                        width: Double(plane.extent.x),
                        height: 0.05,
                        depth: Double(plane.extent.z)
                    ),
                    productId: nil,
                    assetId: nil,
                    modelUrl: nil,
                    lockedBy: nil,
                    lockedUntil: nil
                )
            }
    }
}
