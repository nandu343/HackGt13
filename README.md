# Shared Spatial AI

HackGT 13 — collaborative spatial planning: one canonical scene graph, **Pokémon GO–style camera AR** (real room + overlays), free-space AR sketches, validated AI ops, and a secondary digital-twin map — all on the **same** scene.

> **Scan / enter first → live Camera AR over the real room → plan / draw / invite.** Every client and the AI edit the **same** scene. The renderer never owns world state.

```text
Scan room (iOS RoomPlan) / Enter Camera AR (web)
      ↓
Canonical scene graph (versioned ops)
      ├── Web Camera AR (getUserMedia + optional WebXR immersive-ar)
      ├── Web Map twin (secondary dollhouse)
      ├── Free-space AR sketch (WS draw_stroke, 3D polylines)
      ├── AI planner → ops (accept to apply)
      ├── Catalog + budget + invite links
      └── iOS Live AR (ARKit camera passthrough) after scan
```

---

## Before / after UX

| Area | Before | After |
|------|--------|-------|
| **AR framing** | Synthetic twin as primary | **Camera AR** (real room + overlays) is the hero |
| **Drawing** | Wall whiteboard plane | **Draw in space** — free 3D polylines synced to peers |
| **Flow** | Tools first; room optional | **Scan / enter first**, then Plan / Invite / sketch in AR |
| **Web twin** | Orbit dollhouse only | Map twin is **secondary**; Camera AR default |
| **iOS** | Tab clutter | Scan → **Live AR** (camera) → Plan / Invite / Draw in space |

Mesh voice may degrade at high N (WebRTC is O(n²)); joins are still allowed.

---

## Judge runbook (2 processes)

### Prerequisites

- Node 20+
- Python 3.11+ (3.12 OK) — `python3` on Mac/Linux, `py -3` / `python` on Windows
- Optional: copy `.env.example` → `.env` at repo root (API loads it automatically)

### Env vars

| Variable | Where | Default | Purpose |
|----------|--------|---------|---------|
| `NEXT_PUBLIC_API_URL` | web | `http://localhost:8000` | API base URL |
| `NEXT_PUBLIC_SCENE_WS` | web | on (set `0` to disable) | Connect to `WS /ws/scene/{id}` |
| `CORS_ORIGINS` | api | `http://localhost:3000` | Allowed web origin |
| `XAI_API_KEY` | api | unset | Optional hybrid Grok LLM (`grok-4.6`); rules if empty. `OPENAI_API_KEY` still works as deprecated alias |
| `STRIPE_SECRET_KEY` | api | unset | Optional Stripe test Checkout; sandbox stub URL if empty |
| `STRIPE_SUCCESS_URL` / `STRIPE_CANCEL_URL` | api | localhost:3000 | Checkout redirect targets |
| `LOCK_TTL_SECONDS` | api | `30` | Soft-lock TTL for collaborative edits |
| `SCENE_STORE` | api | `memory` | `supabase` when using Postgres persistence |

See `.env.example` for Supabase optional keys. iOS API URL / scene id: **Settings in-app** or **[apps/ios/README.md](apps/ios/README.md)**.

### Mac / Windows — setup + run

```bash
cd HackGt13
npm install
npm run setup
npm run dev
```

`npm run setup` installs npm workspaces and `apps/api/requirements.txt` (detects `python3` / `py -3.12` / `python`).  
`npm run dev` starts web + API together. `npm run dev:api` uses `scripts/run-api.mjs` (finds Python, auto-installs FastAPI if missing, binds `0.0.0.0:8000` with cwd `apps/api` so `app` always imports).

Mac shorthand: `make setup && make dev` or `./scripts/dev.sh`.

