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
    var drawColor: String = "#e2b45c"
    var onSelect: ((String?) -> Void)?
    var onStrokeComplete: (([Vector3]) -> Void)?

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.environment.background = .color(UIColor(red: 0.06, green: 0.08, blue: 0.1, alpha: 1))
        context.coordinator.root = AnchorEntity(world: .zero)
        if let root = context.coordinator.root {
            view.scene.addAnchor(root)
        }
        let camera = PerspectiveCamera()
        camera.camera = PerspectiveCameraComponent(near: 0.01, far: 100, fieldOfViewInDegrees: 60)
        let cameraAnchor = AnchorEntity(world: .zero)
        cameraAnchor.addChild(camera)
        view.scene.addAnchor(cameraAnchor)
        context.coordinator.camera = camera
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tap)
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(pan)
        context.coordinator.hostView = view
        context.coordinator.onSelect = onSelect
        context.coordinator.onStrokeComplete = onStrokeComplete
        context.coordinator.drawMode = drawMode
        context.coordinator.drawColor = drawColor
        rebuild(coordinator: context.coordinator)
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        let c = context.coordinator
        c.onSelect = onSelect
        c.onStrokeComplete = onStrokeComplete
        c.drawMode = drawMode
        c.drawColor = drawColor
        if c.isDrawing { return }
        rebuild(coordinator: c)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator: NSObject {
        var root: AnchorEntity?
        var camera: PerspectiveCamera?
        weak var hostView: ARView?
        var onSelect: ((String?) -> Void)?
        var onStrokeComplete: (([Vector3]) -> Void)?
        var drawMode = false
        var drawColor = "#e2b45c"
        var isDrawing = false
        var renderedVersion: Int = -1
        var renderedObjectCount: Int = -1
        var renderedSelection: String? = "___"
        var renderedStrokeIds: [String] = []
        var renderedGhostCount: Int = -1
        var sceneSnapshot: SceneDTO?
        var strokesSnapshot: [DrawingStrokeDTO] = []
        var ghostsSnapshot: [PresenceUserDTO] = []
        var selectedId: String?
        private var draftPoints: [Vector3] = []
        var draftEntity: Entity?
        private var lastDraftSIMD: SIMD3<Float>?
        private var draftMaterial = SimpleMaterial(color: .systemYellow, isMetallic: false)

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
                isDrawing = true
                draftPoints = []
                lastDraftSIMD = nil
                draftEntity?.removeFromParent()
                let draft = Entity()
                draft.name = "draft_stroke"
                draftEntity = draft
                root?.addChild(draft)
                let ui = UIColor(hex: drawColor) ?? .systemYellow
                draftMaterial = SimpleMaterial(color: ui.withAlphaComponent(0.95), isMetallic: false)
                if let p = mapSpacePoint(at: loc, in: view) {
                    draftPoints = [p]
                    lastDraftSIMD = Coordinates.toSIMD(p)
                }
            case .changed:
                guard let p = mapSpacePoint(at: loc, in: view) else { return }
                let simd = Coordinates.toSIMD(p)
                if let last = lastDraftSIMD {
                    let dx = simd.x - last.x, dy = simd.y - last.y, dz = simd.z - last.z
                    if dx * dx + dy * dy + dz * dz < 0.0009 { return }
                    draftEntity?.addChild(
                        ARStrokeMesh.segment(
                            from: last, to: simd, radius: 0.011,
                            material: draftMaterial, name: "draft_seg"
                        )
                    )
                }
                draftPoints.append(p)
                lastDraftSIMD = simd
            case .ended, .cancelled:
                let pts = draftPoints
                draftEntity?.name = "stroke_pending"
                draftEntity = nil
                draftPoints = []
                lastDraftSIMD = nil
                isDrawing = false
                if pts.count >= 2 { onStrokeComplete?(pts) }
            default:
                break
            }
        }

        private func mapSpacePoint(at screen: CGPoint, in view: ARView) -> Vector3? {
            let cam = view.cameraTransform
            let camPos = cam.translation
            let size = view.bounds.size
            guard size.width > 1, size.height > 1 else { return nil }
            let ndcX = Float((2 * screen.x / size.width) - 1)
            let ndcY = Float(1 - (2 * screen.y / size.height))
            let q = cam.rotation
            let forward = simd_act(q, SIMD3<Float>(0, 0, -1))
            let right = simd_act(q, SIMD3<Float>(1, 0, 0))
            let up = simd_act(q, SIMD3<Float>(0, 1, 0))
            let dir = normalize(forward + right * ndcX * 0.55 + up * ndcY * 0.55)
            let world = camPos + dir * 2.2
            return Vector3(Double(world.x), Double(world.y), Double(world.z))
        }
    }

    @MainActor
    private func rebuild(coordinator: Coordinator) {
        guard let root = coordinator.root else { return }
        let version = scene?.version ?? -1
        let count = scene?.objects.count ?? -1
        let strokeIds = strokes.map(\.strokeId)
        let ghostCount = ghosts.count
        if version == coordinator.renderedVersion,
           count == coordinator.renderedObjectCount,
           selectedObjectId == coordinator.renderedSelection,
           strokeIds == coordinator.renderedStrokeIds,
           ghostCount == coordinator.renderedGhostCount {
            return
        }
        coordinator.renderedVersion = version
        coordinator.renderedObjectCount = count
        coordinator.renderedSelection = selectedObjectId
        coordinator.renderedStrokeIds = strokeIds
        coordinator.renderedGhostCount = ghostCount
        coordinator.sceneSnapshot = scene
        coordinator.strokesSnapshot = strokes
        coordinator.ghostsSnapshot = ghosts
        coordinator.selectedId = selectedObjectId

        let keep: Set<String> = ["draft_stroke", "stroke_pending"]
        root.children.forEach { child in
            if !keep.contains(child.name) { child.removeFromParent() }
        }

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
            root.addChild(FurnitureMeshBuilder.makeEntity(for: object, selected: object.id == selectedObjectId))
        }
        for stroke in strokes {
            root.addChild(ARStrokeMesh.makeEntity(stroke))
        }
        if let pending = root.children.first(where: { $0.name == "stroke_pending" }) {
            pending.removeFromParent()
        }
        for ghost in GhostAvatarAnchors.remoteGhosts(from: ghosts, localUserId: APIConfig.actorId) {
            root.addChild(makeGhostEntity(ghost))
        }
        if let draft = coordinator.draftEntity, draft.parent == nil {
            root.addChild(draft)
        }

        if let camera = coordinator.camera {
            var cam = Transform()
            cam.translation = SIMD3(
                Float(scene.bounds.width) * 0.45,
                Float(max(scene.bounds.height * 0.75, 1.6)),
                Float(scene.bounds.length) * 1.05
            )
            cam.rotation = simd_quatf(angle: -0.42, axis: SIMD3(1, 0, 0))
                * simd_quatf(angle: 0.35, axis: SIMD3(0, 1, 0))
            camera.transform = cam
        }
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

    private func makeGhostEntity(_ user: PresenceUserDTO) -> Entity {
        let parent = Entity()
        parent.name = "ghost_\(user.userId)"
        if let pos = user.position {
            parent.position = Coordinates.toSIMD(pos)
        }
        let tint = UIColor(hex: user.color ?? "#6eb4c8") ?? .systemTeal
        let opacity: CGFloat = user.voiceSpeaking == true ? 0.55 : 0.35
        let body = ModelEntity(
            mesh: .generateBox(width: 0.32, height: 0.7, depth: 0.32),
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

struct SceneViewerView: View {
    var body: some View {
        Text("Open Live AR from the scan-first flow.")
            .foregroundStyle(.secondary)
    }
}

// MARK: - Live AR HUD

private enum DrawPalette {
    static let colors: [(hex: String, label: String)] = [
        ("#e2b45c", "Gold"),
        ("#6ec8e8", "Cyan"),
        ("#f07178", "Coral"),
        ("#c3e88d", "Lime"),
        ("#ffffff", "White")
    ]
}

/// Primary post-scan surface: live camera AR (device) or map twin (Simulator).
struct ARRoomView: View {
    @Environment(SceneSyncStore.self) private var store
    var onRescan: () -> Void
    var onPlan: () -> Void
    var onInvite: () -> Void
    var onSettings: () -> Void

    @State private var drawMode = false
    @State private var showCatalog = false
    #if targetEnvironment(simulator)
    @State private var mapOnly = true
    #else
    @State private var mapOnly = false
    #endif

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if store.scene == nil {
                emptyState
            } else {
                arCanvas
                    .ignoresSafeArea()
            }

            VStack(spacing: 0) {
                topBar
                Spacer()
                if drawMode {
                    drawToolbar
                } else if let obj = store.selectedObject {
                    selectionCard(obj)
                }
                bottomBar
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showCatalog) {
            CatalogPickerSheet()
        }
        .task {
            store.seedGhostStubsIfNeeded()
            store.connectRealtime()
            await store.loadCatalogIfNeeded()
            if store.scene == nil {
                await store.refresh(markAsRoomMap: true)
            }
        }
        .onDisappear {
            store.disconnectRealtime()
        }
    }

    // MARK: Canvas

    @ViewBuilder
    private var arCanvas: some View {
        #if targetEnvironment(simulator)
        SceneRealityView(
            scene: store.scene,
            selectedObjectId: store.selectedObjectId,
            strokes: store.strokes,
            ghosts: store.presenceGhosts,
            drawMode: drawMode,
            drawColor: store.drawColor,
            onSelect: { store.selectedObjectId = $0 },
            onStrokeComplete: { store.addStroke(points: $0) }
        )
        #else
        if mapOnly {
            SceneRealityView(
                scene: store.scene,
                selectedObjectId: store.selectedObjectId,
                strokes: store.strokes,
                ghosts: store.presenceGhosts,
                drawMode: drawMode,
                drawColor: store.drawColor,
                onSelect: { store.selectedObjectId = $0 },
                onStrokeComplete: { store.addStroke(points: $0) }
            )
        } else {
            ARViewContainer(
                scene: store.scene,
                selectedObjectId: store.selectedObjectId,
                strokes: store.strokes,
                ghosts: store.presenceGhosts,
                drawMode: drawMode,
                drawColor: store.drawColor,
                onSelect: { store.selectedObjectId = $0 },
                onStrokeComplete: { store.addStroke(points: $0) },
                onMoveEnd: { id, pos in
                    Task { await store.moveObject(id: id, to: pos) }
                },
                onPlacementHint: { store.placementHint = $0 }
            )
        }
        #endif
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No room yet", systemImage: "camera.viewfinder")
        } description: {
            Text("Scan a room first, then enter live AR over the real space.")
        } actions: {
            Button("Back to scan") { onRescan() }
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: Top chrome

    private var topBar: some View {
        HStack(spacing: 10) {
            hudIconButton("chevron.left", label: "Scan") { onRescan() }

            VStack(alignment: .leading, spacing: 2) {
                Text(mapOnly ? "Room map" : "Live AR")
                    .font(.headline.weight(.semibold))
                HStack(spacing: 6) {
                    Circle()
                        .fill(store.wsConnected ? Color.green : Color.orange.opacity(0.8))
                        .frame(width: 6, height: 6)
                    Text(store.wsConnected ? "Live" : "Offline")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                    if let scene = store.scene {
                        Text("· v\(scene.version)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            #if !targetEnvironment(simulator)
            hudIconButton(mapOnly ? "camera.viewfinder" : "square.3.layers.3d") {
                mapOnly.toggle()
            }
            #endif
            hudIconButton("arrow.clockwise") {
                Task { await store.refresh(markAsRoomMap: true) }
            }
            hudIconButton("gearshape") { onSettings() }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial.opacity(0.92))
    }

    // MARK: Draw toolbar

    private var drawToolbar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sketch in space")
                .font(.subheadline.weight(.semibold))
            Text("Ink follows your finger · syncs when you lift.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                ForEach(DrawPalette.colors, id: \.hex) { swatch in
                    Button {
                        store.drawColor = swatch.hex
                    } label: {
                        Circle()
                            .fill(Color(uiColor: UIColor(hex: swatch.hex) ?? .yellow))
                            .frame(width: 28, height: 28)
                            .overlay {
                                Circle()
                                    .strokeBorder(
                                        store.drawColor == swatch.hex ? Color.white : Color.clear,
                                        lineWidth: 2.5
                                    )
                            }
                    }
                    .accessibilityLabel(swatch.label)
                }
                Spacer()
                Button("Clear mine") { store.clearOwnStrokes() }
                    .font(.caption.weight(.medium))
                Button("Clear all") { store.clearAllStrokes() }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    // MARK: Selection

    private func selectionCard(_ obj: SceneObjectDTO) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(obj.type.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.subheadline.weight(.semibold))
                if obj.source == "existing" {
                    Text("SCANNED")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.orange.opacity(0.3), in: Capsule())
                }
                Spacer()
                Button("Done") { store.selectedObjectId = nil }
                    .font(.caption.weight(.semibold))
            }

            if obj.type != "wall", obj.movable != false {
                Text("Drag on the floor to move · or nudge")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    nudge("arrow.left") { Task { await store.moveSelected(dx: -0.25, dz: 0) } }
                    nudge("arrow.right") { Task { await store.moveSelected(dx: 0.25, dz: 0) } }
                    nudge("arrow.up") { Task { await store.moveSelected(dx: 0, dz: -0.25) } }
                    nudge("arrow.down") { Task { await store.moveSelected(dx: 0, dz: 0.25) } }
                    Spacer()
                    Button(role: .destructive) {
                        Task { await store.removeSelected() }
                    } label: {
                        Label("Remove", systemImage: "trash")
                            .font(.caption.weight(.semibold))
                    }
                    .disabled(store.isBusy)
                }
            } else {
                Text("Walls stay fixed in the shared scene.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 8) {
            if let err = store.lastError {
                Text(err)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(store.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) {
                        drawMode.toggle()
                        if drawMode { store.selectedObjectId = nil }
                    }
                } label: {
                    Image(systemName: drawMode ? "xmark" : "pencil.tip")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(ARToolButtonStyle(prominent: drawMode, tint: .orange))

                if !drawMode {
                    Button { showCatalog = true } label: {
                        Image(systemName: "plus")
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(ARToolButtonStyle())
                    .disabled(store.scene == nil || store.isBusy)

                    Button { onPlan() } label: {
                        Image(systemName: "wand.and.stars")
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(ARToolButtonStyle())
                    .disabled(store.scene == nil || store.isBusy)

                    Button { onInvite() } label: {
                        Image(systemName: "person.badge.plus")
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(ARToolButtonStyle())
                    .disabled(store.scene == nil || store.isBusy)
                }

                Spacer(minLength: 0)

                if let scene = store.scene {
                    Text("\(scene.objects.count) · \(store.strokes.count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial.opacity(0.95))
    }

    // MARK: Helpers

    private func hudIconButton(_ systemName: String, label: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if let label {
                Label(label, systemImage: systemName)
                    .labelStyle(.iconOnly)
                    .font(.body.weight(.medium))
            } else {
                Image(systemName: systemName)
                    .font(.body.weight(.medium))
            }
        }
        .frame(width: 36, height: 36)
        .background(.thinMaterial, in: Circle())
    }

    private func nudge(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.caption.weight(.bold))
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.bordered)
        .disabled(store.isBusy)
    }
}

private struct ARToolButtonStyle: ButtonStyle {
    var prominent = false
    var tint: Color = .cyan

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(prominent ? Color.black : Color.primary)
            .frame(width: 48, height: 48)
            .background(
                prominent ? AnyShapeStyle(tint) : AnyShapeStyle(.thinMaterial),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
