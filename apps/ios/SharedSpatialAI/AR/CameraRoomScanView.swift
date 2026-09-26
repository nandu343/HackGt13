import ARKit
import RealityKit
import SwiftUI
import UIKit

#if !targetEnvironment(simulator)
/// Camera-based room scan: ARKit world tracking + plane detection (works without LiDAR).
struct CameraRoomScanView: View {
    var sceneId: String
    var onComplete: (SceneDTO) -> Void
    var onCancel: () -> Void

    @StateObject private var model = CameraRoomScanModel()

    var body: some View {
        ZStack {
            CameraRoomScanRepresentable(model: model)
                .ignoresSafeArea()

            VStack {
                instructionBanner
                Spacer()
                bottomBar
            }
        }
        .preferredColorScheme(.dark)
    }

    private var instructionBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Camera scan")
                .font(.headline)
            Text(
                "Walk the room so floors and walls appear. Optional: tap the floor to mark corners. Then Finish scan."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Label("\(model.horizontalCount) floors", systemImage: "square.dashed")
                Label("\(model.verticalCount) walls", systemImage: "rectangle.split.3x1")
                Label("\(model.cornerCount) corners", systemImage: "mappin.and.ellipse")
            }
            .font(.caption2)
            .foregroundStyle(.cyan)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            if let err = model.lastError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 12) {
                Button("Cancel") { onCancel() }
                    .buttonStyle(.bordered)
                Button("Clear corners") { model.clearCorners() }
                    .buttonStyle(.bordered)
                    .disabled(model.cornerCount == 0)
                Button("Finish scan") { finish() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canFinish)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }

    private func finish() {
        let scene = model.buildScene(sceneId: sceneId)
        onComplete(scene)
    }
}

@MainActor
final class CameraRoomScanModel: ObservableObject {
    @Published var horizontalCount = 0
    @Published var verticalCount = 0
    @Published var cornerCount = 0
    @Published var lastError: String?
    /// Bumped when corners are cleared so the AR overlay can drop markers.
    @Published var cornerEpoch = 0

    private(set) var planes: [UUID: DetectedPlaneSnapshot] = [:]
    private(set) var corners: [SIMD3<Float>] = []

    var canFinish: Bool {
        !planes.isEmpty || corners.count >= 3
    }

    func upsertPlane(_ snapshot: DetectedPlaneSnapshot, id: UUID) {
        planes[id] = snapshot
        refreshCounts()
    }

    func removePlane(id: UUID) {
        planes.removeValue(forKey: id)
        refreshCounts()
    }

    func addCorner(_ point: SIMD3<Float>) {
        if let last = corners.last {
            let d = point - last
            if length(d) < 0.15 { return }
        }
        corners.append(point)
        cornerCount = corners.count
        lastError = nil
    }

    func clearCorners() {
        corners.removeAll()
        cornerCount = 0
        cornerEpoch += 1
    }

    func buildScene(sceneId: String) -> SceneDTO {
        CameraScanExporter.export(
            sceneId: sceneId,
            planes: Array(planes.values),
            cornerPoints: corners
        )
    }

    private func refreshCounts() {
        horizontalCount = planes.values.filter { $0.alignment == .horizontal }.count
        verticalCount = planes.values.filter { $0.alignment == .vertical }.count
    }
}

