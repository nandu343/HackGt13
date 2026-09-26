# Shared Spatial AI — iOS (RoomPlan / AR scaffold)

Working scaffold that proves **one scene graph, two renderers**: this app and the web twin both talk to the same FastAPI scene API.

Not App Store polish — enough for judges to open in Xcode, sync with the web twin, and (on device) capture a room.

## Open in Xcode

1. On a Mac with **Xcode 15+** (iOS 17 SDK):
   ```bash
   open apps/ios/SharedSpatialAI.xcodeproj
   ```
2. Select the **SharedSpatialAI** target → **Signing & Capabilities** → choose your Team (required for device).
3. Pick a run destination:
   - **iOS Simulator** — Viewer + API sync + demo RoomPlan export (no live scan / no AR camera).
   - **Physical iPhone/iPad with LiDAR** — full RoomPlan capture + AR overlay.

### If the `.xcodeproj` fails to open

Create a new **iOS App** (SwiftUI, iOS 17+) named `SharedSpatialAI`, then drag the `SharedSpatialAI/` source folder into the project (check “Copy items if needed” off; add to target). Link frameworks: **RoomPlan**, **RealityKit**, **ARKit**. Point Info to `SharedSpatialAI/Resources/Info.plist`.

Optional: regenerate with [XcodeGen](https://github.com/yonaskolb/XcodeGen) from `project.yml`:

```bash
cd apps/ios && xcodegen generate && open SharedSpatialAI.xcodeproj
```

## Run the backend first

From the repo root (same API the web twin uses):

```bash
py -3.12 -m uvicorn app.main:app --reload --host 0.0.0.0 --port 8000 --app-dir apps/api
```

`--host 0.0.0.0` is required so a **physical device** can reach your Mac.

Default scene id: `scene_party_001`.

## Configure API URL

Edit `SharedSpatialAI/Networking/APIConfig.swift`:

| Destination | Base URL |
|-------------|----------|
| Simulator | `http://127.0.0.1:8000` (default) |
| Device on LAN | `http://<your-mac-lan-ip>:8000` |

Or set scheme environment variable `SHARED_SPATIAL_API_URL`.

`Info.plist` allows local HTTP (`NSAllowsLocalNetworking` + ATS exception for demos).

## Tabs

| Tab | Role |
|-----|------|
| **Capture** | RoomPlan scan → normalize → `POST /scene`. Simulator: “Export demo room”. After export/scan, **Plan this room** sheet opens (or use the button). |
| **Viewer** | RealityKit (non-AR) pull of `GET /scene/{id}`; refresh after web edits. |
| **AR** | Overlay stub: place/nudge anchors → `POST /scene/{id}/operations`. Device-only camera. |
| **Settings** | API URL / scene id / coordinate notes. |

### Plan this room (post-scan intent)

1. Export demo room (or finish RoomPlan) → sheet asks what to make the space into (party / study / dinner / movie / custom).
2. **Get AI recommendations** → `POST /ai/layout` (same hybrid planner as web; Grok when `XAI_API_KEY` is set).
3. Review reasoning + ops → **Accept into scene** → `POST /scene/{id}/operations`.
4. Refresh **Viewer** / **AR** (and the web twin) to see placed objects in the shared Y-up frame.

---

## Sync loop with the web twin

```text
iOS RoomPlan / demo export ──POST /scene──► FastAPI SceneStore
iOS Plan sheet ──POST /ai/layout──► ops ──POST …/operations──┤
                                              │
web Plan with friends / drag ──POST …/operations──────────────┤
                                              ▼
iOS Viewer refresh ◄──GET /scene/{id}─────────┘
iOS AR place/move  ──POST …/operations────────┘
```

Both clients use the same camelCase JSON schema as `packages/schema`.

### Coordinate convention

Documented in `Models/Coordinates.swift` and schema:

- **Units:** meters  
- **Up:** +Y  
- **Origin:** floor center of the room  
- RoomPlan matrices are recentered in `RoomPlanExporter` before upload  

## Collaboration (voice + drawing) — signaling contract

Web clients already use WebRTC mesh voice + spatial whiteboard + **collaborative intent** over the same channel. iOS can join later without changing the API.

### Channel

```text
WS  ws://<api-host>:8000/ws/scene/{sceneId}
```

Join with presence (include voice flags + ghost pose when implementing mic / AR):

```json
{
  "type": "join",
  "user": {
    "userId": "ios_…",
    "displayName": "iPhone",
    "color": "#e2b45c",
    "voiceEnabled": false,
    "voiceSpeaking": false,
    "position": [0, 0.9, 0],
    "lookDirection": [0, 0, -1]
  }
}
```

**Ghost avatars:** remotes with `position` render as translucent capsule/sphere entities (`GhostAvatarAnchors` in `CollaborationStubs.swift`). Skip local `userId`; pulse when `voiceSpeaking`. Broadcast AR camera / focus on the same presence channel.

### Invite links (web + future iOS)

Web shares `/?scene={sceneId}&invite={token}` from `POST /scene/{id}/invites` (or `GET …/invites/default`). Resolve with `GET /invite/{token}`. There is **no peer cap** on WS presence — mesh voice may degrade at high N.

**iOS stub path:** open the same URL (universal link / paste in Settings later), set `APIConfig.sceneId` from the query, join WS with a friendly `displayName`. No hard limit on simultaneous devices.

### Existing furniture (AR select)

RoomPlan export marks scanned furniture `source: "existing"` and `movable: true`; walls are `movable: false`. On web, existing furniture is clickable to **move** or **remove** (clear out of the way). For AR stubs: tap a RealityKit entity with `source == existing` → show move gizmo / remove control that posts `MOVE_OBJECT` or `DELETE_OBJECT` (validators protect walls). See `CollaborationStubs.swift` for presence/ghost patterns; wire selection when extending the AR overlay.

### Voice (WebRTC)

Relay only — no media through FastAPI:

| Type | Fields |
|------|--------|
| `rtc_offer` / `rtc_answer` | `fromUserId`, `toUserId`, `sdp: { type, sdp }` |
| `rtc_ice` | `fromUserId`, `toUserId`, `candidate` (or `null`) |

Offerer rule: smaller `userId` string creates the offer (matches web `VoiceMesh`). Stub DTOs: `Models/CollaborationStubs.swift`. Full `AVAudioEngine` / WebRTC stack is intentionally not wired yet.

### Drawing (AR world strokes)

| Type | Role |
|------|------|
| `draw_stroke` | Broadcast a `DrawingStrokeDTO` (points in **Y-up meters**) |
| `draw_clear` | `scope: "own" \| "all"` + `actorId` |
| `welcome.strokes` | Snapshot of in-memory strokes for late joiners |

**AR render path:** for each stroke, spawn a RealityKit entity whose mesh follows `points` in the shared room frame (same origin as `SceneDTO` objects). Wall-plane strokes from web sit near `z = -bounds.length/2`.

### Intent (group planning)

| Type | Role |
|------|------|
| `intent_open` / `intent_draft` | Shared scenario draft while planning |
| `intent_idea` | Short friend suggestions (hub keeps a list; included on `welcome`) |

iOS currently uses the **Plan this room** HTTP sheet rather than the WS intent channel.

---

## Device vs Simulator

| Capability | Simulator | LiDAR device |
|------------|-----------|--------------|
| `GET /scene` + Viewer | Yes | Yes |
| Demo scene `POST /scene` | Yes | Yes |
| Plan this room → `/ai/layout` | Yes | Yes |
| Live RoomPlan capture | No | Yes (LiDAR) |
| AR camera overlay | Stub buttons only | Yes |

RoomPlan needs a Pro/Max iPhone or iPad Pro with LiDAR. Without LiDAR, use demo export + Viewer/ops sync.

## API surface used

| Method | Path | Purpose |
|--------|------|---------|
| `GET` | `/scene/{sceneId}` | Pull shared graph |
| `POST` | `/scene` | Upsert full normalized scene (RoomPlan export) |
| `PUT` | `/scene/{sceneId}` | Same upsert by path |
| `POST` | `/scene/{sceneId}/operations` | Validated ops (`MOVE_OBJECT`, `DELETE_OBJECT`, …) |
| `POST` | `/scene/{sceneId}/invites` | Create shareable invite token (unlimited peers) |
| `GET` | `/invite/{token}` | Resolve invite → sceneId |
| `POST` | `/ai/layout` | Hybrid planner (Accept applies via operations) |

Ops use `baseVersion` — stale versions return **409**; the app refreshes and surfaces the error.

## Layout

```text
apps/ios/
├── README.md
├── project.yml                 # optional XcodeGen
├── SharedSpatialAI.xcodeproj/
└── SharedSpatialAI/
    ├── App/                    # SwiftUI entry + tabs
    ├── Models/                 # Scene DTOs + coordinates + layout + collaboration stubs
    ├── Networking/             # API client + sync store
    ├── RoomPlan/               # Capture + exporter + PlanRoomSheet
    ├── Viewer/                 # RealityKit non-AR viewer
    ├── AR/                     # AR overlay stub
    └── Resources/              # Info.plist, assets
```

## Demo script for judges

1. Start API (`--host 0.0.0.0`) and web twin.
2. Open this Xcode project; run on Simulator.
3. **Capture** → “Export demo room → POST /scene” → **Plan this room** sheet appears.
4. Pick a scenario → Get AI recommendations → Accept — web twin version bumps with new objects.
5. Or skip planning: refresh the web twin after export alone.
6. Move something on the web → **Viewer** refresh on iOS.
7. On device: **AR** → Place chair → web sees the new object via ops.
