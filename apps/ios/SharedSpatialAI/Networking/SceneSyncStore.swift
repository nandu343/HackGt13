import Foundation
import Observation

/// Shared app state: current scene mirror + sync status for web twin demos.
@Observable
@MainActor
final class SceneSyncStore {
    var scene: SceneDTO?
    var statusMessage: String = "Scan a room to begin"
    var lastError: String?
    var isBusy = false
    /// True after a successful RoomPlan / demo export or an intentional "load existing" refresh.
    var hasRoomMap = false
    var selectedObjectId: String?
    /// Free-space drawing strokes (Y-up meters); synced via WS `draw_stroke`.
    var strokes: [DrawingStrokeDTO] = []
    /// Presence for ghost avatars (WS when connected; stubs offline).
    var presenceGhosts: [PresenceUserDTO] = []
    var wsConnected = false
    /// Active stroke color (hex) for Live AR draw mode.
    var drawColor: String = "#e2b45c"
    /// Cached GET /catalog for Place picker + AI “Open website”.
    var catalog: [CatalogItemDTO] = []
    /// Last AI layout preview (value picks / product URLs).
    var lastLayout: LayoutResponseDTO?
    /// Hint from Live AR: floor point in front of camera for catalog ADD_OBJECT.
    var placementHint: Vector3?

    private(set) var sceneId: String
    private let realtime = SceneWebSocket()

    init(sceneId: String? = nil) {
        self.sceneId = sceneId ?? APIConfig.sceneId
        realtime.onStrokesSnapshot = { [weak self] list in
            self?.strokes = list
        }
        realtime.onStroke = { [weak self] stroke in
            guard let self else { return }
            if !self.strokes.contains(where: { $0.strokeId == stroke.strokeId }) {
                self.strokes.append(stroke)
            }
        }
        realtime.onPresence = { [weak self] users in
            guard let self else { return }
            let remotes = users.filter { $0.userId != APIConfig.actorId }
            if !remotes.isEmpty {
                self.presenceGhosts = remotes
            }
        }
        realtime.onConnectionChange = { [weak self] ok in
            self?.wsConnected = ok
            if ok {
                self?.statusMessage = "Live AR channel connected"
            }
        }
    }

    var selectedObject: SceneObjectDTO? {
        guard let id = selectedObjectId, let scene else { return nil }
        return scene.objects.first { $0.id == id }
    }

    func catalogItem(productId: String) -> CatalogItemDTO? {
        catalog.first { $0.productId == productId }
    }

    func connectRealtime() {
        realtime.connect(sceneId: sceneId)
    }

    func disconnectRealtime() {
        realtime.disconnect()
    }

