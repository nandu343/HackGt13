import SwiftUI

@main
struct SharedSpatialAIApp: App {
    @State private var store = SceneSyncStore()

    var body: some Scene {
        WindowGroup {
            RootFlowView()
                .environment(store)
                .preferredColorScheme(.dark)
        }
    }
}

/// Scan room first → live camera AR (plan / invite / draw in space) on that map.
enum AppPhase: Equatable {
    case scan
    case arRoom
}

struct RootFlowView: View {
    @Environment(SceneSyncStore.self) private var store
    @State private var phase: AppPhase = .scan
    @State private var showPlanSheet = false
    @State private var showInviteSheet = false
    @State private var showSettings = false

    var body: some View {
        Group {
            switch phase {
            case .scan:
                CaptureFlowView(
                    onRoomReady: { openARRoom(showPlan: true) },
                    onOpenSettings: { showSettings = true }
                )
            case .arRoom:
                ARRoomView(
                    onRescan: {
                        phase = .scan
                        showPlanSheet = false
                    },
                    onPlan: { showPlanSheet = true },
                    onInvite: { showInviteSheet = true },
                    onSettings: { showSettings = true }
                )
            }
        }
        .sheet(isPresented: $showPlanSheet) {
            PlanRoomSheet()
        }
        .sheet(isPresented: $showInviteSheet) {
            InviteSheet()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    private func openARRoom(showPlan: Bool) {
        store.seedGhostStubsIfNeeded()
        phase = .arRoom
        if showPlan {
            // Slight delay so the AR room mounts before the plan sheet.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                showPlanSheet = true
            }
        }
    }
}

struct SettingsView: View {
    @Environment(SceneSyncStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var apiURLDraft = APIConfig.baseURL.absoluteString
    @State private var sceneIdDraft = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("API") {
                    TextField("Base URL", text: $apiURLDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("Scene ID", text: $sceneIdDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Save connection") {
                        APIConfig.setBaseURLString(apiURLDraft)
                        store.updateSceneId(sceneIdDraft.isEmpty ? APIConfig.defaultSceneId : sceneIdDraft)
                        store.statusMessage = "Saved API settings"
                    }
                    Text(
                        "Simulator can use http://127.0.0.1:8000. On a physical device, use your Mac’s LAN IP (e.g. http://192.168.1.20:8000) and run uvicorn with --host 0.0.0.0."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

                Section("Coordinates") {
                    Text("Y-up meters · origin at floor center · same schema as web twin (`packages/schema`).")
                        .font(.footnote)
                }

                Section("Sync with web") {
                    Button("GET /scene (refresh)") {
                        Task { await store.refresh(markAsRoomMap: true) }
                    }
                    if let scene = store.scene {
                        LabeledContent("Version", value: "\(scene.version)")
                        LabeledContent("Objects", value: "\(scene.objects.count)")
                    }
                    if let err = store.lastError {
                        Text(err).font(.caption).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                apiURLDraft = APIConfig.baseURL.absoluteString
                sceneIdDraft = store.sceneId
            }
        }
    }
}