- Web: [http://localhost:3000](http://localhost:3000)
- API: [http://localhost:8000/health](http://localhost:8000/health)
- Docs: [http://localhost:8000/docs](http://localhost:8000/docs)

### Or separately

```bash
npm run dev:api
npm run dev:web
```

### iOS (3rd client)

API already binds `--host 0.0.0.0` via `npm run dev:api`. On a physical device, set the **Mac LAN IP** in the app (Settings) or `APIConfig.swift` — see **[apps/ios/README.md](apps/ios/README.md)**.

```bash
open apps/ios/SharedSpatialAI.xcodeproj
```

**Simulator:** Scan gate → **Use demo room** → map twin + Draw in space + Plan. **LiDAR device:** RoomPlan → **Live AR** (camera passthrough) with furniture overlays + free-space sketch. Same `scene_party_001` / Y-up meters as the web twin. Catalog furniture renders as **GLB meshes** on web (`apps/web/public/models`) and **RealityKit multi-mesh composites** (optional USDZ) on iOS — not plain boxes.
---

## Demo loop

### Web (desktop or phone browser)

1. Open [http://localhost:3000](http://localhost:3000) — **Enter Camera AR** gate (invite links skip in).
2. Allow camera → rear feed + shared furniture overlays (**Camera AR**). Toggle **Map twin** for the exact digital twin.
3. On supported browsers (typically Android Chrome / WebXR devices): **WebXR AR** for `immersive-ar`.
4. **Invite** → share `?scene=…&invite=TOKEN` → peer joins the same scene.
5. **Plan** → AI → **Accept**. **AR sketch** → draw in free 3D space (not a wall whiteboard).
6. Drag / remove existing furniture; walls stay fixed.

**Web Camera AR limits:** `getUserMedia` backdrop is **approximate** (no full 6DoF world tracking). Use iOS Live AR or WebXR for true world-locked overlays. Map twin stays exact.

Reset the gate with `?gate=1` if needed.

### iPhone (physical device)

1. Start API with `--host 0.0.0.0`; set Settings → Mac LAN IP.
2. **Scan room** (RoomPlan) → enter **Live AR** (camera shows the real room).
3. Tap furniture → move / remove; **Place** catalog chair; **Draw in space** (finger drag → 3D stroke synced via WS).
4. **Invite** → open link on web; peers see the same ops + strokes.

---

## Collaboration (voice + AR sketch + intent + invite + timeline)

| Feature | Approach |
|---------|----------|
| **Invite** | `POST /scene/{id}/invites` → token; web URL `/?scene={id}&invite={token}`. **No peer cap.** |
| **Voice** | WebRTC mesh; signaling on `WS /ws/scene/{id}`. |
| **Drawing** | Free-space 3D polylines; WS `draw_stroke` / `draw_clear` (`plane: "free"`). |
| **Intent** | Plan modal → `POST /ai/layout` → Accept. |
| **Timeline / Disagreement** | Restore/branch; A/B ghosts. |
| **Existing furniture** | Relocatable/removable; structure fixed. |

iOS: scan-first Live AR + Plan + Invite + Draw — **[apps/ios/README.md](apps/ios/README.md)**.

---

## API surface (Phase 1+)

| Method | Path | Notes |
|--------|------|--------|
| `GET` | `/health` | Liveness + store mode |
| `GET` | `/scene/{sceneId}` | Full scene |
| `POST` | `/scene` | Upsert full scene (RoomPlan / iOS export) |
| `PUT` | `/scene/{sceneId}` | Same upsert by path |
| `POST` | `/scene/{sceneId}/operations` | Validate + apply; `409` on stale `baseVersion` |
| `POST` | `/scene/{sceneId}/invites` | Create shareable invite token |
| `GET` | `/invite/{token}` | Resolve token → `sceneId` |
| `POST` | `/ai/layout` | Hybrid planner ops (**not** applied until Accept) |
| `WS` | `/ws/scene/{sceneId}` | Presence / patch / voice / draw / intent — **unlimited presence** |

---

## Repo layout

```text
apps/web          Next.js + R3F Camera AR + Map twin
apps/api          FastAPI scene store, ops, AI, catalog, invites
apps/ios          Scan-first → Live AR + Plan / Invite / Draw
packages/schema   Shared Zod/TS types + demo seed
```

---

## Architecture notes

- **Ops-only AI**: planner returns ops; validators own legality.
- **Camera AR first**: real room via device camera; shared graph as overlays.
- **Free-space drawing**: strokes are arbitrary Y-up meter polylines (not wall-only).
- **Coordinate system**: Y-up meters, origin at floor center.
- **WebXR**: `@react-three/xr` `immersive-ar` when `navigator.xr` supports it; else getUserMedia fallback.

---

## Status

**Working for demo:** Camera AR + Map twin (web), iOS Live AR after RoomPlan, free-space AR sketch sync, invite links, Plan with friends, drag / clear existing furniture, hybrid AI, timeline / disagreement, catalog/budget, WS presence + voice + draw.

**Known limits:** Web getUserMedia AR is not full SLAM; WebXR needs a compatible device/browser; iOS WebRTC voice still optional.
