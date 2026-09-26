# Shared Spatial AI — iOS (RoomPlan / Live Camera AR)

Working client that proves **one scene graph, two renderers**: this app and the web twin both talk to the same FastAPI scene API.

**Product flow:** **Scan room first → Live Camera AR** (Pokémon GO–style: real room + overlays) → **Plan / Invite / Draw in space.**

## Open in Xcode

1. On a Mac with **Xcode 15+** (iOS 17 SDK):
   ```bash
   open apps/ios/SharedSpatialAI.xcodeproj
   ```
2. Select the **SharedSpatialAI** target → **Signing & Capabilities** → choose your Team (required for device).
3. Pick a run destination:
   - **iOS Simulator** — scan-first gate + demo room export + RealityKit **map** (no live camera / no RoomPlan).
   - **Physical iPhone/iPad with LiDAR** — RoomPlan capture → **Live AR** camera passthrough with shared overlays.

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

**In-app:** gear on the scan screen / Live AR → **Settings** → edit Base URL + Scene ID → Save.

Or edit `SharedSpatialAI/Networking/APIConfig.swift` / set env `SHARED_SPATIAL_API_URL`:

| Destination | Base URL |
|-------------|----------|
| Simulator | `http://127.0.0.1:8000` (default) |
| Device on LAN | `http://<your-mac-lan-ip>:8000` |

`Info.plist` allows local HTTP (`NSAllowsLocalNetworking` + ATS exception for demos).

## Flow (Scan → Live AR → Plan / Invite / Draw)

```text
Scan room (RoomPlan) or Use demo room
        ↓  POST /scene
   Live AR (ARKit camera passthrough)
        ├── Draw in space → WS draw_stroke (free 3D polylines)
        ├── Plan sheet → POST /ai/layout → ops
        ├── Invite → POST …/invites → share web ?scene=&invite=
        └── Tap furniture → move / remove (existing + catalog)
```

| Screen | Role |
|--------|------|
| **Scan** (launch) | Big **Scan room** (device) or **Use demo room** (simulator). Secondary: load existing map from API. Settings gear for API URL. |
| **Live AR** | Camera shows the real room; furniture / ghosts / strokes overlay in world space. **Draw in space**, **Plan**, **Invite**. Toggle **Map** for a non-AR twin. |
| **Plan** | Same hybrid `/ai/layout` as web → Accept applies ops. |
| **Invite** | Creates API invite; share link opens web on the **same `sceneId`**. |

### Try it (Mac + Simulator)

1. Start API (`--host 0.0.0.0`) and optionally the web twin (`npm run dev`).
2. Open this Xcode project; run on Simulator.
3. Launch lands on **Scan** → **Use demo room** → auto-opens map + **Plan** sheet.
4. Accept AI ops (or Close) → tap an object → move / remove → **Draw in space** → **Invite** and open the link on localhost web.
5. On device: **Scan room** (RoomPlan) → **Live AR** with camera passthrough + free-space sketch.

---

## Sync loop with the web twin

```text
iOS RoomPlan / demo export ──POST /scene──► FastAPI SceneStore
iOS Plan sheet ──POST /ai/layout──► ops ──POST …/operations──┤
iOS Draw in space ──WS draw_stroke──────────────────────────┤
                                              │
web Camera AR / Map / Plan / drag ──ops + WS────────────────┤
                                              ▼
iOS Live AR refresh ◄──GET /scene/{id} + WS strokes─────────┘
iOS place/move/remove ──POST …/operations───────────────────┘
```

Both clients use the same camelCase JSON schema as `packages/schema`.

### Coordinate convention

Documented in `Models/Coordinates.swift` and schema:

- **Units:** meters  
- **Up:** +Y  
- **Origin:** floor center of the room  
- RoomPlan matrices are recentered in `RoomPlanExporter` before upload  

## Collaboration (voice + free-space drawing)

Web clients use WebRTC mesh voice + **AR sketch** + collaborative intent over the same channel. iOS joins for **draw_stroke** / presence via `SceneWebSocket`.

### Channel

```text
WS  ws://<api-host>:8000/ws/scene/{sceneId}
```

**Drawing:** finger drag projects points along the camera ray (~1.2 m) — free space, not a wall whiteboard. `plane: "free"`.

**Ghost avatars:** stub peers render as translucent capsules; live presence when WS is connected.

### Invite links

Web shares `/?scene={sceneId}&invite={token}`. iOS **Invite** creates the token and builds a join URL (API host port 8000 → web 3000 on the same host).

### Existing furniture

RoomPlan export marks scanned furniture `source: "existing"` and `movable: true`; walls are fixed. Tap in Live AR → move / remove (same ops as web).

---

## Device vs Simulator

| Capability | Simulator | LiDAR device |
|------------|-----------|--------------|
| Scan-first gate | Yes (demo CTA) | Yes (RoomPlan primary) |
| Demo / load map → AR | Yes (map twin) | Yes (Live camera AR) |
| Plan → `/ai/layout` | Yes | Yes |
| Live RoomPlan capture | No | Yes (LiDAR) |
| Camera passthrough AR | No | Yes |
| Draw in space + WS | Yes (map ray) | Yes (camera ray) |

## API surface used

| Method | Path | Purpose |
|--------|------|---------|
| `GET` | `/scene/{sceneId}` | Pull shared graph |
| `POST` | `/scene` | Upsert full normalized scene (RoomPlan export) |
| `PUT` | `/scene/{sceneId}` | Same upsert by path |
| `POST` | `/scene/{sceneId}/operations` | Validated ops |
| `POST` | `/scene/{sceneId}/invites` | Shareable invite token |
| `POST` | `/ai/layout` | Hybrid planner |
| `WS` | `/ws/scene/{sceneId}` | Draw strokes + presence |

## Layout

```text
apps/ios/
├── README.md
├── project.yml
├── SharedSpatialAI.xcodeproj/
└── SharedSpatialAI/
    ├── App/           # Scan-first RootFlowView
    ├── Models/
    ├── Networking/    # API + SceneSyncStore + SceneWebSocket
    ├── RoomPlan/      # Capture + Plan + Invite
    ├── Viewer/        # Live AR / map twin UI
    ├── AR/            # Device ARViewContainer (camera AR)
    └── Resources/
```
