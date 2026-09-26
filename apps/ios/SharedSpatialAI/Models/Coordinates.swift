import Foundation
import simd

/// Shared Spatial AI coordinate convention (matches `packages/schema`):
/// - Units: **meters**
/// - Up axis: **+Y**
/// - Origin: **floor center** of the room (XZ plane on the floor; Y = 0 is floor)
/// - Right-handed; +Z toward "back" of room is conventional for web twin (Three.js)
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
}
