import ARKit
import RealityKit
import SwiftUI
import UIKit

/// AR overlay stub: place/move catalog anchors and push ops to the shared API
/// (same `POST /scene/{id}/operations` path as the web twin).
struct AROverlayView: View {
    @Environment(SceneSyncStore.self) private var store
    @State private var session = AROverlaySession()
    @State private var placedCount = 0

    var body: some View {
        NavigationStack {
            ZStack {
                #if targetEnvironment(simulator)
                ContentUnavailableView(
                    "AR requires a device",
                    systemImage: "arkit",
                    description: Text(
                        "On a physical iPhone/iPad this tab hosts an ARView. From Simulator, use the buttons below to push sample ops against the API."
                    )
                )
                #else
                ARViewContainer(session: session)
                    .ignoresSafeArea()
                #endif

                VStack {
                    Spacer()
                    controlBar
                }
            }
            .navigationTitle("AR Overlay")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await store.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .task {
                if store.scene == nil {
                    await store.refresh()
                }
            }
        }
    }

    private var controlBar: some View {
        VStack(spacing: 10) {
            Text(store.statusMessage)
                .font(.caption)
                .frame(maxWidth: .infinity)
            if let err = store.lastError {
                Text(err).font(.caption2).foregroundStyle(.red)
            }

            HStack(spacing: 12) {
                Button("Place chair") {
                    Task { await placeChair() }
                }
                .buttonStyle(.borderedProminent)

                Button("Nudge +X") {
                    Task { await nudgeSelected(dx: 0.25, dz: 0) }
                }
                .buttonStyle(.bordered)

                Button("Nudge −Z") {
                    Task { await nudgeSelected(dx: 0, dz: -0.25) }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    private func placeChair() async {
        placedCount += 1
        let id = "ar_anchor_\(placedCount)"
        let position = Vector3(0.5 * Double(placedCount % 3), 0.43, -0.8)
        session.placeBox(id: id, at: position)

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
    }

    private func nudgeSelected(dx: Double, dz: Double) async {
        guard let scene = store.scene else { return }
        let target =
            scene.objects.last(where: { $0.id.hasPrefix("ar_anchor_") })
            ?? scene.objects.first(where: { $0.movable != false && $0.type != "wall" })
        guard let object = target else {
            store.lastError = "No movable object to nudge"
            return
        }
        let next = Vector3(
            object.transform.position.x + dx,
            object.transform.position.y,
            object.transform.position.z + dz
        )
        session.moveBox(id: object.id, to: next)
        let op = SceneOperationDTO(
            type: .moveObject,
            objectId: object.id,
            targetPosition: next,
            targetRotation: nil,
            assetId: nil,
            productId: nil,
            objectType: nil,
            dimensions: nil,
            movable: nil,
            source: nil
        )
        await store.pushOps([op])
    }
}

@Observable
final class AROverlaySession {
    weak var arView: ARView?
    private var anchors: [String: AnchorEntity] = [:]

    func placeBox(id: String, at position: Vector3) {
        guard let arView else { return }
        let mesh = MeshResource.generateBox(width: 0.48, height: 0.86, depth: 0.52)
        let material = SimpleMaterial(color: .systemOrange, isMetallic: false)
        let model = ModelEntity(mesh: mesh, materials: [material])
        model.name = id
        let anchor = AnchorEntity(world: Coordinates.toSIMD(position))
        anchor.addChild(model)
        arView.scene.addAnchor(anchor)
        anchors[id] = anchor
    }

    func moveBox(id: String, to position: Vector3) {
        anchors[id]?.position = Coordinates.toSIMD(position)
    }
}

#if !targetEnvironment(simulator)
struct ARViewContainer: UIViewRepresentable {
    var session: AROverlaySession

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero)
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        view.session.run(config)
        session.arView = view
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}
#endif
