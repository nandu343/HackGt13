import RealityKit
import SwiftUI
import UIKit

/// Non-AR RealityKit map (Simulator / secondary map view). Same Y-up meters scene graph.
struct SceneRealityView: UIViewRepresentable {
    let scene: SceneDTO?
    var selectedObjectId: String?
    var strokes: [DrawingStrokeDTO] = []
    var ghosts: [PresenceUserDTO] = []
    var drawMode: Bool = false
    var onSelect: ((String?) -> Void)?
    var onStrokeComplete: (([Vector3]) -> Void)?

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.environment.background = .color(UIColor(red: 0.06, green: 0.08, blue: 0.1, alpha: 1))
        context.coordinator.root = AnchorEntity(world: .zero)
        if let root = context.coordinator.root {
            view.scene.addAnchor(root)
        }
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tap)
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
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
        Coordinator()
    }

    final class Coordinator: NSObject {
        var root: AnchorEntity?
        weak var hostView: ARView?
        var onSelect: ((String?) -> Void)?
        var onStrokeComplete: (([Vector3]) -> Void)?
        var drawMode = false
        var renderedVersion: Int = -1
        var renderedObjectCount: Int = -1
        var renderedSelection: String? = "___"
        var renderedStrokeCount: Int = -1
        var renderedGhostCount: Int = -1
        var sceneSnapshot: SceneDTO?
        var strokesSnapshot: [DrawingStrokeDTO] = []
        var ghostsSnapshot: [PresenceUserDTO] = []
        var selectedId: String?
        private var draftPoints: [Vector3] = []

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard !drawMode, let view = hostView else { return }
            let loc = gesture.location(in: view)
            let hits = view.hitTest(loc)
            let name = hits.compactMap { $0.entity.name }.first {
                !$0.isEmpty && $0 != "floor" && !$0.hasPrefix("grid_")
                    && !$0.hasPrefix("ghost_") && !$0.hasPrefix("stroke_")
            }
            onSelect?(name)
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard drawMode, let view = hostView else { return }
            let loc = gesture.location(in: view)
            switch gesture.state {
            case .began:
                draftPoints = []
                if let p = mapSpacePoint(at: loc, in: view) { draftPoints = [p] }
            case .changed:
                guard let p = mapSpacePoint(at: loc, in: view) else { return }
                if let last = draftPoints.last {
                    let dx = p.x - last.x, dy = p.y - last.y, dz = p.z - last.z
                    if dx * dx + dy * dy + dz * dz < 0.0009 { return }
                }
                draftPoints.append(p)
            case .ended, .cancelled:
                let pts = draftPoints
                draftPoints = []
                if pts.count >= 2 { onStrokeComplete?(pts) }
            default:
                break
            }
        }

        /// Ray from orbit camera through screen into free space (~1.4 m along look).
        private func mapSpacePoint(at screen: CGPoint, in view: ARView) -> Vector3? {
            let cam = view.cameraTransform
            let camPos = cam.translation
            let size = view.bounds.size
            guard size.width > 1, size.height > 1 else { return nil }
            let ndcX = Float((2 * screen.x / size.width) - 1)
            let ndcY = Float(1 - (2 * screen.y / size.height))
            // Approximate look from camera rotation (local -Z).
            let q = cam.rotation
            let forward = simd_act(q, SIMD3<Float>(0, 0, -1))
            let right = simd_act(q, SIMD3<Float>(1, 0, 0))
            let up = simd_act(q, SIMD3<Float>(0, 1, 0))
            let depth: Float = 2.2
            let dir = normalize(forward + right * ndcX * 0.55 + up * ndcY * 0.55)
            let world = camPos + dir * depth
            return Vector3(Double(world.x), Double(world.y), Double(world.z))
        }
    }

    private func rebuild(in view: ARView, coordinator: Coordinator) {
        guard let root = coordinator.root else { return }
        let version = scene?.version ?? -1
        let count = scene?.objects.count ?? -1
        let strokeCount = strokes.count
        let ghostCount = ghosts.count
        if version == coordinator.renderedVersion,
           count == coordinator.renderedObjectCount,
           selectedObjectId == coordinator.renderedSelection,
           strokeCount == coordinator.renderedStrokeCount,
           ghostCount == coordinator.renderedGhostCount {
            return
        }
        coordinator.renderedVersion = version
        coordinator.renderedObjectCount = count
        coordinator.renderedSelection = selectedObjectId
        coordinator.renderedStrokeCount = strokeCount
        coordinator.renderedGhostCount = ghostCount
        coordinator.sceneSnapshot = scene
        coordinator.strokesSnapshot = strokes
        coordinator.ghostsSnapshot = ghosts
        coordinator.selectedId = selectedObjectId

        root.children.forEach { $0.removeFromParent() }

        guard let scene else {
            let placeholder = ModelEntity(
                mesh: .generateBox(size: 0.35),
                materials: [SimpleMaterial(color: .darkGray, isMetallic: false)]
            )
            placeholder.name = "empty"
            root.addChild(placeholder)
            return
        }

        addFloorGrid(to: root, bounds: scene.bounds)

        for object in scene.objects {
            root.addChild(makeFurnitureProxy(for: object, selected: object.id == selectedObjectId))
        }

        for stroke in strokes {
            root.addChild(ARStrokeMesh.makeEntity(stroke))
        }

        for ghost in GhostAvatarAnchors.remoteGhosts(from: ghosts, localUserId: APIConfig.actorId) {
            root.addChild(makeGhostEntity(ghost))
        }

        var cam = Transform()
        cam.translation = SIMD3(
            Float(scene.bounds.width) * 0.45,
            Float(max(scene.bounds.height * 0.75, 1.6)),
            Float(scene.bounds.length) * 1.05
        )
        cam.rotation = simd_quatf(angle: -0.42, axis: SIMD3(1, 0, 0))
            * simd_quatf(angle: 0.35, axis: SIMD3(0, 1, 0))
        view.cameraTransform = cam
    }

    private func addFloorGrid(to root: AnchorEntity, bounds: RoomBoundsDTO) {
        let floor = ModelEntity(
            mesh: .generatePlane(width: Float(bounds.width), depth: Float(bounds.length)),
            materials: [SimpleMaterial(color: UIColor(white: 0.14, alpha: 1), isMetallic: false)]
        )
        floor.name = "floor"
        floor.position = SIMD3(0, 0.001, 0)
        root.addChild(floor)

        let lineMat = SimpleMaterial(color: UIColor(white: 0.32, alpha: 0.85), isMetallic: false)
        let step: Float = 0.5
        let halfW = Float(bounds.width) / 2
        let halfL = Float(bounds.length) / 2
        var x: Float = -halfW
        while x <= halfW + 0.001 {
            let line = ModelEntity(
                mesh: .generateBox(width: 0.012, height: 0.004, depth: Float(bounds.length)),
                materials: [lineMat]
            )
            line.name = "grid_x_\(x)"
            line.position = SIMD3(x, 0.006, 0)
            root.addChild(line)
            x += step
        }
        var z: Float = -halfL
        while z <= halfL + 0.001 {
            let line = ModelEntity(
                mesh: .generateBox(width: Float(bounds.width), height: 0.004, depth: 0.012),
                materials: [lineMat]
            )
            line.name = "grid_z_\(z)"
            line.position = SIMD3(0, 0.006, z)
            root.addChild(line)
            z += step
        }
    }

    private func makeFurnitureProxy(for object: SceneObjectDTO, selected: Bool) -> Entity {
        let w = Float(object.dimensions?.width ?? 0.5)
        let h = Float(object.dimensions?.height ?? 0.5)
        let d = Float(object.dimensions?.depth ?? 0.5)
        let parent = Entity()
        parent.name = object.id
        parent.position = Coordinates.toSIMD(object.transform.position)
        parent.orientation = Coordinates.toSIMDQuat(object.transform.rotation)

        let baseColor = furnitureColor(for: object)
        let color = selected
            ? baseColor.withAlphaComponent(1).blended(with: .systemYellow) ?? baseColor
            : baseColor
        let mat = SimpleMaterial(color: color, isMetallic: object.type == "wall")

        switch object.type {
        case "wall":
            let wall = ModelEntity(
                mesh: .generateBox(width: w, height: h, depth: max(d, 0.06)),
                materials: [SimpleMaterial(color: UIColor(white: 0.55, alpha: 0.85), isMetallic: false)]
            )
            wall.name = object.id
            parent.addChild(wall)
        case "sofa":
            let seat = ModelEntity(
                mesh: .generateBox(width: w, height: h * 0.45, depth: d),
                materials: [mat]
            )
            seat.position.y = -h * 0.15
            seat.name = object.id
            let back = ModelEntity(
                mesh: .generateBox(width: w, height: h * 0.55, depth: d * 0.22),
                materials: [mat]
            )
            back.position = SIMD3(0, h * 0.05, -d * 0.35)
            back.name = object.id
            parent.addChild(seat)
            parent.addChild(back)
        case "table":
            let top = ModelEntity(
                mesh: .generateBox(width: w, height: max(h * 0.08, 0.04), depth: d),
                materials: [mat]
            )
            top.position.y = h * 0.42
            top.name = object.id
            parent.addChild(top)
            let legSize: Float = 0.05
            let insetX = w * 0.4
            let insetZ = d * 0.4
            for (sx, sz) in [(-1, -1), (-1, 1), (1, -1), (1, 1)] as [(Float, Float)] {
                let leg = ModelEntity(
                    mesh: .generateBox(width: legSize, height: h * 0.85, depth: legSize),
                    materials: [mat]
                )
                leg.position = SIMD3(sx * insetX, 0, sz * insetZ)
                leg.name = object.id
                parent.addChild(leg)
            }
        case "chair":
            let seat = ModelEntity(
                mesh: .generateBox(width: w, height: h * 0.12, depth: d),
                materials: [mat]
            )
            seat.position.y = -h * 0.15
            seat.name = object.id
            let back = ModelEntity(
                mesh: .generateBox(width: w, height: h * 0.55, depth: d * 0.12),
                materials: [mat]
            )
            back.position = SIMD3(0, h * 0.15, -d * 0.4)
            back.name = object.id
            parent.addChild(seat)
            parent.addChild(back)
        case "floor_lamp", "lamp":
            let pole = ModelEntity(
                mesh: .generateCylinder(height: h * 0.85, radius: 0.03),
                materials: [mat]
            )
            pole.name = object.id
            let shade = ModelEntity(
                mesh: .generateCylinder(height: h * 0.2, radius: max(w, d) * 0.35),
                materials: [SimpleMaterial(color: .systemYellow, isMetallic: false)]
            )
            shade.position.y = h * 0.4
            shade.name = object.id
            parent.addChild(pole)
            parent.addChild(shade)
        default:
            let box = ModelEntity(
                mesh: .generateBox(width: w, height: h, depth: d),
                materials: [mat]
            )
            box.name = object.id
            parent.addChild(box)
        }

        if selected {
            let ring = ModelEntity(
                mesh: .generateBox(width: w * 1.12, height: 0.02, depth: d * 1.12),
                materials: [SimpleMaterial(color: .systemYellow.withAlphaComponent(0.7), isMetallic: false)]
            )
            ring.position.y = -h * 0.48
            ring.name = object.id
            parent.addChild(ring)
        }

        return parent
    }

    private func furnitureColor(for object: SceneObjectDTO) -> UIColor {
        if object.source == "existing" {
            switch object.type {
            case "sofa": return UIColor(red: 0.35, green: 0.42, blue: 0.48, alpha: 1)
            case "table": return UIColor(red: 0.45, green: 0.32, blue: 0.22, alpha: 1)
            case "chair": return UIColor(red: 0.5, green: 0.38, blue: 0.28, alpha: 1)
            default: return UIColor(white: 0.42, alpha: 1)
            }
        }
        switch object.type {
        case "sofa": return .systemTeal
        case "table": return .systemBrown
        case "chair": return .systemOrange
        case "floor_lamp", "lamp": return .systemYellow
        default: return .systemIndigo
        }
    }

    private func makeGhostEntity(_ user: PresenceUserDTO) -> Entity {
        let parent = Entity()
        parent.name = "ghost_\(user.userId)"
        if let pos = user.position {
            parent.position = Coordinates.toSIMD(pos)
        }
        let tint = UIColor(hex: user.color ?? "#6eb4c8") ?? .systemTeal
        let opacity: CGFloat = user.voiceSpeaking == true ? 0.55 : 0.35
        let body = ModelEntity(
            mesh: .generateCylinder(height: 0.7, radius: 0.16),
            materials: [SimpleMaterial(color: tint.withAlphaComponent(opacity), isMetallic: false)]
        )
        body.name = "ghost_\(user.userId)"
        let head = ModelEntity(
            mesh: .generateSphere(radius: 0.14),
            materials: [SimpleMaterial(color: tint.withAlphaComponent(opacity + 0.1), isMetallic: false)]
        )
        head.position.y = 0.5
        head.name = "ghost_\(user.userId)"
        parent.addChild(body)
        parent.addChild(head)
        return parent
    }
}

