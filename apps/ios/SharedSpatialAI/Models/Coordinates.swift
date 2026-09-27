import Foundation
import simd

/// Shared Spatial AI coordinate convention (matches `packages/schema`):
/// - Units: **meters**
/// - Up axis: **+Y**
/// - Origin: **floor center** of the room (XZ plane on the floor; **Y = 0 is the floor**)
/// - Right-handed; +Z toward "back" of room is conventional for web twin (Three.js)
///
/// **Mesh pivot:** RealityKit boxes / fitted USDZ are **center-pivoted**. Floor-sitting
/// furniture therefore stores `position.y = heightMeters / 2` so the visual bottom rests
/// on Y = 0. Live AR must parent the scene under a root whose local Y = 0 is the
/// **detected ARKit floor plane** (not the session world origin at phone height).
///
/// RoomPlan / ARKit use a device-relative world. Exporters (camera scan + RoomPlan)
/// recenter so the captured floor AABB center maps to (0, 0, 0) in shared space.
enum Coordinates {
    static let identityQuaternion = Quaternion.identity

    /// Convert a RoomPlan / RealityKit `simd_float4x4` translation to Vector3.
    static func position(from matrix: simd_float4x4) -> Vector3 {
        let t = matrix.columns.3
        return Vector3(Double(t.x), Double(t.y), Double(t.z))
    }

    /// Extract rotation as schema quaternion `[x, y, z, w]` from a 4x4 matrix.
    static func rotation(from matrix: simd_float4x4) -> Quaternion {
        // simd_quatf only accepts a 3×3 rotation matrix, not float4x4.
        let rot = simd_float3x3(
            SIMD3(matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z),
            SIMD3(matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z),
            SIMD3(matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z)
        )
        let q = simd_quatf(rot)
        return Quaternion(
            x: Double(q.vector.x),
            y: Double(q.vector.y),
            z: Double(q.vector.z),
            w: Double(q.vector.w)
        )
    }

    /// Shift a world-space point so `origin` becomes the new (0,0,0).
    static func recenter(_ point: Vector3, origin: Vector3) -> Vector3 {
        Vector3(point.x - origin.x, point.y - origin.y, point.z - origin.z)
    }

    static func toSIMD(_ v: Vector3) -> SIMD3<Float> {
        SIMD3(Float(v.x), Float(v.y), Float(v.z))
    }

    static func toSIMDQuat(_ q: Quaternion) -> simd_quatf {
        simd_quatf(
            ix: Float(q.x),
            iy: Float(q.y),
            iz: Float(q.z),
            r: Float(q.w)
        )
    }

    // MARK: - Floor seating (center pivot)

    /// Center-pivot Y so the mesh bottom rests on the floor (Y = 0).
    static func seatedY(heightMeters: Double) -> Double {
        max(heightMeters, 0.02) * 0.5
    }

    static func seatedY(heightMeters: Float) -> Float {
        max(heightMeters, 0.02) * 0.5
    }

    /// Ceiling / wall-mounted types keep their authored Y; everything else sits on the floor.
    static func sitsOnFloor(_ object: SceneObjectDTO) -> Bool {
        let t = object.type.lowercased()
        if t == "wall" || t == "door" || t == "window" || t == "ceiling" || t == "opening" {
            return false
        }
        if t.contains("pendant") || t.contains("string_light") || t.contains("ceiling") {
            return false
        }
        // Elevated scan plane anchors (tables/counters) keep their measured height.
        if object.id.hasPrefix("plane_cam_") {
            return false
        }
        return true
    }

    /// Project XZ onto the floor plane and set Y to `height/2` for floor-sitting objects.
    static func projectOntoFloor(
        _ position: Vector3,
        heightMeters: Double,
        sitsOnFloor: Bool = true
    ) -> Vector3 {
        guard sitsOnFloor else { return position }
        return Vector3(position.x, seatedY(heightMeters: heightMeters), position.z)
    }

    /// Render / place helper: floor-sit catalog & AI objects; leave scan geometry as-is
    /// when it already carries a measured center Y (RoomPlan / walls).
    static func renderPosition(for object: SceneObjectDTO) -> Vector3 {
        let raw = object.transform.position
        guard sitsOnFloor(object) else { return raw }
        let h = object.dimensions?.heightMeters ?? 0.5
        // Scanned furniture already has a real center height from RoomPlan / planes.
        if object.source == "existing", !object.id.hasPrefix("ar_") {
            // Still clamp near-floor floaters (Y≈0 with center pivot → half-buried look)
            // and obvious mid-air bugs (Y far above halfHeight without being a tall piece).
            if raw.y < h * 0.15 {
                return projectOntoFloor(raw, heightMeters: h)
            }
            return raw
        }
        return projectOntoFloor(raw, heightMeters: h)
    }
}
