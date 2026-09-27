import ARKit
import RealityKit
import SwiftUI
import UIKit
import simd

#if !targetEnvironment(simulator)
/// Live camera ARView: world-tracking passthrough with shared scene overlays.
/// Drawing is local-first: draft segments append instantly; WS only on finger-up.
struct ARViewContainer: UIViewRepresentable {
    let scene: SceneDTO?
    var selectedObjectId: String?
    var strokes: [DrawingStrokeDTO] = []
    var ghosts: [PresenceUserDTO] = []
    var drawMode: Bool = false
    /// Hex stroke color for the in-progress draft.
    var drawColor: String = "#e2b45c"
    var onSelect: ((String?) -> Void)?
    var onStrokeComplete: (([Vector3]) -> Void)?
    var onMoveEnd: ((String, Vector3) -> Void)?
    /// Floor point ~1.5 m in front of camera (catalog place).
    var onPlacementHint: ((Vector3) -> Void)?

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
        // Prefer draw/drag over ARView's default gestures when active.
        pan.cancelsTouchesInView = false
        view.addGestureRecognizer(pan)
        context.coordinator.hostView = view
        context.coordinator.applyCallbacks(from: self)
        rebuild(in: view, coordinator: context.coordinator)
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        let c = context.coordinator
        c.applyCallbacks(from: self)
        // Never tear down the scene while the finger is down — that was a major lag source.
        if c.isDrawing || c.draggingObjectId != nil {
            return
        }
        rebuild(in: uiView, coordinator: c)
        c.publishPlacementHintIfNeeded()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: ARViewContainer
        var root: AnchorEntity?
        weak var hostView: ARView?
        var onSelect: ((String?) -> Void)?
        var onStrokeComplete: (([Vector3]) -> Void)?
        var onMoveEnd: ((String, Vector3) -> Void)?
        var onPlacementHint: ((Vector3) -> Void)?
        var drawMode = false
        var drawColor = "#e2b45c"
        var renderedVersion = -1
        var renderedCount = -1
        var renderedSelection: String? = "___"
        var renderedStrokeCount = -1
        var renderedGhostCount = -1
        var renderedStrokeIds: [String] = []

        /// True from pan .began → .ended in draw mode — blocks full rebuilds.
        var isDrawing = false
        var draftEntity: Entity?
        private var draftPoints: [Vector3] = []
        private var lastDraftSIMD: SIMD3<Float>?
        private var draftMaterial = SimpleMaterial(color: .systemYellow, isMetallic: false)

        var draggingObjectId: String?
        private var dragLockY: Float = 0
        private var dragStartPos: SIMD3<Float>?
        private var lastHintPublish: CFTimeInterval = 0

        init(parent: ARViewContainer) {
            self.parent = parent
        }

