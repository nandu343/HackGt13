import Foundation
import Observation

/// Shared app state: current scene mirror + sync status for web twin demos.
@Observable
@MainActor
final class SceneSyncStore {
    var scene: SceneDTO?
    var statusMessage: String = "Idle"
    var lastError: String?
    var isBusy = false

    let sceneId: String

    init(sceneId: String = APIConfig.defaultSceneId) {
        self.sceneId = sceneId
    }

    func refresh() async {
        isBusy = true
        lastError = nil
        defer { isBusy = false }
        do {
            let fetched = try await APIClient.shared.fetchScene(sceneId: sceneId)
            scene = fetched
            statusMessage = "Synced v\(fetched.version) · \(fetched.objects.count) objects"
        } catch {
            lastError = error.localizedDescription
            statusMessage = "Fetch failed"
        }
    }

    func uploadScene(_ next: SceneDTO) async {
        isBusy = true
        lastError = nil
        defer { isBusy = false }
        do {
            var payload = next
            payload.sceneId = sceneId
            let stored = try await APIClient.shared.postScene(payload)
            scene = stored
            statusMessage = "Uploaded RoomPlan → API v\(stored.version)"
        } catch {
            lastError = error.localizedDescription
            statusMessage = "Upload failed"
        }
    }

    func pushOps(_ operations: [SceneOperationDTO]) async {
        guard let current = scene else {
            lastError = "No scene loaded — refresh first"
            return
        }
        isBusy = true
        lastError = nil
        defer { isBusy = false }
        do {
            let result = try await APIClient.shared.applyOperations(
                sceneId: current.sceneId,
                baseVersion: current.version,
                operations: operations
            )
            scene = result.scene
            statusMessage = "Applied \(result.applied) op(s) → v\(result.version)"
        } catch {
            lastError = error.localizedDescription
            statusMessage = "Ops failed"
            // Re-fetch on conflict so UI can catch up with web twin.
            await refresh()
        }
    }

    /// Call hybrid `/ai/layout` then apply returned ops into the shared scene (AR / web twin).
    @discardableResult
    func planAndApply(
        prompt: String,
        guestCount: Int,
        budget: Double
    ) async -> LayoutResponseDTO? {
        guard scene != nil else {
            lastError = "No scene loaded — export or refresh first"
            return nil
        }
        lastError = nil
        isBusy = true
        let layout: LayoutResponseDTO
        do {
            layout = try await APIClient.shared.postAiLayout(
                LayoutRequestDTO(
                    sceneId: sceneId,
                    prompt: prompt,
                    guestCount: guestCount,
                    budget: budget
                )
            )
            statusMessage = "AI \(layout.plannerMode ?? "rules"): \(layout.scenario) · \(layout.operations.count) ops"
        } catch {
            lastError = error.localizedDescription
            statusMessage = "AI layout failed"
            isBusy = false
            return nil
        }
        isBusy = false
        guard !layout.operations.isEmpty else {
            lastError = "No valid ops — try a different prompt"
            return layout
        }
        await pushOps(layout.operations)
        return layout
    }
}
