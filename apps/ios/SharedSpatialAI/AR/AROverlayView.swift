import ARKit
import RealityKit
import SwiftUI
import UIKit

#if !targetEnvironment(simulator)
/// Live camera ARView (Pokémon GO–style): world-tracking passthrough with shared scene overlays.
/// Finger drag in draw mode places free-space 3D polylines (Y-up meters) synced via WS.
struct ARViewContainer: UIViewRepresentable {
    let scene: SceneDTO?
    var selectedObjectId: String?
    var strokes: [DrawingStrokeDTO] = []
    var ghosts: [PresenceUserDTO] = []
    var drawMode: Bool = false
    var onSelect: ((String?) -> Void)?
    var onStrokeComplete: (([Vector3]) -> Void)?

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero)
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        view.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        context.coordinator.root = AnchorEntity(world: .zero)
        if let root = context.coordinator.root {
            view.scene.addAnchor(root)
        }
        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        view.addGestureRecognizer(tap)
        let pan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        pan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(pan)
        context.coordinator.hostView = view
        context.coordinator.onSelect = onSelect
        context.coordinator.onStrokeComplete = onStrokeComplete
        context.coordinator.drawMode = drawMode
        rebuild(in: view, coordinator: context.coordinator)
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.onSelect = onSelect
        context.coordinator.onStrokeComplete = onStrokeComplete
        context.coordinator.drawMode = drawMode
        rebuild(in: uiView, coordinator: context.coordinator)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject {
        var parent: ARViewContainer
        var root: AnchorEntity?
        weak var hostView: ARView?
        var onSelect: ((String?) -> Void)?
        var onStrokeComplete: (([Vector3]) -> Void)?
        var drawMode = false
        var renderedVersion = -1
        var renderedCount = -1
        var renderedSelection: String? = "___"
        var renderedStrokeCount = -1
        var renderedGhostCount = -1
        private var draftPoints: [Vector3] = []
        // Internal: accessed from ARViewContainer.rebuild (nested private is not visible there).
        var draftEntity: Entity?

        init(parent: ARViewContainer) {
            self.parent = parent
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard !drawMode, let view = hostView else { return }
            let loc = gesture.location(in: view)
            let hits = view.hitTest(loc)
            let name = hits.compactMap { $0.entity.name }.first {
                !$0.isEmpty
                    && $0 != "floor"
                    && !$0.hasPrefix("grid_")
                    && !$0.hasPrefix("ghost_")
                    && !$0.hasPrefix("stroke_")
                    && !$0.hasPrefix("draft_")
            }
            onSelect?(name)
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard drawMode, let view = hostView else { return }
            let loc = gesture.location(in: view)
            switch gesture.state {
            case .began:
                draftPoints = []
                draftEntity?.removeFromParent()
                draftEntity = Entity()
                draftEntity?.name = "draft_stroke"
                if let draftEntity, let root {
                    root.addChild(draftEntity)
                }
                if let p = freeSpacePoint(at: loc, in: view) {
                    draftPoints = [p]
                }
            case .changed:
                guard let p = freeSpacePoint(at: loc, in: view) else { return }
                if let last = draftPoints.last {
                    let dx = p.x - last.x
                    let dy = p.y - last.y
                    let dz = p.z - last.z
                    if dx * dx + dy * dy + dz * dz < 0.0009 { return }
                }
                draftPoints.append(p)
                refreshDraftMesh()
            case .ended, .cancelled:
                let pts = draftPoints
                draftPoints = []
                draftEntity?.removeFromParent()
                draftEntity = nil
                if pts.count >= 2 {
                    onStrokeComplete?(pts)
                }
            default:
                break
            }
        }

        /// Place a point along the camera ray (~1.2 m) so strokes live in free 3D space.
        private func freeSpacePoint(at screen: CGPoint, in view: ARView) -> Vector3? {
            guard let frame = view.session.currentFrame else { return nil }
            let cam = frame.camera.transform
            let camPos = SIMD3<Float>(cam.columns.3.x, cam.columns.3.y, cam.columns.3.z)
            let forward = -SIMD3<Float>(cam.columns.2.x, cam.columns.2.y, cam.columns.2.z)
            let right = SIMD3<Float>(cam.columns.0.x, cam.columns.0.y, cam.columns.0.z)
            let up = SIMD3<Float>(cam.columns.1.x, cam.columns.1.y, cam.columns.1.z)
            let size = view.bounds.size
            guard size.width > 1, size.height > 1 else { return nil }
            let ndcX = Float((2 * screen.x / size.width) - 1)
            let ndcY = Float(1 - (2 * screen.y / size.height))
            let depth: Float = 1.25
            let fovScale: Float = 0.65
            let dir = normalize(forward) + right * ndcX * fovScale + up * ndcY * fovScale
            let world = camPos + normalize(dir) * depth
            return Vector3(Double(world.x), Double(world.y), Double(world.z))
        }

        private func refreshDraftMesh() {
            guard let draftEntity, draftPoints.count >= 2 else { return }
            draftEntity.children.forEach { $0.removeFromParent() }
            let mat = SimpleMaterial(color: .systemYellow.withAlphaComponent(0.9), isMetallic: false)
            for i in 0..<(draftPoints.count - 1) {
                draftEntity.addChild(
                    ARStrokeMesh.segment(
                        from: Coordinates.toSIMD(draftPoints[i]),
                        to: Coordinates.toSIMD(draftPoints[i + 1]),
                        radius: 0.012,
                        material: mat,
                        name: "draft_seg"
                    )
                )
            }
        }
    }

    private func rebuild(in view: ARView, coordinator: Coordinator) {
        guard let root = coordinator.root else { return }
        let version = scene?.version ?? -1
        let count = scene?.objects.count ?? -1
        let strokeCount = strokes.count
        let ghostCount = ghosts.count
        if version == coordinator.renderedVersion,
           count == coordinator.renderedCount,
           selectedObjectId == coordinator.renderedSelection,
           strokeCount == coordinator.renderedStrokeCount,
           ghostCount == coordinator.renderedGhostCount {
            return
        }
        coordinator.renderedVersion = version
        coordinator.renderedCount = count
        coordinator.renderedSelection = selectedObjectId
        coordinator.renderedStrokeCount = strokeCount
        coordinator.renderedGhostCount = ghostCount
        coordinator.parent = self

        // Keep in-progress draft while rebuilding peers/objects.
        let draft = coordinator.draftEntity
        root.children.forEach { child in
            if child.name != "draft_stroke" {
                child.removeFromParent()
            }
        }
        guard let scene else { return }

        for object in scene.objects where object.type != "wall" {
            let entity = makeOverlayProxy(for: object, selected: object.id == selectedObjectId)
            root.addChild(entity)
        }
        for ghost in GhostAvatarAnchors.remoteGhosts(from: ghosts, localUserId: APIConfig.actorId) {
            root.addChild(makeGhost(ghost))
        }
        for stroke in strokes {
            root.addChild(ARStrokeMesh.makeEntity(stroke))
        }
        if let draft, draft.parent == nil {
            root.addChild(draft)
        }
    }

    private func makeOverlayProxy(for object: SceneObjectDTO, selected: Bool) -> ModelEntity {
        let w = Float(object.dimensions?.width ?? 0.5)
        let h = Float(object.dimensions?.height ?? 0.5)
        let d = Float(object.dimensions?.depth ?? 0.5)
        let base: UIColor = object.source == "existing"
            ? .systemOrange.withAlphaComponent(selected ? 0.55 : 0.35)
            : .systemTeal.withAlphaComponent(selected ? 0.55 : 0.4)
        let color: UIColor = selected ? .systemYellow.withAlphaComponent(0.55) : base
        let entity = ModelEntity(
            mesh: .generateBox(width: w, height: h, depth: d),
            materials: [SimpleMaterial(color: color, isMetallic: false)]
        )
        entity.name = object.id
        entity.position = Coordinates.toSIMD(object.transform.position)
        entity.orientation = Coordinates.toSIMDQuat(object.transform.rotation)
        entity.generateCollisionShapes(recursive: true)
        return entity
    }

    private func makeGhost(_ user: PresenceUserDTO) -> Entity {
        let parent = Entity()
        parent.name = "ghost_\(user.userId)"
        if let pos = user.position {
            parent.position = Coordinates.toSIMD(pos)
        }
        let tint = UIColor(hex: user.color ?? "#6eb4c8") ?? .systemTeal
        let body = ModelEntity(
            mesh: .generateCylinder(height: 0.7, radius: 0.16),
            materials: [SimpleMaterial(color: tint.withAlphaComponent(0.35), isMetallic: false)]
        )
        body.name = parent.name
        parent.addChild(body)
        return parent
    }
}
#endif

