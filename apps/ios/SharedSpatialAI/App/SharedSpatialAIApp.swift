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
                .transition(.opacity.combined(with: .move(edge: .leading)))
            case .arRoom:
                ARRoomView(
                    onRescan: {
                        withAnimation(.easeInOut(duration: 0.28)) {
                            phase = .scan
                            showPlanSheet = false
                        }
                    },
                    onPlan: { showPlanSheet = true },
                    onInvite: { showInviteSheet = true },
                    onSettings: { showSettings = true }
                )
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .animation(.easeInOut(duration: 0.28), value: phase)
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
        withAnimation(.easeInOut(duration: 0.28)) {
            phase = .arRoom
        }
        if showPlan {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
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
    @State private var testResult: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Status") {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(store.wsConnected ? Color.green : Color.orange)
                                .frame(width: 7, height: 7)
                            Text(store.wsConnected ? "Live channel" : "Not connected")
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let testResult {
                        Text(testResult)
                            .font(.caption)
                            .foregroundStyle(testResult.contains("OK") ? .green : .secondary)
                    }
                }

                Section {
                    TextField("Base URL", text: $apiURLDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .font(.body.monospaced())
                    TextField("Scene ID", text: $sceneIdDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                    Button("Save connection") {
                        APIConfig.setBaseURLString(apiURLDraft)
                        store.updateSceneId(sceneIdDraft.isEmpty ? APIConfig.defaultSceneId : sceneIdDraft)
                        apiURLDraft = APIConfig.baseURL.absoluteString
                        store.statusMessage = "Saved · \(APIConfig.baseURL.absoluteString)"
                        store.connectRealtime()
                        testResult = nil
                    }
                    .fontWeight(.semibold)
                    Button {
                        Task {
                            APIConfig.setBaseURLString(apiURLDraft)
                            let ok = await store.testConnection()
                            testResult = ok
                                ? "OK · \(APIConfig.baseURL.absoluteString)"
                                : (store.lastError ?? "Failed")
                            if ok {
                                await store.loadCatalogIfNeeded(force: true)
                            }
                        }
                    } label: {
                        Label(
                            store.isBusy ? "Testing…" : "Test connection",
                            systemImage: "antenna.radiowaves.left.and.right"
                        )
                    }
                    .disabled(store.isBusy)
                } header: {
                    Text("API")
                } footer: {
                    Text(
                        "Simulator: http://127.0.0.1:8000 · Device: http://<Mac-LAN-IP>:8000 "
                            + "(API must bind 0.0.0.0). Saved URL sticks across launches."
                    )
                }

                Section("Scene") {
                    Button {
                        Task { await store.refresh(markAsRoomMap: true) }
                    } label: {
                        Label("Refresh from API", systemImage: "arrow.clockwise")
                    }
                    Button {
                        Task { await store.loadCatalogIfNeeded(force: true) }
                    } label: {
                        Label(
                            store.catalog.isEmpty
                                ? "Load catalog"
                                : "Reload catalog (\(store.catalog.count))",
                            systemImage: "shippingbox"
                        )
                    }
                    if let scene = store.scene {
                        LabeledContent("Version", value: "\(scene.version)")
                        LabeledContent("Objects", value: "\(scene.objects.count)")
                        LabeledContent("Strokes", value: "\(store.strokes.count)")
                    }
                    if let err = store.lastError {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                }

                Section("Coordinates") {
                    Text("Y-up meters · origin at floor center · same schema as the web twin.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(red: 0.06, green: 0.07, blue: 0.09))
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                apiURLDraft = APIConfig.baseURL.absoluteString
                sceneIdDraft = store.sceneId
            }
        }
        .preferredColorScheme(.dark)
    }
}
