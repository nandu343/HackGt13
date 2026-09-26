import SwiftUI

@main
struct SharedSpatialAIApp: App {
    @State private var store = SceneSyncStore()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(store)
                .preferredColorScheme(.dark)
        }
    }
}

struct RootTabView: View {
    var body: some View {
        TabView {
            CaptureFlowView()
                .tabItem { Label("Capture", systemImage: "camera.viewfinder") }

            SceneViewerView()
                .tabItem { Label("Viewer", systemImage: "cube.transparent") }

            AROverlayView()
                .tabItem { Label("AR", systemImage: "arkit") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

struct SettingsView: View {
    @Environment(SceneSyncStore.self) private var store

    var body: some View {
        NavigationStack {
            Form {
                Section("API") {
                    LabeledContent("Base URL", value: APIConfig.baseURL.absoluteString)
                    LabeledContent("Scene ID", value: store.sceneId)
                    Text("On a physical device, set `APIConfig.baseURL` (or env `SHARED_SPATIAL_API_URL`) to your Mac’s LAN IP, e.g. http://192.168.1.20:8000. Allow local networking / ATS exceptions are already configured for HTTP demos.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Coordinates") {
                    Text("Y-up meters · origin at floor center · same schema as web twin (`packages/schema`).")
                        .font(.footnote)
                }

                Section("Sync with web") {
                    Button("GET /scene (refresh)") {
                        Task { await store.refresh() }
                    }
                    if let scene = store.scene {
                        LabeledContent("Version", value: "\(scene.version)")
                        LabeledContent("Objects", value: "\(scene.objects.count)")
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}