        func applyCallbacks(from parent: ARViewContainer) {
            self.parent = parent
            onSelect = parent.onSelect
            onStrokeComplete = parent.onStrokeComplete
            onMoveEnd = parent.onMoveEnd
            onPlacementHint = parent.onPlacementHint
            drawMode = parent.drawMode
            drawColor = parent.drawColor
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard !drawMode, draggingObjectId == nil, let view = hostView else { return }
            let loc = gesture.location(in: view)
            let hits = view.hitTest(loc)
            let name = hits.compactMap { entityName($0.entity) }.first {
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
            guard let view = hostView else { return }
            let loc = gesture.location(in: view)
            if drawMode {
                handleDrawPan(gesture, at: loc, in: view)
            } else {
                handleObjectDragPan(gesture, at: loc, in: view)
            }
        }

        // MARK: - Drawing (local-first, incremental)

        private func handleDrawPan(_ gesture: UIPanGestureRecognizer, at loc: CGPoint, in view: ARView) {
            switch gesture.state {
            case .began:
                isDrawing = true
                draftPoints = []
                lastDraftSIMD = nil
                draftEntity?.removeFromParent()
                let draft = Entity()
                draft.name = "draft_stroke"
                draftEntity = draft
                root?.addChild(draft)
                let uiColor = UIColor(hex: drawColor) ?? .systemYellow
                draftMaterial = SimpleMaterial(color: uiColor.withAlphaComponent(0.95), isMetallic: false)
                if let p = freeSpacePoint(at: loc, in: view) {
                    draftPoints = [p]
                    lastDraftSIMD = Coordinates.toSIMD(p)
                }
            case .changed:
                guard isDrawing, let p = freeSpacePoint(at: loc, in: view) else { return }
                let simd = Coordinates.toSIMD(p)
                if let last = lastDraftSIMD {
                    let dx = simd.x - last.x
                    let dy = simd.y - last.y
                    let dz = simd.z - last.z
                    // ~3 cm min spacing — fewer meshes, still smooth.
                    if dx * dx + dy * dy + dz * dz < 0.0009 { return }
                    // Append one segment only — never rebuild the whole polyline.
                    draftEntity?.addChild(
                        ARStrokeMesh.segment(
                            from: last,
                            to: simd,
                            radius: 0.011,
                            material: draftMaterial,
                            name: "draft_seg"
                        )
                    )
                }
                draftPoints.append(p)
                lastDraftSIMD = simd
            case .ended, .cancelled:
                let pts = draftPoints
                // Leave draft mesh in place until the next rebuild installs the committed stroke —
                // avoids a blank frame between finger-up and store → SwiftUI → rebuild.
                let pending = draftEntity
                pending?.name = "stroke_pending"
                draftEntity = nil
                draftPoints = []
                lastDraftSIMD = nil
                isDrawing = false
                if pts.count >= 2 {
                    // Sync off the gesture hot path; local ink already visible.
                    onStrokeComplete?(pts)
                } else {
                    pending?.removeFromParent()
                }
            default:
                break
            }
        }

        // MARK: - Furniture drag

        private func handleObjectDragPan(
            _ gesture: UIPanGestureRecognizer,
            at loc: CGPoint,
            in view: ARView
        ) {
            switch gesture.state {
            case .began:
                let hits = view.hitTest(loc)
                let hitName = hits.compactMap { entityName($0.entity) }.first {
                    !$0.isEmpty
                        && !$0.hasPrefix("ghost_")
                        && !$0.hasPrefix("stroke_")
                        && !$0.hasPrefix("draft_")
                }
                guard let id = hitName,
                      let obj = parent.scene?.objects.first(where: { $0.id == id }),
                      obj.type != "wall",
                      obj.movable != false,
                      let entity = findEntity(named: id)
                else {
                    draggingObjectId = nil
                    return
                }
                if parent.selectedObjectId != id {
                    onSelect?(id)
                }
                draggingObjectId = id
                dragLockY = entity.position.y
                dragStartPos = entity.position
            case .changed:
                guard let id = draggingObjectId,
                      let entity = findEntity(named: id),
                      let hit = floorPlaneHit(at: loc, planeY: dragLockY, in: view)
                else { return }
                entity.position = SIMD3(hit.x, dragLockY, hit.z)
            case .ended, .cancelled:
                defer {
                    draggingObjectId = nil
                    dragStartPos = nil
                }
                guard let id = draggingObjectId,
                      let entity = findEntity(named: id)
                else { return }
                let pos = entity.position
                let moved: Bool = {
                    guard let start = dragStartPos else { return true }
                    let dx = pos.x - start.x
                    let dz = pos.z - start.z
                    return dx * dx + dz * dz > 0.0001
                }()
                if moved {
                    onMoveEnd?(
                        id,
                        Vector3(Double(pos.x), Double(dragLockY), Double(pos.z))
                    )
                }
            default:
                break
            }
        }

        private func entityName(_ entity: Entity) -> String? {
            var current: Entity? = entity
            while let e = current {
                if !e.name.isEmpty { return e.name }
                current = e.parent
            }
            return nil
        }

        private func findEntity(named id: String) -> Entity? {
            root?.children.first { $0.name == id }
        }

        private func floorPlaneHit(
            at screen: CGPoint,
            planeY: Float,
            in view: ARView
        ) -> SIMD3<Float>? {
            guard let ray = view.ray(through: screen) else { return nil }
            let origin = ray.origin
            let dir = ray.direction
            guard abs(dir.y) > 1e-5 else { return nil }
            let t = (planeY - origin.y) / dir.y
            guard t > 0 else { return nil }
            return origin + dir * t
        }

        /// Accurate under-finger point: ARView ray through touch, fixed depth along ray.
        private func freeSpacePoint(at screen: CGPoint, in view: ARView) -> Vector3? {
            guard let ray = view.ray(through: screen) else { return nil }
            let depth: Float = 1.25
            let world = ray.origin + normalize(ray.direction) * depth
            return Vector3(Double(world.x), Double(world.y), Double(world.z))
        }

        func publishPlacementHintIfNeeded() {
            let now = CACurrentMediaTime()
            guard now - lastHintPublish > 0.4, let view = hostView else { return }
            lastHintPublish = now
            let center = CGPoint(x: view.bounds.midX, y: view.bounds.midY + 40)
            if let hit = floorPlaneHit(at: center, planeY: 0, in: view) {
                onPlacementHint?(Vector3(Double(hit.x), 0, Double(hit.z)))
            } else if let ray = view.ray(through: center) {
                let p = ray.origin + normalize(ray.direction) * 1.6
                onPlacementHint?(Vector3(Double(p.x), 0, Double(p.z)))
            }
        }
    }

