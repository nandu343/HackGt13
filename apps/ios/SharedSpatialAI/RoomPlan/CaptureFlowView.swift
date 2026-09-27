import RoomPlan
import SwiftUI

#if !targetEnvironment(simulator)
import ARKit
#endif

/// Feature flags for scan paths. RoomPlan / LiDAR is optional — never a hard blocker.
enum ScanCapabilities {
    /// True when RoomPlan capture is available (typically LiDAR devices).
    static var supportsDetailedRoomPlan: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return RoomCaptureSession.isSupported
        #endif
    }

    /// Any physical device with ARKit world tracking can do camera plane scan + Live AR.
    static var supportsCameraScan: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return ARWorldTrackingConfiguration.isSupported
        #endif
    }
}

/// Launch gate: scan the room (camera primary, RoomPlan optional) or demo before planning in AR.
struct CaptureFlowView: View {
    @Environment(SceneSyncStore.self) private var store
    var onRoomReady: () -> Void
    var onOpenSettings: () -> Void

    @State private var showCameraScan = false
    @State private var showRoomPlan = false
    @State private var lastExportSummary: String?

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.05, green: 0.07, blue: 0.09),
                        Color(red: 0.08, green: 0.12, blue: 0.14),
                        Color(red: 0.06, green: 0.09, blue: 0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer(minLength: 24)

                    VStack(spacing: 14) {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 56, weight: .light))
                            .foregroundStyle(.cyan.opacity(0.9))
                        Text("Shared Spatial")
                            .font(.largeTitle.weight(.semibold))
                        Text("Scan the room first.\nThen plan and collaborate in AR on that map.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)
                    }

                    Spacer(minLength: 32)

                    VStack(spacing: 12) {
                        #if targetEnvironment(simulator)
                        Button {
                            Task { await exportDemo() }
                        } label: {
                            labelRow(
                                title: store.isBusy ? "Syncing…" : "Use demo room",
                                subtitle: "Simulator export → POST /scene",
                                systemImage: "square.and.arrow.up.on.square"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(store.isBusy)
                        #else
                        if ScanCapabilities.supportsCameraScan {
                            Button {
                                showCameraScan = true
                            } label: {
                                labelRow(
                                    title: "Scan with camera",
                                    subtitle: "ARKit planes · works without LiDAR",
                                    systemImage: "camera.viewfinder"
                                )
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(store.isBusy)
                        }

                        if ScanCapabilities.supportsDetailedRoomPlan {
                            Button {
                                showRoomPlan = true
                            } label: {
                                labelRow(
                                    title: "Detailed scan (LiDAR)",
                                    subtitle: "RoomPlan · richer walls & furniture",
                                    systemImage: "cube.transparent"
                                )
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .disabled(store.isBusy)
                        }

                        Button {
                            Task { await exportDemo() }
                        } label: {
                            Text("Use demo room instead")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(store.isBusy)
                        #endif

                        Button {
                            Task { await loadExisting() }
                        } label: {
                            Text("Load existing map from API")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(store.isBusy)
                    }
                    .padding(.horizontal, 24)

                    VStack(alignment: .leading, spacing: 6) {
                        statusBlock
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .padding(.bottom, 8)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onOpenSettings()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .fullScreenCover(isPresented: $showCameraScan) {
                #if !targetEnvironment(simulator)
                CameraRoomScanView(
                    sceneId: store.sceneId,
                    onComplete: { scene in
                        showCameraScan = false
                        applyExportedScene(scene, label: "Camera scan")
                    },
                    onCancel: { showCameraScan = false }
                )
                .ignoresSafeArea()
                #else
                Text("Camera scan requires a physical device")
                    .padding()
                #endif
            }
            .fullScreenCover(isPresented: $showRoomPlan) {
                #if !targetEnvironment(simulator)
                if ScanCapabilities.supportsDetailedRoomPlan {
                    RoomCaptureRepresentable(
                        onComplete: { captured in
                            showRoomPlan = false
                            let scene = RoomPlanExporter.export(
                                captured: captured,
                                sceneId: store.sceneId
                            )
                            applyExportedScene(scene, label: "RoomPlan")
                        },
                        onCancel: { showRoomPlan = false }
                    )
                    .ignoresSafeArea()
                } else {
                    VStack(spacing: 12) {
                        Text("Detailed scan needs LiDAR")
                            .font(.headline)
                        Text("Use Scan with camera instead — Live AR works without LiDAR.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Close") { showRoomPlan = false }
                    }
                    .padding()
                }
                #else
                Text("RoomPlan requires a physical device")
                    .padding()
                #endif
            }
        }
    }

    private var statusBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            if store.isBusy {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Talking to API…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text(store.statusMessage)
                .font(.caption)
            Text("Scene \(store.sceneId) · \(APIConfig.baseURL.absoluteString)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if let summary = lastExportSummary {
                Text(summary).font(.caption2).foregroundStyle(.secondary)
            }
            if let err = store.lastError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
            if store.scene == nil && store.lastError == nil {
                Text("No room map yet — scan with camera, use demo, or load from API.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func labelRow(title: String, subtitle: String, systemImage: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).opacity(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } icon: {
            Image(systemName: systemImage)
        }
        .padding(.vertical, 4)
    }

    private func applyExportedScene(_ scene: SceneDTO, label: String) {
        lastExportSummary =
            "\(label): \(scene.objects.count) objects · "
            + String(
                format: "%.1f×%.1f×%.1f m",
                scene.bounds.width,
                scene.bounds.length,
                scene.bounds.height
            )
        Task {
            await store.uploadScene(scene)
            if store.lastError == nil {
                onRoomReady()
            }
        }
    }

    private func exportDemo() async {
        await store.uploadScene(DemoSceneFactory.partyDemo(sceneId: store.sceneId))
        lastExportSummary = store.statusMessage
        if store.lastError == nil {
            onRoomReady()
        }
    }

    private func loadExisting() async {
        await store.refresh(markAsRoomMap: true)
        if store.scene != nil, store.lastError == nil {
            onRoomReady()
        }
    }
}