/// Shared stroke mesh builder (device AR + simulator map).
enum ARStrokeMesh {
    static func makeEntity(_ stroke: DrawingStrokeDTO) -> Entity {
        let parent = Entity()
        parent.name = "stroke_\(stroke.strokeId)"
        let pts = stroke.points
        guard pts.count >= 2 else { return parent }
        let color = UIColor(hex: stroke.color) ?? .systemYellow
        let mat = SimpleMaterial(color: color.withAlphaComponent(0.85), isMetallic: false)
        let radius = Float(max(stroke.width, 0.015)) * 0.5
        for i in 0..<(pts.count - 1) {
            parent.addChild(
                segment(
                    from: Coordinates.toSIMD(pts[i]),
                    to: Coordinates.toSIMD(pts[i + 1]),
                    radius: radius,
                    material: mat,
                    name: parent.name
                )
            )
        }
        return parent
    }

    static func segment(
        from a: SIMD3<Float>,
        to b: SIMD3<Float>,
        radius: Float,
        material: SimpleMaterial,
        name: String
    ) -> ModelEntity {
        let mid = (a + b) * 0.5
        let delta = b - a
        let len = length(delta)
        let seg = ModelEntity(
            mesh: .generateBox(width: radius * 2, height: radius * 2, depth: max(len, 0.001)),
            materials: [material]
        )
        seg.name = name
        seg.position = mid
        let dir = normalize(delta)
        let axis = cross(SIMD3(0, 0, -1), dir)
        let axisLen = length(axis)
        if axisLen > 0.001 {
            let angle = acos(max(-1, min(1, dot(SIMD3(0, 0, -1), dir))))
            seg.orientation = simd_quatf(angle: angle, axis: normalize(axis))
        } else if dot(SIMD3(0, 0, -1), dir) < 0 {
            seg.orientation = simd_quatf(angle: .pi, axis: SIMD3(0, 1, 0))
        }
        return seg
    }
}

private extension UIColor {
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt64(s, radix: 16) else { return nil }
        let r = CGFloat((value & 0xFF0000) >> 16) / 255
        let g = CGFloat((value & 0x00FF00) >> 8) / 255
        let b = CGFloat(value & 0x0000FF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}

/// Legacy name kept for project references.
struct AROverlayView: View {
    var body: some View {
        Text("Use Live AR from the scan-first flow.")
            .foregroundStyle(.secondary)
    }
}