    @MainActor
    private func rebuild(in view: ARView, coordinator: Coordinator) {
        guard let root = coordinator.root else { return }
        let version = scene?.version ?? -1
        let count = scene?.objects.count ?? -1
        let strokeIds = strokes.map(\.strokeId)
        let ghostCount = ghosts.count
        if version == coordinator.renderedVersion,
           count == coordinator.renderedCount,
           selectedObjectId == coordinator.renderedSelection,
           strokeIds == coordinator.renderedStrokeIds,
           ghostCount == coordinator.renderedGhostCount {
            return
        }
        coordinator.renderedVersion = version
        coordinator.renderedCount = count
        coordinator.renderedSelection = selectedObjectId
        coordinator.renderedStrokeCount = strokes.count
        coordinator.renderedStrokeIds = strokeIds
        coordinator.renderedGhostCount = ghostCount
        coordinator.parent = self

        let keepNames: Set<String> = ["draft_stroke", "stroke_pending"]
        root.children.forEach { child in
            if !keepNames.contains(child.name) {
                child.removeFromParent()
            }
        }
        guard let scene else { return }

        for object in scene.objects where object.type != "wall" {
            let entity = FurnitureMeshBuilder.makeEntity(for: object, selected: object.id == selectedObjectId)
            root.addChild(entity)
        }
        for ghost in GhostAvatarAnchors.remoteGhosts(from: ghosts, localUserId: APIConfig.actorId) {
            root.addChild(makeGhost(ghost))
        }
        for stroke in strokes {
            root.addChild(ARStrokeMesh.makeEntity(stroke))
        }
        // Drop pending draft once committed strokes are in the graph.
        if let pending = root.children.first(where: { $0.name == "stroke_pending" }) {
            pending.removeFromParent()
        }
        if let draft = coordinator.draftEntity, draft.parent == nil {
            root.addChild(draft)
        }
    }

    private func makeGhost(_ user: PresenceUserDTO) -> Entity {
        let parent = Entity()
        parent.name = "ghost_\(user.userId)"
        if let pos = user.position {
            parent.position = Coordinates.toSIMD(pos)
        }
        let tint = UIColor(hex: user.color ?? "#6eb4c8") ?? .systemTeal
        let body = ModelEntity(
            mesh: .generateBox(width: 0.32, height: 0.7, depth: 0.32),
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

extension UIColor {
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

struct AROverlayView: View {
    var body: some View {
        Text("Use Live AR from the scan-first flow.")
            .foregroundStyle(.secondary)
    }
}
