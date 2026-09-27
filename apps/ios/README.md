# Shared Spatial AI — iOS (Camera scan / optional RoomPlan / Live Camera AR)

Working client that proves **one scene graph, two renderers**: this app and the web twin both talk to the same FastAPI scene API.

**Product flow:** **Scan room first → Live Camera AR** (real room + overlays) → **Plan / Place / Invite / Draw in space.**

**LiDAR is optional.** Any ARKit world-tracking iPhone can **Scan with camera** and use **Live AR**. RoomPlan is a secondary “Detailed scan (LiDAR)” path when available.

## Judge demo script (≈4 minutes)

1. **API on Mac** (repo root): `npm run setup` once, then `npm run dev:api` (binds `0.0.0.0:8000`).
2. **Xcode** → open `apps/ios/SharedSpatialAI.xcodeproj` → Team signing → run on a physical iPhone.
3. **Settings (gear)** → Base URL `http://<Mac-LAN-IP>:8000` → **Save** → **Test connection** (must say OK). Scene ID `scene_party_001`.
4. **Scan with camera** → walk until cyan floor / purple wall planes appear → optionally tap floor corners → **Finish scan**. App POSTs the scene and opens Live AR.
5. **Place (+)** → search “sofa” / “lamp” / “rug” → place several SKUs. Each mesh is distinct and sized to catalog meters (sofa ≈ 2.1 m wide).
6. **Tap + drag** furniture on the floor; **Remove** from the selection card.
7. **Pencil** → draw in space (ink under finger) → switch Gold/Cyan → **Clear mine**.
8. **Wand (Plan)** → Party scenario → **Get AI recommendations** → **Open website** on a value pick → **Accept into scene**.
9. **Invite** → copy join link → open on laptop web twin (`:3000`) to show shared scene / presence when WS is up.

Fallback without a room: **Use demo room instead** on the scan gate (or Simulator).

## Live AR feature checklist

| Feature | Status | Notes |
|---------|--------|-------|
| **1:1 product meshes** | Done | Per-SKU RealityKit composites; optional USDZ in `Models/` scaled to `dimensions` (m). |
| **Catalog Place (all SKUs)** | Done | Searchable + category filter; sofa/table/lamp/plant/rug/screen/… not chair-only. |
| **Drag to move / Remove** | Done | Floor-plane drag → `MOVE_OBJECT`; trash → `DELETE_OBJECT`. |
| **Instant draw** | Done | Local-first segments; WS on finger-up; colors + clear mine/all. |
| **Plan + Open website** | Done | `/ai/layout` preview → value picks → retailer URLs. |
| **Invite / WS presence** | Done | Invite link + WS strokes/presence when API reachable. |
| **Settings API URL sticks** | Done | UserDefaults overrides env; Test connection + clear errors. |
| **Camera scan / RoomPlan** | Done | Non-LiDAR ARKit planes primary; LiDAR RoomPlan optional. |

## Product → model mapping

| productId | Mesh (iOS) | Asset stem | Scale source |
|-----------|------------|------------|--------------|
| `product_sofa_01` | Lounge sofa + cushions/arms | `sofa` | 2.1 × 0.82 × 0.91 m |
| `chair_fold_01` | Folding X-frame lounge | `loungeChair` | 0.48 × 0.86 × 0.52 m |
| `chair_dining_02` | Slat dining chair | `chairDesk` | 0.46 × 0.92 × 0.50 m |
| `stool_bar_01` | Pedestal bar stool | `stool` | 0.40 × 1.05 × 0.40 m |
| `beanbag_01` | Soft beanbag | `beanbag` | 0.90 × 0.70 × 0.90 m |
| `product_table_05` | Coffee table | `table` | 1.40 × 0.75 × 1.10 m |
| `desk_study_01` | Study desk + drawer | `desk` | 1.20 × 0.75 × 0.60 m |
| `table_dining_01` | Dining table | `sideTable` | 1.80 × 0.75 × 0.90 m |
| `product_39` | Arc floor lamp | `lampRoundFloor` | 0.40 × 1.72 × 0.40 m |
| `party_lights_03` | String lights | `string_lights` | 3.00 × 0.05 × 0.05 m |
| `lamp_desk_01` | Task desk lamp | `lampSquareTable` | 0.20 × 0.45 × 0.20 m |
| `pendant_dinner_01` | Pendant dome | `pendant` | 0.45 × 0.35 × 0.45 m |
| `backdrop_12` | Photo backdrop | `backdrop` | 2.00 × 2.40 × 0.08 m |
| `plant_tall_02` | Tall plant | `pottedPlant` | 0.45 × 1.40 × 0.45 m |
| `rug_party_01` | Dance rug | `rugRectangle` | 2.00 × 0.02 × 2.00 m |
| `projector_screen_01` | Projector screen | `projector_screen` | 2.40 × 1.50 × 0.06 m |

**Scale rule:** fit model AABB to `dimensions.width/height/depth` in meters (same as web GLB fitting). See `ProductModelCatalog.swift` + `FurnitureMeshBuilder.swift`. USDZ drop-in: `SharedSpatialAI/Models/README.md`.

## Open in Xcode

1. On a Mac with **Xcode 15+** (iOS 17 SDK):
   ```bash
   open apps/ios/SharedSpatialAI.xcodeproj
   ```
2. Select the **SharedSpatialAI** target → **Signing & Capabilities** → choose your Team.
3. Destinations:
   - **Simulator** — demo room + RealityKit map (no live camera).
   - **Any ARKit iPhone** — Scan with camera → Live AR.
   - **LiDAR (optional)** — Detailed scan (RoomPlan).

### If the `.xcodeproj` fails to open

Create a new **iOS App** (SwiftUI, iOS 17+) named `SharedSpatialAI`, drag the `SharedSpatialAI/` source folder in, link **RoomPlan**, **RealityKit**, **ARKit**. Or regenerate with XcodeGen from `project.yml`.

## Run the backend first

```bash
npm run setup   # once
npm run dev:api # binds 0.0.0.0:8000 — required for a physical device
```

Or both web + API: `npm run dev`.

## Configure API URL

**In-app Settings** (persisted in UserDefaults — survives relaunch):

| Destination | Base URL |
|-------------|----------|
| Simulator | `http://127.0.0.1:8000` |
| Device on LAN | `http://<your-mac-lan-ip>:8000` |

Use **Test connection** before scanning. `Info.plist` allows local HTTP for demos.

## Layout

```text
apps/ios/
├── README.md
├── project.yml
├── SharedSpatialAI.xcodeproj/
└── SharedSpatialAI/
    ├── App/           # Scan-first RootFlowView + Settings
    ├── Models/        # DTOs + optional USDZ (see Models/README.md)
    ├── Networking/    # API + SceneSyncStore + SceneWebSocket
    ├── RoomPlan/      # Optional LiDAR + Plan + Invite + Catalog
    ├── Viewer/        # Live AR HUD / map twin UI
    ├── AR/            # Camera scan + ARView + FurnitureMeshBuilder
    └── Resources/
```

## API surface used

| Method | Path | Use |
|--------|------|-----|
| `GET` | `/scene/{id}` | Refresh |
| `POST` | `/scene` | Scan / demo upload |
| `POST` | `/scene/{id}/operations` | Move / place / delete / AI accept |
| `GET` | `/catalog` | Place picker |
| `POST` | `/ai/layout` | Plan recommendations |
| `POST` | `/scene/{id}/invites` | Invite link |
| `WS` | `/ws/scene/{id}` | Draw + presence |
