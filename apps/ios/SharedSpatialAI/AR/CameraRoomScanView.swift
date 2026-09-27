import ARKit
import RealityKit
import SwiftUI
import UIKit
import simd

#if !targetEnvironment(simulator)
/// Automatic camera room setup: walk around; floors/walls appear; finishes when coverage is stable.
struct CameraRoomScanView: View {
    var sceneId: String
    var onComplete: (SceneDTO) -> Void
    var onCancel: () -> Void

    @StateObject private var model = CameraRoomScanModel()

    var body: some View {
        ZStack {
            CameraRoomScanRepresentable(model: model)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topHUD
                Spacer()
                bottomBar
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: model.shouldAutoFinish) { _, ready in
            if ready { finish() }
        }
    }

    private var topHUD: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.statusTitle)
                .font(.title3.weight(.semibold))
            Text(model.statusDetail)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ProgressView(value: model.coverage)
                .tint(.cyan)
            HStack {
                Text("Coverage")
                Spacer()
                Text("\(Int(model.coverage * 100))%")
                    .monospacedDigit()
            }
            .font(.caption2)
            .foregroundStyle(.cyan)

            HStack(spacing: 14) {
                Label("\(model.horizontalCount) floor", systemImage: "square.dashed")
                Label("\(model.verticalCount) wall", systemImage: "rectangle.split.3x1")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            if model.isStabilizing {
                Text("Hold still — finishing…")
                    .font(.caption)
                    .foregroundStyle(.cyan)
            }
            if let err = model.lastError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 12) {
                Button("Cancel") { onCancel() }
                    .buttonStyle(.bordered)
                Button(model.canFinish ? "Finish" : "Keep scanning…") { finish() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canFinish)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }

    private func finish() {
        guard !model.didFinish else { return }
        model.didFinish = true
        onComplete(model.buildScene(sceneId: sceneId))
    }
}

@MainActor
final class CameraRoomScanModel: ObservableObject {
    @Published var horizontalCount = 0
    @Published var verticalCount = 0
    @Published var coverage: Double = 0
    @Published var statusTitle = "Walk around the room"
    @Published var statusDetail = "Point at floors and walls — setup is automatic."
    @Published var lastError: String?
    @Published var shouldAutoFinish = false
    @Published var isStabilizing = false
    @Published var didFinish = false

    private(set) var planes: [UUID: DetectedPlaneSnapshot] = [:]

    /// Floor area (m²) + wall span used for coverage.
    private var lastBoundsSignature: String = ""
    private var stableSince: Date?
    private let minFloorArea: Float = 2.5
    private let minWalls = 1
    private let coverageReady: Double = 0.72
    private let stableSeconds: TimeInterval = 1.6

    var canFinish: Bool {
        horizontalCount >= 1 && (coverage >= 0.45 || !planes.isEmpty)
    }

    func upsertPlane(_ snapshot: DetectedPlaneSnapshot, id: UUID) {
        planes[id] = snapshot
        refreshProgress()
    }

    func removePlane(id: UUID) {
        planes.removeValue(forKey: id)
        refreshProgress()
    }

    func buildScene(sceneId: String) -> SceneDTO {
        CameraScanExporter.export(
            sceneId: sceneId,
            planes: Array(planes.values),
            cornerPoints: []
        )
    }

    private func refreshProgress() {
        let floors = planes.values.filter { $0.alignment == .horizontal }
        let walls = planes.values.filter { $0.alignment == .vertical }
        horizontalCount = floors.count
        verticalCount = walls.count

        let floorArea = floors.reduce(Float(0)) { $0 + $1.extent.x * $1.extent.z }
        let wallSpan = walls.reduce(Float(0)) { $0 + $1.extent.x }

        let areaScore = min(1.0, Double(floorArea / max(minFloorArea, 0.1)))
        let wallScore = min(1.0, Double(walls.count) / Double(max(minWalls, 1)) * 0.35
            + min(1.0, Double(wallSpan / 4.0)) * 0.65)
        // Floor dominates; walls unlock the last ~30%.
        coverage = min(1.0, areaScore * 0.7 + wallScore * 0.3)

        let sig = boundsSignature()
        if coverage >= coverageReady && horizontalCount >= 1 {
            if sig == lastBoundsSignature {
                if stableSince == nil { stableSince = Date() }
                let held = Date().timeIntervalSince(stableSince ?? Date())
                isStabilizing = held > 0.4
                if held >= stableSeconds, !didFinish {
                    statusTitle = "Room ready"
                    statusDetail = "Finishing automatically…"
                    shouldAutoFinish = true
                } else {
                    statusTitle = "Looking good"
                    statusDetail = "Hold still a moment while bounds settle."
                }
            } else {
                lastBoundsSignature = sig
                stableSince = Date()
                isStabilizing = false
                statusTitle = "Keep moving…"
                statusDetail = "Coverage is high — slow walk to confirm edges."
            }
        } else if horizontalCount == 0 {
            stableSince = nil
            isStabilizing = false
            statusTitle = "Find the floor"
            statusDetail = "Tilt the phone down and walk slowly."
        } else if coverage < 0.4 {
            stableSince = nil
            isStabilizing = false
            statusTitle = "Keep moving…"
            statusDetail = "Sweep left and right so more floor appears."
        } else {
            stableSince = nil
            isStabilizing = false
            statusTitle = "Almost there"
            statusDetail = walls.isEmpty
                ? "Turn toward a wall so the room bounds lock in."
                : "A bit more floor coverage, then we’ll finish."
        }
    }

