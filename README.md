# Shared Spatial AI

HackGT 13 — collaborative spatial planning: one canonical scene graph, a browser digital twin, validated AI ops, and a clear path to AR / realtime / commerce.

> Every client and the AI edit the **same** scene. The renderer never owns world state.

```text
Room / demo seed
      ↓
Canonical scene graph (versioned ops)
      ├── Web 3D twin (this repo)
      ├── AI planner → ops (accept to apply)
      ├── Catalog + budget
      └── iOS RoomPlan / RealityKit scaffold (`apps/ios`)
```

---

## Judge runbook (2 processes)

### Prerequisites

- Node 20+
- Python 3.11+ (3.12 OK)
- Optional: copy `.env.example` → `.env` at repo root

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

See `.env.example` for Supabase optional keys. iOS API URL / scene id live in **[apps/ios/README.md](apps/ios/README.md)** (`APIConfig.swift`) — do not duplicate device LAN setup here.

### Install

```bash
npm install
py -3.12 -m pip install -r apps/api/requirements.txt
```

### Run both (recommended)

```bash
npm run dev
```

- Web: [http://localhost:3000](http://localhost:3000)
- API: [http://localhost:8000/health](http://localhost:8000/health)
- Docs: [http://localhost:8000/docs](http://localhost:8000/docs)

### Or separately

```bash
npm run dev:api
npm run dev:web
```

API equivalent:

```bash
py -3.12 -m uvicorn app.main:app --reload --app-dir apps/api --host 0.0.0.0 --port 8000
```

Use `--host 0.0.0.0` when syncing from a physical iOS device.

### iOS scaffold (optional 3rd client)

See **[apps/ios/README.md](apps/ios/README.md)**. On a Mac:

```bash
open apps/ios/SharedSpatialAI.xcodeproj
```

Simulator: Viewer + demo `POST /scene`. LiDAR device: RoomPlan capture + AR ops. Same `scene_party_001` / Y-up meters as the web twin.

---

## Demo loop (web)

1. Open the web app — status pill should read **API connected · v1** (scene `scene_party_001` from `GET /scene/...`). Peer count appears when WS presence is live.
2. **Drag** a movable object (gizmo) → optimistic move → `POST /scene/.../operations` bumps version. Open a second tab to confirm **patch** sync.
3. **Voice:** open a 2nd browser tab → **Join voice** on both → allow mic → talk; mute/unmute + speaking rings show in the collab bar. Presence chips show who has voice enabled.
4. **Draw:** toggle **Draw** → paint on the back wall → strokes appear in the other tab; **Clear mine** / **Clear all**.
5. Edit the AI prompt → **Generate layout** → review scenario, **planner mode** (rules/llm), fixed ops + validation warnings → **Accept** (animated lerp) or **Reject**. Accept stays disabled when no valid ops remain.
6. Watch **Budget** update from catalog `productId`s; **Add** items from Catalog; **Checkout** opens `POST /commerce/checkout` URL (Stripe test session or sandbox stub).
7. Keyboard: click select · `Delete` · `Ctrl/Cmd+Z` undo · `Esc` deselect / exit draw.

If the status shows an error, start the API and hit **Reload**.

---

## Collaboration (voice + whiteboard)

| Feature | Approach |
|---------|----------|
| **Voice** | WebRTC **mesh** (STUN). Signaling over existing `WS /ws/scene/{id}`: `rtc_offer` / `rtc_answer` / `rtc_ice` (targeted `fromUserId`→`toUserId`). Presence: `voiceEnabled` / `voiceSpeaking`. |
| **Drawing** | Ephemeral spatial strokes (Y-up meters) on the back wall plane. WS: `draw_stroke` / `draw_clear`; hub keeps ≤200 strokes in memory and includes them on `welcome`. |

iOS can join the same signaling channel later — see **[apps/ios/README.md](apps/ios/README.md)** and `CollaborationStubs.swift`.

---

## API surface (Phase 1+)

| Method | Path | Notes |
|--------|------|--------|
| `GET` | `/health` | Liveness + store mode |
| `GET` | `/scene/{sceneId}` | Full scene |
| `POST` | `/scene` | Upsert full scene (RoomPlan / iOS export) |
| `PUT` | `/scene/{sceneId}` | Same upsert by path |
| `POST` | `/scene/{sceneId}/operations` | Validate + apply; `409` on stale `baseVersion` / foreign locks |
| `POST` | `/scene/{sceneId}/locks` | Soft-lock acquire |
| `POST` | `/scene/{sceneId}/locks/release` | Soft-lock release |
| `POST` | `/ai/layout` | Hybrid planner ops (**not** applied until client Accept) |
| `GET` | `/catalog` | Seed products |
| `POST` | `/commerce/cart/summary` | Cart from scene products |
| `POST` | `/commerce/checkout` | Stripe test Checkout or sandbox stub URL |
| `WS` | `/ws/scene/{sceneId}` | `welcome` / `presence` / `scene` / `patch` / `lock` + voice `rtc_*` + `draw_stroke` / `draw_clear` |

Web client connects to the WebSocket by default (`apps/web/lib/ws.ts`). Set `NEXT_PUBLIC_SCENE_WS=0` to use HTTP-only.

---

## Repo layout

```text
apps/web          Next.js + R3F digital twin
apps/api          FastAPI scene store, ops, AI stub, catalog
apps/ios          RoomPlan capture + RealityKit viewer + AR ops stub
packages/schema   Shared Zod/TS types + demo seed
```

Web twin pieces:

- `lib/api.ts` / `lib/sceneStore.ts` — fetch, optimistic ops, Accept lerp, undo
- `components/SceneCanvas`, `ObjectGizmo`, `AiPanel`, `CatalogPanel`, `BudgetPanel`

---

## Architecture notes

- **Ops-only AI**: planner returns `MOVE_OBJECT` / `ADD_OBJECT` / …; applier + validators own legality.
- **Versioning**: every successful envelope increments `version`; clients send `baseVersion`.
- **Coordinate system**: Y-up meters, origin at floor center (see schema package).

---

## Status

**Working for demo:** web ←→ API scene loop, drag ops, hybrid AI accept/reject (rules + optional LLM), catalog/budget, checkout stub/Stripe, WS presence/patch/locks, **WebRTC voice mesh + shared wall drawing**, polish UX, iOS RoomPlan/AR scaffold syncing the same scene API.

**Optional / later polish:** deep Supabase auth & Realtime channel (local WS is the required path), richer Stripe UX, TURN for cellular voice, iOS WebRTC/AVAudio join.