struct CameraRoomScanRepresentable: UIViewRepresentable {
    @ObservedObject var model: CameraRoomScanModel

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero)
        view.automaticallyConfigureSession = false

        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        // Never require LiDAR mesh / scene reconstruction for this path.
        view.session.delegate = context.coordinator
        view.session.run(config, options: [.resetTracking, .removeExistingAnchors])

        context.coordinator.hostView = view
        context.coordinator.model = model

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.model = model
        context.coordinator.syncCornerMarkersIfNeeded()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    final class Coordinator: NSObject, ARSessionDelegate {
        var model: CameraRoomScanModel
        weak var hostView: ARView?
        private var cornerMarkers: [Entity] = []
        private var planeEntities: [UUID: ModelEntity] = [:]
        private let overlayRoot = AnchorEntity(world: .zero)
        private var lastCornerEpoch = 0

        init(model: CameraRoomScanModel) {
            self.model = model
            super.init()
        }

        func syncCornerMarkersIfNeeded() {
            guard model.cornerEpoch != lastCornerEpoch else { return }
            lastCornerEpoch = model.cornerEpoch
            cornerMarkers.forEach { $0.removeFromParent() }
            cornerMarkers.removeAll()
        }

        func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
            for case let plane as ARPlaneAnchor in anchors {
                upsert(plane)
            }
        }

        func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
            for case let plane as ARPlaneAnchor in anchors {
                upsert(plane)
            }
        }

        func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
            for case let plane as ARPlaneAnchor in anchors {
                Task { @MainActor in
                    model.removePlane(id: plane.identifier)
                    planeEntities[plane.identifier]?.removeFromParent()
                    planeEntities.removeValue(forKey: plane.identifier)
                }
            }
        }

        private func upsert(_ plane: ARPlaneAnchor) {
            let alignment: DetectedPlaneSnapshot.Alignment =
                plane.alignment == .vertical ? .vertical : .horizontal
            let center = SIMD3<Float>(
                plane.transform.columns.3.x,
                plane.transform.columns.3.y,
                plane.transform.columns.3.z
            )
            // Prefer planeExtent (iOS 16+) over deprecated `extent`.
            let extent = SIMD3<Float>(
                plane.planeExtent.width,
                0,
                plane.planeExtent.height
            )
            let snapshot = DetectedPlaneSnapshot(
                center: center,
                extent: extent,
                transform: plane.transform,
                alignment: alignment
            )
            Task { @MainActor in
                model.upsertPlane(snapshot, id: plane.identifier)
                updatePlaneVisual(plane: plane, extent: extent, alignment: alignment)
            }
        }

        private func updatePlaneVisual(
            plane: ARPlaneAnchor,
            extent: SIMD3<Float>,
            alignment: DetectedPlaneSnapshot.Alignment
        ) {
            guard let view = hostView else { return }
            if overlayRoot.scene == nil {
                view.scene.addAnchor(overlayRoot)
            }

            let w = max(extent.x, 0.05)
            let h = max(extent.z, 0.05)
            let color: UIColor = alignment == .horizontal
                ? .systemCyan.withAlphaComponent(0.28)
                : .systemPurple.withAlphaComponent(0.22)

            // Replace mesh by recreating the entity (avoids fragile ModelComponent mutation).
            planeEntities[plane.identifier]?.removeFromParent()
            let entity = ModelEntity(
                mesh: .generatePlane(width: w, depth: h),
                materials: [SimpleMaterial(color: color, isMetallic: false)]
            )
            entity.name = "scan_plane_\(plane.identifier.uuidString)"
            entity.transform = Transform(matrix: plane.transform)
            planeEntities[plane.identifier] = entity
            overlayRoot.addChild(entity)
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = hostView else { return }
            let loc = gesture.location(in: view)
            // Prefer horizontal plane hits so corners sit on the floor/table.
            let results = view.raycast(
                from: loc,
                allowing: .existingPlaneGeometry,
                alignment: .horizontal
            )
            guard let hit = results.first else {
                Task { @MainActor in
                    model.lastError = "Tap a detected floor or table plane to set a corner."
                }
                return
            }
            let p = hit.worldTransform.columns.3
            let point = SIMD3<Float>(p.x, p.y, p.z)
            Task { @MainActor in
                model.addCorner(point)
                addCornerMarker(at: point)
            }
        }

        private func addCornerMarker(at point: SIMD3<Float>) {
            guard let view = hostView else { return }
            if overlayRoot.scene == nil {
                view.scene.addAnchor(overlayRoot)
            }
            let marker = ModelEntity(
                mesh: .generateSphere(radius: 0.06),
                materials: [SimpleMaterial(color: .systemYellow, isMetallic: false)]
            )
            marker.position = point
            marker.name = "scan_corner_\(cornerMarkers.count)"
            overlayRoot.addChild(marker)
            cornerMarkers.append(marker)
        }
    }
}
#endif