    private func boundsSignature() -> String {
        let pts = planes.values.flatMap { plane -> [SIMD3<Float>] in
            let hx = plane.extent.x * 0.5
            let hz = plane.extent.z * 0.5
            let locals: [SIMD3<Float>] = [
                SIMD3(-hx, 0, -hz), SIMD3(hx, 0, -hz),
                SIMD3(hx, 0, hz), SIMD3(-hx, 0, hz)
            ]
            return locals.map { local in
                let c = plane.transform * SIMD4<Float>(local.x, local.y, local.z, 1)
                return SIMD3(c.x, c.y, c.z)
            }
        }
        guard let first = pts.first else { return "empty" }
        var minX = first.x, maxX = first.x, minZ = first.z, maxZ = first.z
        for p in pts.dropFirst() {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minZ = min(minZ, p.z); maxZ = max(maxZ, p.z)
        }
        // Quantize so tiny plane jitter doesn't reset stability.
        let qx = Int((maxX - minX) * 5)
        let qz = Int((maxZ - minZ) * 5)
        return "\(qx)x\(qz)_\(horizontalCount)_\(verticalCount)"
    }
}

struct CameraRoomScanRepresentable: UIViewRepresentable {
    @ObservedObject var model: CameraRoomScanModel

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero)
        view.automaticallyConfigureSession = false

        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        view.session.delegate = context.coordinator
        view.session.run(config, options: [.resetTracking, .removeExistingAnchors])

        context.coordinator.hostView = view
        context.coordinator.model = model
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.model = model
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    @MainActor
    final class Coordinator: NSObject, ARSessionDelegate {
        var model: CameraRoomScanModel
        weak var hostView: ARView?
        private var planeEntities: [UUID: ModelEntity] = [:]
        private let overlayRoot = AnchorEntity(world: .zero)

        init(model: CameraRoomScanModel) {
            self.model = model
            super.init()
        }

        nonisolated func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
            let updates = CameraScanPlaneUpdate.makeList(from: anchors)
            Task { @MainActor [weak self] in
                guard let self else { return }
                for update in updates { self.upsert(update) }
            }
        }

        nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
            let updates = CameraScanPlaneUpdate.makeList(from: anchors)
            Task { @MainActor [weak self] in
                guard let self else { return }
                for update in updates { self.upsert(update) }
            }
        }

        nonisolated func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
            let ids = anchors.compactMap { ($0 as? ARPlaneAnchor)?.identifier }
            Task { @MainActor [weak self] in
                guard let self else { return }
                for id in ids {
                    self.model.removePlane(id: id)
                    self.planeEntities[id]?.removeFromParent()
                    self.planeEntities.removeValue(forKey: id)
                }
            }
        }

        private func upsert(_ plane: CameraScanPlaneUpdate) {
            let snapshot = DetectedPlaneSnapshot(
                center: plane.center,
                extent: plane.extent,
                transform: plane.transform,
                alignment: plane.alignment
            )
            model.upsertPlane(snapshot, id: plane.id)
            updatePlaneVisual(
                id: plane.id,
                transform: plane.transform,
                extent: plane.extent,
                alignment: plane.alignment
            )
        }

        private func updatePlaneVisual(
            id: UUID,
            transform: simd_float4x4,
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
                : .systemTeal.withAlphaComponent(0.20)

            planeEntities[id]?.removeFromParent()
            let entity = ModelEntity(
                mesh: .generatePlane(width: w, depth: h),
                materials: [SimpleMaterial(color: color, isMetallic: false)]
            )
            entity.name = "scan_plane_\(id.uuidString)"
            entity.transform = Transform(matrix: transform)
            planeEntities[id] = entity
            overlayRoot.addChild(entity)
        }
    }
}

private struct CameraScanPlaneUpdate: Sendable {
    let id: UUID
    let center: SIMD3<Float>
    let extent: SIMD3<Float>
    let transform: simd_float4x4
    let alignment: DetectedPlaneSnapshot.Alignment

    static func makeList(from anchors: [ARAnchor]) -> [CameraScanPlaneUpdate] {
        anchors.compactMap { anchor -> CameraScanPlaneUpdate? in
            guard let plane = anchor as? ARPlaneAnchor else { return nil }
            let transform = plane.transform
            let alignment: DetectedPlaneSnapshot.Alignment =
                plane.alignment == .vertical ? .vertical : .horizontal
            return CameraScanPlaneUpdate(
                id: plane.identifier,
                center: SIMD3(
                    transform.columns.3.x,
                    transform.columns.3.y,
                    transform.columns.3.z
                ),
                extent: SIMD3(plane.planeExtent.width, Float(0), plane.planeExtent.height),
                transform: transform,
                alignment: alignment
            )
        }
    }
}
#endif