private extension UIColor {
    func blended(with other: UIColor) -> UIColor? {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        guard getRed(&r1, green: &g1, blue: &b1, alpha: &a1),
              other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2) else { return nil }
        return UIColor(
            red: (r1 + r2) / 2,
            green: (g1 + g2) / 2,
            blue: (b1 + b2) / 2,
            alpha: max(a1, a2)
        )
    }

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

/// Legacy entry kept for project references; primary UI is ARRoomView (live camera AR).
struct SceneViewerView: View {
    var body: some View {
        Text("Open Live AR from the scan-first flow.")
            .foregroundStyle(.secondary)
    }
}

/// Primary post-scan surface: live camera AR (device) or map twin (Simulator) + draw / Plan / Invite.
struct ARRoomView: View {
    @Environment(SceneSyncStore.self) private var store
    var onRescan: () -> Void
    var onPlan: () -> Void
    var onInvite: () -> Void
    var onSettings: () -> Void

    @State private var drawMode = false
    #if targetEnvironment(simulator)
    @State private var mapOnly = true
    #else
    @State private var mapOnly = false
    #endif

    var body: some View {
        NavigationStack {
            ZStack {
                if store.scene == nil {
                    ContentUnavailableView {
                        Label("No room yet", systemImage: "camera.viewfinder")
                    } description: {
                        Text("Scan a room first, then enter live AR over the real space.")
                    } actions: {
                        Button("Back to scan") { onRescan() }
                    }
                } else {
                    #if targetEnvironment(simulator)
                    SceneRealityView(
                        scene: store.scene,
                        selectedObjectId: store.selectedObjectId,
                        strokes: store.strokes,
                        ghosts: store.presenceGhosts,
                        drawMode: drawMode,
                        onSelect: { store.selectedObjectId = $0 },
                        onStrokeComplete: { store.addStroke(points: $0) }
                    )
                    .ignoresSafeArea(edges: .bottom)
                    #else
                    if mapOnly {
                        SceneRealityView(
                            scene: store.scene,
                            selectedObjectId: store.selectedObjectId,
                            strokes: store.strokes,
                            ghosts: store.presenceGhosts,
                            drawMode: drawMode,
                            onSelect: { store.selectedObjectId = $0 },
                            onStrokeComplete: { store.addStroke(points: $0) }
                        )
                        .ignoresSafeArea(edges: .bottom)
                    } else {
                        ARViewContainer(
                            scene: store.scene,
                            selectedObjectId: store.selectedObjectId,
                            strokes: store.strokes,
                            ghosts: store.presenceGhosts,
                            drawMode: drawMode,
                            onSelect: { store.selectedObjectId = $0 },
                            onStrokeComplete: { store.addStroke(points: $0) }
                        )
                        .ignoresSafeArea(edges: .bottom)
                    }
                    #endif
                }

                VStack {
                    Spacer()
                    controlChrome
                }
            }
            .navigationTitle(mapOnly ? "Room map" : "Live AR")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Scan") { onRescan() }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    #if !targetEnvironment(simulator)
                    Button(mapOnly ? "Camera AR" : "Map") {
                        mapOnly.toggle()
                    }
                    #endif
                    Button {
                        Task { await store.refresh(markAsRoomMap: true) }
                    } label: {
                        if store.isBusy {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    Button { onSettings() } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .task {
                store.seedGhostStubsIfNeeded()
                store.connectRealtime()
                if store.scene == nil {
                    await store.refresh(markAsRoomMap: true)
                }
            }
            .onDisappear {
                store.disconnectRealtime()
            }
        }
    }

    private var controlChrome: some View {
        VStack(spacing: 10) {
            if let err = store.lastError {
                Text(err)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if drawMode {
                Text("Drag anywhere to sketch in AR space — strokes sync to peers.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let obj = store.selectedObject {
                selectionBar(obj)
            }

            Text(store.statusMessage)
                .font(.caption)
                .frame(maxWidth: .infinity)

            if let scene = store.scene {
                Text(
                    "v\(scene.version) · \(scene.objects.count) objects · \(store.strokes.count) strokes · "
                        + String(
                            format: "%.1f×%.1f×%.1f m",
                            scene.bounds.width,
                            scene.bounds.length,
                            scene.bounds.height
                        )
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button {
                    drawMode.toggle()
                    if drawMode { store.selectedObjectId = nil }
                } label: {
                    Label(drawMode ? "Exit draw" : "Draw in space", systemImage: "pencil.tip")
                }
                .buttonStyle(.borderedProminent)
                .tint(drawMode ? .orange : .accentColor)
                .disabled(store.scene == nil)

                if drawMode {
                    Button("Clear mine") { store.clearOwnStrokes() }
                        .buttonStyle(.bordered)
                }

                Button { onPlan() } label: {
                    Label("Plan", systemImage: "wand.and.stars")
                }
                .buttonStyle(.bordered)
                .disabled(store.scene == nil || store.isBusy || drawMode)

                Button { onInvite() } label: {
                    Label("Invite", systemImage: "person.badge.plus")
                }
                .buttonStyle(.bordered)
                .disabled(store.scene == nil || store.isBusy)

                #if !targetEnvironment(simulator)
                if !drawMode {
                    Button {
                        Task { await placeCatalogChair() }
                    } label: {
                        Label("Place", systemImage: "plus.square.on.square")
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.scene == nil || store.isBusy)
                }
                #endif
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    private func selectionBar(_ obj: SceneObjectDTO) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(obj.type.replacingOccurrences(of: "_", with: " "))")
                    .font(.subheadline.weight(.semibold))
                if obj.source == "existing" {
                    Text("room")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.orange.opacity(0.25), in: Capsule())
                }
                Spacer()
                Button("Deselect") { store.selectedObjectId = nil }
                    .font(.caption)
            }

            if obj.type != "wall", obj.movable != false {
                HStack(spacing: 8) {
                    Button("←") { Task { await store.moveSelected(dx: -0.25, dz: 0) } }
                        .buttonStyle(.bordered)
                    Button("→") { Task { await store.moveSelected(dx: 0.25, dz: 0) } }
                        .buttonStyle(.bordered)
                    Button("↑") { Task { await store.moveSelected(dx: 0, dz: -0.25) } }
                        .buttonStyle(.bordered)
                    Button("↓") { Task { await store.moveSelected(dx: 0, dz: 0.25) } }
                        .buttonStyle(.bordered)
                    Spacer()
                    Button("Remove", role: .destructive) {
                        Task { await store.removeSelected() }
                    }
                    .buttonStyle(.bordered)
                }
                .disabled(store.isBusy)
            } else {
                Text("Walls stay fixed in the shared scene.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    private func placeCatalogChair() async {
        guard let scene = store.scene else { return }
        let id = "ar_anchor_\(UUID().uuidString.prefix(6))"
        let position = Vector3(0.4, 0.43, -min(0.9, scene.bounds.length * 0.25))
        let op = SceneOperationDTO(
            type: .addObject,
            objectId: id,
            targetPosition: position,
            targetRotation: .identity,
            assetId: "asset_chair_fold_01",
            productId: "chair_fold_01",
            objectType: "chair",
            dimensions: DimensionsDTO(width: 0.48, height: 0.86, depth: 0.52),
            movable: true,
            source: "catalog"
        )
        await store.pushOps([op])
        store.selectedObjectId = id
    }
}
