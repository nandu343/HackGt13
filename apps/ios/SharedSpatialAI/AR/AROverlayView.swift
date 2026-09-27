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
        view.automaticallyConfigureSession = false
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        view.session.delegate = context.coordinator
        view.session.run(config, options: [.resetTracking, .removeExistingAnchors])

        // Shared scene Y=0 must be the *detected floor*, not ARKit world origin
        // (world origin is typically phone height when tracking starts → hover bug).
        let root = AnchorEntity(world: .zero)
        root.name = "scene_floor_root"
        context.coordinator.root = root
        view.scene.addAnchor(root)

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        tap.delegate = context.coordinator
        view.addGestureRecognizer(tap)
        let pan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        pan.maximumNumberOfTouches = 1
        pan.cancelsTouchesInView = true
        pan.delegate = context.coordinator
        context.coordinator.objectPan = pan
        view.addGestureRecognizer(pan)
        // Camera orbit must wait for our pan to fail (empty space → orbit still works).
        for gr in view.gestureRecognizers ?? [] where gr !== pan && gr !== tap {
            gr.require(toFail: pan)
        }
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
    final class Coordinator: NSObject, UIGestureRecognizerDelegate, ARSessionDelegate {
        var parent: ARViewContainer
        var root: AnchorEntity?
        weak var hostView: ARView?
        weak var objectPan: UIPanGestureRecognizer?
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
        /// Local (scene) Y locked for drag — center pivot seated height, not world Y.
        private var dragLockY: Float = 0
        private var dragStartPos: SIMD3<Float>?
        /// Finger→object XZ offset so the mesh does not jump under the finger.
        private var dragOffsetXZ: SIMD3<Float> = .zero
        private var lastHintPublish: CFTimeInterval = 0
        /// Object ids currently swapping in a remote/bundled USDZ.
        private var loadingModelIds: Set<String> = []

        /// World-space Y of the lowest horizontal plane (ARKit floor).
        private(set) var floorWorldY: Float = 0
        private(set) var hasFloorAlignment = false

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

        // MARK: - Floor alignment (critical: kill hover)

        nonisolated func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
            Task { @MainActor [weak self] in
                self?.ingestPlanes(anchors)
            }
        }

        nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
            Task { @MainActor [weak self] in
                self?.ingestPlanes(anchors)
            }
        }

        /// Call on rebuild / hint so we pick up planes that already exist.
        func refreshFloorFromSession() {
            guard let frame = hostView?.session.currentFrame else {
                applyCameraHeightFallback()
                return
            }
            ingestPlanes(frame.anchors)
            if !hasFloorAlignment {
                applyCameraHeightFallback(cameraY: frame.camera.transform.columns.3.y)
            }
        }

        private func ingestPlanes(_ anchors: [ARAnchor]) {
            let horizontals = anchors.compactMap { $0 as? ARPlaneAnchor }
                .filter { $0.alignment == .horizontal }
            guard let lowest = horizontals.map({ $0.transform.columns.3.y }).min() else { return }
            applyFloorWorldY(lowest)
        }

        /// Until ARKit reports a horizontal plane, approximate floor ~1.35 m below the camera.
        private func applyCameraHeightFallback(cameraY: Float? = nil) {
            guard !hasFloorAlignment else { return }
            let camY: Float
            if let cameraY {
                camY = cameraY
            } else if let y = hostView?.session.currentFrame?.camera.transform.columns.3.y {
                camY = y
            } else {
                return
            }
            // Typical handheld phone height; better than leaving Y=0 at device origin.
            root?.position = SIMD3(0, camY - 1.35, 0)
        }

        private func applyFloorWorldY(_ y: Float) {
            // Prefer the lowest horizontal plane (true floor over tabletops).
            if hasFloorAlignment {
                // Only drop further down (new lower floor), avoid jumping up to tables.
                if y >= floorWorldY - 0.02 { return }
            }
            floorWorldY = y
            hasFloorAlignment = true
            // Shared local Y=0 → detected floor. Keep XZ at session origin (user-centric).
            root?.position = SIMD3(0, floorWorldY, 0)
        }

        /// World → scene-local (floor-root) position.
        private func worldToScene(_ world: SIMD3<Float>) -> SIMD3<Float> {
            guard let root else { return world }
            return root.convert(position: world, from: nil)
        }

        /// Seated local Y for an object (center pivot on floor).
        private func seatedLocalY(for object: SceneObjectDTO) -> Float {
            let h = Float(object.dimensions?.heightMeters ?? 0.5)
            if Coordinates.sitsOnFloor(object) {
                return Coordinates.seatedY(heightMeters: h)
            }
            return Float(Coordinates.renderPosition(for: object).y)
        }

        // MARK: - Gestures

        /// Only claim the pan when drawing or when the finger is on (or near) furniture.
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer === objectPan, let view = hostView else { return true }
            if drawMode { return true }
            let loc = gestureRecognizer.location(in: view)
            return furnitureId(at: loc, in: view) != nil
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            // Never share the drag/draw pan with ARView camera orbit.
            if gestureRecognizer === objectPan || otherGestureRecognizer === objectPan {
                return false
            }
            return true
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard !drawMode, draggingObjectId == nil, let view = hostView else { return }
            let loc = gesture.location(in: view)
            onSelect?(furnitureId(at: loc, in: view))
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

        private func furnitureId(at loc: CGPoint, in view: ARView) -> String? {
            let hits = view.hitTest(loc)
            if let name = hits.compactMap({ entityName($0.entity) }).first(where: isFurnitureName) {
                return name
            }
            // Soft hit: already-selected object stays draggable near its footprint.
            if let selected = parent.selectedObjectId,
               let entity = findEntity(named: selected),
               let hit = floorPlaneHitLocal(at: loc, in: view) {
                let dx = hit.x - entity.position.x
                let dz = hit.z - entity.position.z
                if dx * dx + dz * dz < 0.55 { return selected }
            }
            return nil
        }

        private func isFurnitureName(_ name: String) -> Bool {
            !name.isEmpty
                && name != "floor"
                && name != "scene_floor_root"
                && !name.hasPrefix("grid_")
                && !name.hasPrefix("ghost_")
                && !name.hasPrefix("stroke_")
                && !name.hasPrefix("draft_")
                && !name.hasPrefix("scan_")
                && !name.hasPrefix("loading_")
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
                guard let id = furnitureId(at: loc, in: view),
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
                // Lock to seated floor height (not whatever world Y the mesh currently has).
                dragLockY = seatedLocalY(for: obj)
                entity.position.y = dragLockY
                dragStartPos = entity.position
                // Keep the grab point under the finger (no center-snap jump).
                if let hit = floorPlaneHitLocal(at: loc, in: view) {
                    dragOffsetXZ = SIMD3(
                        entity.position.x - hit.x,
                        0,
                        entity.position.z - hit.z
                    )
                } else {
                    dragOffsetXZ = .zero
                }
            case .changed:
                guard let id = draggingObjectId,
                      let entity = findEntity(named: id),
                      let hit = floorPlaneHitLocal(at: loc, in: view)
                else { return }
                entity.position = SIMD3(
                    hit.x + dragOffsetXZ.x,
                    dragLockY,
                    hit.z + dragOffsetXZ.z
                )
            case .ended, .cancelled:
                guard let id = draggingObjectId,
                      let entity = findEntity(named: id)
                else {
                    draggingObjectId = nil
                    dragStartPos = nil
                    dragOffsetXZ = .zero
                    return
                }
                let pos = entity.position
                let moved: Bool = {
                    guard let start = dragStartPos else { return true }
                    let dx = pos.x - start.x
                    let dz = pos.z - start.z
                    return dx * dx + dz * dz > 0.0001
                }()
                let lockY = dragLockY
                if moved {
                    // Keep draggingObjectId set briefly so updateUIView does not rebuild
                    // with the pre-move scene before the optimistic store patch lands.
                    onMoveEnd?(
                        id,
                        Vector3(Double(pos.x), Double(lockY), Double(pos.z))
                    )
                    DispatchQueue.main.async { [weak self] in
                        self?.draggingObjectId = nil
                        self?.dragStartPos = nil
                        self?.dragOffsetXZ = .zero
                    }
                } else {
                    draggingObjectId = nil
                    dragStartPos = nil
                    dragOffsetXZ = .zero
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

        /// Floor XZ under the finger in **scene-local** space (Y ≈ 0 on the floor root).
        private func floorPlaneHitLocal(at screen: CGPoint, in view: ARView) -> SIMD3<Float>? {
            refreshFloorFromSession()
            let results = view.raycast(
                from: screen,
                allowing: .existingPlaneGeometry,
                alignment: .horizontal
            )
            // Prefer the lowest hit (floor over tabletops).
            let sorted = results.sorted {
                $0.worldTransform.columns.3.y < $1.worldTransform.columns.3.y
            }
            if let first = sorted.first {
                let t = first.worldTransform.columns.3
                var local = worldToScene(SIMD3(t.x, t.y, t.z))
                local.y = 0
                return local
            }
            // Math plane at detected floor (world Y), converted to scene-local.
            let worldFloorY = hasFloorAlignment ? floorWorldY : (root?.position.y ?? 0)
            guard let ray = view.ray(through: screen) else { return nil }
            let origin = ray.origin
            let dir = ray.direction
            guard abs(dir.y) > 1e-5 else { return nil }
            let t = (worldFloorY - origin.y) / dir.y
            guard t > 0 else { return nil }
            let world = origin + dir * t
            var local = worldToScene(world)
            local.y = 0
            return local
        }

        /// Accurate under-finger point: ARView ray through touch, fixed depth along ray.
        private func freeSpacePoint(at screen: CGPoint, in view: ARView) -> Vector3? {
            guard let ray = view.ray(through: screen) else { return nil }
            let depth: Float = 1.25
            let world = ray.origin + normalize(ray.direction) * depth
            let local = worldToScene(world)
            return Vector3(Double(local.x), Double(local.y), Double(local.z))
        }

        func publishPlacementHintIfNeeded() {
            let now = CACurrentMediaTime()
            guard now - lastHintPublish > 0.4, let view = hostView else { return }
            lastHintPublish = now
            refreshFloorFromSession()
            let center = CGPoint(x: view.bounds.midX, y: view.bounds.midY + 40)
            if let hit = floorPlaneHitLocal(at: center, in: view) {
                onPlacementHint?(Vector3(Double(hit.x), 0, Double(hit.z)))
            } else if let ray = view.ray(through: center) {
                let world = ray.origin + normalize(ray.direction) * 1.6
                let local = worldToScene(world)
                onPlacementHint?(Vector3(Double(local.x), 0, Double(local.z)))
            }
        }

        /// Swap composite stand-in for a bundled/remote USDZ when available (async).
        func enqueueRemoteModelIfNeeded(for object: SceneObjectDTO, onto entity: Entity) {
            guard !loadingModelIds.contains(object.id) else { return }
            guard ProductModelLoader.shouldAttemptUSDZ(for: object) else { return }
            loadingModelIds.insert(object.id)
            let objectId = object.id
            let selected = object.id == parent.selectedObjectId
            Task { @MainActor in
                defer { loadingModelIds.remove(objectId) }
                guard let loaded = await ProductModelLoader.loadUSDZEntity(for: object, selected: selected),
                      let root = self.root,
                      self.draggingObjectId != objectId,
                      let current = root.children.first(where: { $0.name == objectId })
                else { return }
                let pos = current.position
                let orient = current.orientation
                let scale = current.scale
                loaded.position = pos
                loaded.orientation = orient
                loaded.scale = scale
                current.removeFromParent()
                root.addChild(loaded)
            }
        }
    }

    @MainActor
    private func rebuild(in view: ARView, coordinator: Coordinator) {
        guard let root = coordinator.root else { return }
        coordinator.refreshFloorFromSession()
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
            coordinator.enqueueRemoteModelIfNeeded(for: object, onto: entity)
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
