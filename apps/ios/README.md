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
| **Capture** | RoomPlan scan → normalize → `POST /scene`. Simulator: “Export demo room”. |
| **Viewer** | RealityKit (non-AR) pull of `GET /scene/{id}`; refresh after web edits. |
| **AR** | Overlay stub: place/nudge anchors → `POST /scene/{id}/operations`. Device-only camera. |
| **Settings** | API URL / scene id / coordinate notes. |

## Sync loop with the web twin

```text
iOS RoomPlan / demo export ──POST /scene──► FastAPI SceneStore
                                              │
web drag / AI accept ──POST …/operations──────┤
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

Web clients already use WebRTC mesh voice + spatial whiteboard over the same channel. iOS can join later without changing the API.

### Channel

```text
WS  ws://<api-host>:8000/ws/scene/{sceneId}
```

Join with presence (include voice flags when implementing mic):

```json
{
  "type": "join",
  "user": {
    "userId": "ios_…",
    "displayName": "iPhone",
    "color": "#e2b45c",
    "voiceEnabled": false,
    "voiceSpeaking": false
  }
}
```

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

---

## Device vs Simulator

| Capability | Simulator | LiDAR device |
|------------|-----------|--------------|
| `GET /scene` + Viewer | Yes | Yes |
| Demo scene `POST /scene` | Yes | Yes |
| Live RoomPlan capture | No | Yes (LiDAR) |
| AR camera overlay | Stub buttons only | Yes |

RoomPlan needs a Pro/Max iPhone or iPad Pro with LiDAR. Without LiDAR, use demo export + Viewer/ops sync.

## API surface used

| Method | Path | Purpose |
|--------|------|---------|
| `GET` | `/scene/{sceneId}` | Pull shared graph |
| `POST` | `/scene` | Upsert full normalized scene (RoomPlan export) |
| `PUT` | `/scene/{sceneId}` | Same upsert by path |
| `POST` | `/scene/{sceneId}/operations` | Validated ops (`MOVE_OBJECT`, `ADD_OBJECT`, …) |

Ops use `baseVersion` — stale versions return **409**; the app refreshes and surfaces the error.

## Layout

```text
apps/ios/
├── README.md
├── project.yml                 # optional XcodeGen
├── SharedSpatialAI.xcodeproj/
└── SharedSpatialAI/
    ├── App/                    # SwiftUI entry + tabs
    ├── Models/                 # Scene DTOs + coordinates + collaboration stubs
    ├── Networking/             # API client + sync store
    ├── RoomPlan/               # Capture + exporter
    ├── Viewer/                 # RealityKit non-AR viewer
    ├── AR/                     # AR overlay stub
    └── Resources/              # Info.plist, assets
```

## Demo script for judges

1. Start API (`--host 0.0.0.0`) and web twin.
2. Open this Xcode project; run on Simulator.
3. **Capture** → “Export demo room → POST /scene” (or scan on device).
4. Refresh the web twin — same objects / version bump.
5. Move something on the web → **Viewer** refresh on iOS.
6. On device: **AR** → Place chair → web sees the new object via ops.
