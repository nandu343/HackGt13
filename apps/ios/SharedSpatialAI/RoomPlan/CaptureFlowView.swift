import SwiftUI

struct CaptureFlowView: View {
    @Environment(SceneSyncStore.self) private var store
    @State private var showCapture = false
    @State private var lastExportSummary: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("RoomPlan") {
                    Text("Scan a room on a LiDAR device, normalize to Y-up meters (origin at floor center), then POST to the shared API so the web twin can load the same scene.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    #if targetEnvironment(simulator)
                    Label("Simulator: capture UI disabled — use demo export below.", systemImage: "iphone.slash")
                        .foregroundStyle(.orange)
                    #else
                    Button("Start RoomPlan capture") {
                        showCapture = true
                    }
                    .disabled(store.isBusy)
                    #endif

                    Button("Export demo room → POST /scene") {
                        Task {
                            await store.uploadScene(DemoSceneFactory.partyDemo(sceneId: store.sceneId))
                            lastExportSummary = store.statusMessage
                        }
                    }
                    .disabled(store.isBusy)
                }

                Section("Sync") {
                    LabeledContent("Scene ID", value: store.sceneId)
                    LabeledContent("API", value: APIConfig.baseURL.absoluteString)
                    LabeledContent("Status", value: store.statusMessage)
                    if let err = store.lastError {
                        Text(err).foregroundStyle(.red).font(.caption)
                    }
                    if let summary = lastExportSummary {
                        Text(summary).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Capture")
            .fullScreenCover(isPresented: $showCapture) {
                #if !targetEnvironment(simulator)
                RoomCaptureRepresentable(
                    onComplete: { captured in
                        showCapture = false
                        let scene = RoomPlanExporter.export(
                            captured: captured,
                            sceneId: store.sceneId
                        )
                        lastExportSummary = "Captured \(scene.objects.count) objects · bounds \(scene.bounds.width)×\(scene.bounds.length)×\(scene.bounds.height) m"
                        Task { await store.uploadScene(scene) }
                    },
                    onCancel: { showCapture = false }
                )
                .ignoresSafeArea()
                #else
                Text("RoomPlan requires a physical device")
                    .padding()
                #endif
            }
        }
    }
}