    func addStroke(points: [Vector3], color: String? = nil, width: Double = 0.025) {
        guard points.count >= 2 else { return }
        let stroke = DrawingStrokeDTO(
            strokeId: "stroke_\(UUID().uuidString.prefix(8))",
            sceneId: sceneId,
            actorId: APIConfig.actorId,
            color: color ?? drawColor,
            width: width,
            points: points,
            plane: .free,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
        // Optimistic local append first — ink already on screen from the draft entity.
        strokes.append(stroke)
        // Fire-and-forget WS (URLSession callback); never await network on the gesture path.
        realtime.sendStroke(stroke)
        statusMessage = "Sketch synced · \(strokes.count)"
    }

    func clearOwnStrokes() {
        strokes.removeAll { $0.actorId == APIConfig.actorId }
        realtime.sendClear(scope: "own")
        statusMessage = "Cleared your strokes"
    }

    func clearAllStrokes() {
        strokes = []
        realtime.sendClear(scope: "all")
        statusMessage = "Cleared all strokes"
    }

    func updateSceneId(_ next: String) {
        let trimmed = next.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        APIConfig.setSceneId(trimmed)
        sceneId = trimmed
        scene = nil
        hasRoomMap = false
        selectedObjectId = nil
        strokes = []
        lastLayout = nil
        realtime.disconnect()
        statusMessage = "Scene id set — scan or load"
        realtime.connect(sceneId: sceneId)
    }

    func refresh(markAsRoomMap: Bool = false) async {
        isBusy = true
        lastError = nil
        defer { isBusy = false }
        do {
            let fetched = try await APIClient.shared.fetchScene(sceneId: sceneId)
            scene = fetched
            if markAsRoomMap || hasRoomMap {
                hasRoomMap = true
            }
            statusMessage = "Synced v\(fetched.version) · \(fetched.objects.count) objects"
        } catch {
            lastError = error.localizedDescription
            statusMessage = "Fetch failed"
        }
    }

    func loadCatalogIfNeeded(force: Bool = false) async {
        if !force, !catalog.isEmpty { return }
        do {
            catalog = try await APIClient.shared.fetchCatalog()
            if lastError?.contains("Cannot reach API") == true {
                lastError = nil
            }
        } catch {
            lastError = error.localizedDescription
            statusMessage = "Catalog unavailable"
        }
    }

    /// Probe API from Settings — clear success / actionable failure.
    func testConnection() async -> Bool {
        isBusy = true
        lastError = nil
        defer { isBusy = false }
        do {
            try await APIClient.shared.healthPing()
            statusMessage = "API OK · \(APIConfig.baseURL.absoluteString)"
            connectRealtime()
            return true
        } catch {
            lastError = error.localizedDescription
            statusMessage = "API unreachable"
            wsConnected = false
            return false
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
            hasRoomMap = true
            selectedObjectId = nil
            statusMessage = "Room map synced · v\(stored.version)"
            connectRealtime()
        } catch {
            lastError = error.localizedDescription
            statusMessage = "Upload failed"
        }
    }

    func pushOps(_ operations: [SceneOperationDTO]) async {
        guard let current = scene else {
            lastError = "No scene loaded — scan or refresh first"
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
            if let id = selectedObjectId,
               result.scene.objects.first(where: { $0.id == id }) == nil {
                selectedObjectId = nil
            }
        } catch {
            lastError = error.localizedDescription
            statusMessage = "Ops failed"
            await refresh(markAsRoomMap: true)
        }
    }

    func moveSelected(dx: Double, dz: Double) async {
        guard let object = selectedObject else {
            lastError = "Select an object first"
            return
        }
        let next = Vector3(
            object.transform.position.x + dx,
            object.transform.position.y,
            object.transform.position.z + dz
        )
        await moveObject(id: object.id, to: next)
    }

    /// Absolute MOVE_OBJECT (floor-plane drag in Live AR / web twin).
    func moveObject(id: String, to position: Vector3) async {
        guard let scene else { return }
        guard let object = scene.objects.first(where: { $0.id == id }) else {
            lastError = "Object not found"
            return
        }
        guard object.type != "wall", object.movable != false else {
            lastError = "Walls stay fixed"
            return
        }
        await pushOps([.move(objectId: object.id, to: position)])
    }

    func removeSelected() async {
        guard let object = selectedObject else {
            lastError = "Select an object first"
            return
        }
        guard object.type != "wall", object.movable != false else {
            lastError = "Walls stay fixed"
            return
        }
        await pushOps([.delete(objectId: object.id)])
        selectedObjectId = nil
    }

    /// Place a catalog product via ADD_OBJECT at `position` (or placement hint / room default).
    func placeCatalogItem(_ item: CatalogItemDTO, at position: Vector3? = nil) async {
        guard let scene else {
            lastError = "No scene loaded"
            return
        }
        let id = "ar_\(item.productId)_\(UUID().uuidString.prefix(5))"
        let height = item.dimensions?.heightMeters ?? 0.5
        let y = height * 0.5
        let resolved: Vector3
        if let position {
            resolved = Vector3(position.x, y, position.z)
        } else if let hint = placementHint {
            resolved = Vector3(hint.x, y, hint.z)
        } else {
            resolved = Vector3(
                0.35,
                y,
                -min(1.1, scene.bounds.length * 0.28)
            )
        }
        let op = SceneOperationDTO.add(from: item, objectId: id, position: resolved)
        await pushOps([op])
        selectedObjectId = id
        statusMessage = "Placed \(item.name)"
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
            lastLayout = layout
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

    func createInviteLink() async -> String? {
        isBusy = true
        lastError = nil
        defer { isBusy = false }
        do {
            let invite = try await APIClient.shared.createInvite(
                sceneId: sceneId,
                label: "iOS friends"
            )
            guard let url = APIConfig.webJoinURL(sceneId: sceneId, inviteToken: invite.token) else {
                lastError = "Could not build join URL"
                return nil
            }
            statusMessage = "Invite ready"
            return url.absoluteString
        } catch {
            lastError = error.localizedDescription
            statusMessage = "Invite failed"
            return nil
        }
    }

    /// Seed translucent ghost stubs so Live AR shows collaboration placeholders offline.
    func seedGhostStubsIfNeeded() {
        guard presenceGhosts.isEmpty else { return }
        presenceGhosts = [
            PresenceUserDTO(
                userId: "stub_peer_a",
                displayName: "Alex",
                color: "#6eb4c8",
                selectedObjectId: nil,
                lastSeenAt: nil,
                voiceEnabled: true,
                voiceSpeaking: false,
                position: Vector3(-0.8, 0.9, 0.4),
                lookDirection: Vector3(0, 0, -1)
            ),
            PresenceUserDTO(
                userId: "stub_peer_b",
                displayName: "Sam",
                color: "#c9a66b",
                selectedObjectId: nil,
                lastSeenAt: nil,
                voiceEnabled: false,
                voiceSpeaking: true,
                position: Vector3(1.0, 0.9, -0.6),
                lookDirection: Vector3(-0.4, 0, 0.9)
            )
        ]
        if strokes.isEmpty {
            strokes = [
                DrawingStrokeDTO(
                    strokeId: "stub_stroke_1",
                    sceneId: sceneId,
                    actorId: "stub",
                    color: "#e2b45c",
                    width: 0.03,
                    points: [
                        Vector3(-0.4, 1.35, -0.2),
                        Vector3(-0.1, 1.55, 0.1),
                        Vector3(0.25, 1.4, 0.35),
                        Vector3(0.55, 1.6, 0.15)
                    ],
                    plane: .free,
                    createdAt: nil
                )
            ]
        }
    }
}
