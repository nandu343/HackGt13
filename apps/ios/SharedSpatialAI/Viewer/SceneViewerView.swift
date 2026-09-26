import RealityKit
import SwiftUI
import UIKit

/// Non-AR RealityKit view that renders the shared scene graph (Y-up meters).
struct SceneRealityView: UIViewRepresentable {
    let scene: SceneDTO?

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.environment.background = .color(.black)
        context.coordinator.root = AnchorEntity(world: .zero)
        if let root = context.coordinator.root {
            view.scene.addAnchor(root)
        }
        rebuild(in: view, coordinator: context.coordinator, scene: scene)
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        rebuild(in: uiView, coordinator: context.coordinator, scene: scene)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var root: AnchorEntity?
        var renderedVersion: Int = -1
        var renderedObjectCount: Int = -1
    }

    private func rebuild(in view: ARView, coordinator: Coordinator, scene: SceneDTO?) {
        guard let root = coordinator.root else { return }
        let version = scene?.version ?? -1
        let count = scene?.objects.count ?? -1
        if version == coordinator.renderedVersion && count == coordinator.renderedObjectCount {
            return
        }
        coordinator.renderedVersion = version
        coordinator.renderedObjectCount = count

        root.children.forEach { $0.removeFromParent() }

        guard let scene else {
            let placeholder = ModelEntity(
                mesh: .generateBox(size: 0.4),
                materials: [SimpleMaterial(color: .gray, isMetallic: false)]
            )
            root.addChild(placeholder)
            return
        }

        let floor = ModelEntity(
            mesh: .generatePlane(
                width: Float(scene.bounds.width),
                depth: Float(scene.bounds.length)
            ),
            materials: [SimpleMaterial(color: UIColor(white: 0.18, alpha: 1), isMetallic: false)]
        )
        floor.name = "floor"
        root.addChild(floor)

        for object in scene.objects {
            root.addChild(makeEntity(for: object))
        }

        // Frame the room for the non-AR camera (look roughly toward origin).
        var cam = Transform()
        cam.translation = SIMD3(
            Float(scene.bounds.width) * 0.55,
            Float(scene.bounds.height) * 0.85,
            Float(scene.bounds.length) * 1.15
        )
        cam.rotation = simd_quatf(angle: -0.5, axis: SIMD3(1, 0, 0))
            * simd_quatf(angle: 0.4, axis: SIMD3(0, 1, 0))
        view.cameraTransform = cam
    }

    private func makeEntity(for object: SceneObjectDTO) -> ModelEntity {
        let w = Float(object.dimensions?.width ?? 0.5)
        let h = Float(object.dimensions?.height ?? 0.5)
        let d = Float(object.dimensions?.depth ?? 0.5)

        let color: UIColor = {
            switch object.type {
            case "wall": return UIColor(white: 0.55, alpha: 1)
            case "sofa": return .systemTeal
            case "table": return .systemBrown
            case "chair": return .systemOrange
            case "floor_lamp", "lamp": return .systemYellow
            default: return .systemIndigo
            }
        }()

        let mesh: MeshResource =
            object.type == "wall"
            ? .generateBox(width: w, height: h, depth: max(d, 0.08))
            : .generateBox(width: w, height: h, depth: d)

        let entity = ModelEntity(
            mesh: mesh,
            materials: [SimpleMaterial(color: color, isMetallic: false)]
        )
        entity.name = object.id
        entity.position = Coordinates.toSIMD(object.transform.position)
        entity.orientation = Coordinates.toSIMDQuat(object.transform.rotation)
        return entity
    }
}

struct SceneViewerView: View {
    @Environment(SceneSyncStore.self) private var store

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SceneRealityView(scene: store.scene)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)

                VStack(alignment: .leading, spacing: 6) {
                    Text(store.statusMessage)
                        .font(.caption)
                    if let scene = store.scene {
                        Text(
                            "v\(scene.version) · \(scene.objects.count) objects · "
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
                    if let err = store.lastError {
                        Text(err).font(.caption2).foregroundStyle(.red)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.ultraThinMaterial)
            }
            .navigationTitle("Viewer")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await store.refresh() }
                    } label: {
                        if store.isBusy {
                            ProgressView()
                        } else {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
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
}
