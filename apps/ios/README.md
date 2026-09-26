# Shared Spatial AI — iOS (Camera scan / optional RoomPlan / Live Camera AR)

Working client that proves **one scene graph, two renderers**: this app and the web twin both talk to the same FastAPI scene API.

**Product flow:** **Scan room first → Live Camera AR** (Pokémon GO–style: real room + overlays) → **Plan / Invite / Draw in space.**

**LiDAR is optional.** Any ARKit world-tracking iPhone can **Scan with camera** (plane detection) and use **Live AR**. RoomPlan is a secondary “Detailed scan (LiDAR)” path when `RoomCaptureSession.isSupported`.

## Open in Xcode

1. On a Mac with **Xcode 15+** (iOS 17 SDK):
   ```bash
   open apps/ios/SharedSpatialAI.xcodeproj
   ```
2. Select the **SharedSpatialAI** target → **Signing & Capabilities** → choose your Team (required for device).
3. Pick a run destination:
   - **iOS Simulator** — scan-first gate + demo room export + RealityKit **map** (no live camera).
   - **Any physical iPhone/iPad with ARKit** — **Scan with camera** → **Live AR** (no LiDAR required).
   - **LiDAR device (optional)** — also offers **Detailed scan (LiDAR)** via RoomPlan for richer walls/furniture.

### Try on a non-LiDAR iPhone

1. Start the API from the repo root (`npm run setup` once, then `npm run dev:api` so it binds `0.0.0.0:8000`).
2. Open `apps/ios/SharedSpatialAI.xcodeproj` in Xcode, set your Team, select your non-LiDAR iPhone.
3. In-app **Settings** → set Base URL to `http://<your-mac-lan-ip>:8000`.
4. On the launch gate tap **Scan with camera** (primary CTA). Walk the room until cyan floor / purple wall planes appear; optionally tap the floor to mark corners; tap **Finish scan**.
5. App POSTs the Scene JSON and opens **Live AR** — place/move objects, **Draw in space**, **Plan**, **Invite** work without LiDAR.
6. **Detailed scan (LiDAR)** stays hidden or unused on non-LiDAR phones; **Use demo room** remains available.

### If the `.xcodeproj` fails to open

Create a new **iOS App** (SwiftUI, iOS 17+) named `SharedSpatialAI`, then drag the `SharedSpatialAI/` source folder into the project (check “Copy items if needed” off; add to target). Link frameworks: **RoomPlan**, **RealityKit**, **ARKit**. Point Info to `SharedSpatialAI/Resources/Info.plist`.

Optional: regenerate with [XcodeGen](https://github.com/yonaskolb/XcodeGen) from `project.yml`:

```bash
cd apps/ios && xcodegen generate && open SharedSpatialAI.xcodeproj
```

## Run the backend first

From the repo root (same API the web twin uses):

```bash
npm run setup   # once
npm run dev:api # binds 0.0.0.0:8000 — required for a physical device
```

Or both web + API: `npm run dev`.

`--host 0.0.0.0` is already set by `scripts/run-api.mjs` so a **physical device** can reach your Mac. Set the **LAN IP** in Settings (below).

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
Scan with camera (primary)  or  Detailed scan LiDAR (optional)  or  Demo room
        ↓  POST /scene
   Live AR (ARWorldTrackingConfiguration — no LiDAR mesh required)
        ├── Draw in space → WS draw_stroke (free 3D polylines)
        ├── Plan sheet → POST /ai/layout → ops
        ├── Invite → POST …/invites → share web ?scene=&invite=
        └── Tap furniture → move / remove (existing + catalog)
```

| Screen | Role |
|--------|------|
| **Scan** (launch) | Primary **Scan with camera**; secondary **Detailed scan (LiDAR)** if supported; **Use demo room**; load existing map. |
| **Live AR** | Camera shows the real room; furniture / ghosts / strokes overlay in world space. **Draw in space**, **Plan**, **Invite**. Toggle **Map** for a non-AR twin. |
| **Plan** | Same hybrid `/ai/layout` as web → Accept applies ops. |
| **Invite** | Creates API invite; share link opens web on the **same `sceneId`**. |

### Try it (Mac + Simulator)

1. Start API (`--host 0.0.0.0`) and optionally the web twin (`npm run dev`).
2. Open this Xcode project; run on Simulator.
3. Launch lands on **Scan** → **Use demo room** → auto-opens map + **Plan** sheet.
4. Accept AI ops (or Close) → tap an object → move / remove → **Draw in space** → **Invite** and open the link on localhost web.
5. On any ARKit device: **Scan with camera** → **Live AR** with camera passthrough + free-space sketch.

---

## Sync loop with the web twin

```text
iOS camera / RoomPlan / demo export ──POST /scene──► FastAPI SceneStore
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
- Camera-scan and RoomPlan matrices are recentered before upload  

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

RoomPlan / camera-scan exports mark scanned surfaces `source: "existing"`; walls are fixed. Tap in Live AR → move / remove (same ops as web).

---

## Device vs Simulator

| Capability | Simulator | Non-LiDAR device | LiDAR device |
|------------|-----------|------------------|--------------|
| Scan-first gate | Yes (demo CTA) | Yes (camera primary) | Yes (camera + RoomPlan) |
| Camera plane scan | No | Yes | Yes |
| Detailed RoomPlan | No | No (hidden) | Yes (optional) |
| Demo / load map → AR | Yes (map twin) | Yes (Live camera AR) | Yes |
| Plan → `/ai/layout` | Yes | Yes | Yes |
| Camera passthrough AR | No | Yes | Yes |
| Draw in space + WS | Yes (map ray) | Yes (camera ray) | Yes |

## API surface used

| Method | Path | Purpose |
|--------|------|---------|
| `GET` | `/scene/{sceneId}` | Pull shared graph |
| `POST` | `/scene` | Upsert full normalized scene (scan / demo export) |
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
    ├── RoomPlan/      # Optional LiDAR capture + Plan + Invite
    ├── Viewer/        # Live AR / map twin UI
    ├── AR/            # Camera scan + device ARViewContainer
    └── Resources/
```
