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
      ├── Invite links (unlimited peers)
      └── iOS RoomPlan / RealityKit scaffold (`apps/ios`)
```

---

## Before / after UX

| Area | Before | After |
|------|--------|-------|
| **Chrome** | Dense hackathon dashboard — every panel always open | Core flow (plan → AI → place → invite) first; timeline / disagreement / draw grouped under **Advanced tools** (tabbed on mobile) |
| **Invite** | “Open a second tab” only | Shareable `?scene=…&invite=TOKEN` links, **Invite friends** CTA, optional display name, **no peer cap** |
| **Existing furniture** | Walls + furniture treated similarly; unclear clear-out | Click `source: existing` furniture → gizmo move or Remove (confirm) / Delete×2; walls stay fixed |
| **Empty states** | Bare overlay text | Loading pulse, error + Retry, empty presence copy |
| **Visual** | Functional dark panel | Clearer hierarchy, breathing room, accent invite CTAs, selection bar on the twin |

Mesh voice may degrade at high N (WebRTC is O(n²)); joins are still allowed.

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

1. Open the web app — status pill should read **API connected · v1** (scene `scene_party_001`). Peer count appears when WS presence is live.
2. **Invite friends** (header / primary CTA / collab bar): copy the shareable link (`?scene=…&invite=TOKEN`). Set an optional display name. Open the link in another browser / device — no joiner limit.
3. **Plan with friends** (auto-opens once after first load / Skip marks it seen): scenario chips, notes, friends’ ideas over WS → **Get AI recommendations** → **Accept into scene**.
4. **Clear what’s in the way:** click the sofa (`source: existing`) → amber selection ring + bar → drag gizmo to move, or **Remove** (confirm) / press **Delete** twice. Walls stay fixed. Peers see the op via WS patch.
5. **Drag** catalog objects → optimistic move → `POST /scene/.../operations`. Second tab confirms **patch** sync.
6. **Voice:** **Join voice** on both tabs → allow mic → talk. Mesh may get noisy with many peers; unlimited join still works.
7. **Draw:** sidebar **Tools** / collab **Draw** → paint on the back wall; **Clear mine** / **Clear all**.
8. Sidebar **Plan** → AI layout Generate / Accept / Propose. **Shop** → Budget + Catalog. **Advanced tools** (desktop) or **Tools** tab (mobile): Timeline, Disagreement, Draw.
9. **Timeline:** Restore / Branch. **Disagreement:** A/B ghosts → Blend or picks.
10. Keyboard: click select · `Delete`×2 remove · `Ctrl/Cmd+Z` undo · `Esc` deselect / exit draw.

If the status shows an error, start the API and hit **Reload** / **Retry**.

---

## Collaboration (voice + whiteboard + intent + invite + timeline)

| Feature | Approach |
|---------|----------|
| **Invite** | `POST /scene/{id}/invites` → token; web URL `/?scene={id}&invite={token}`. `GET /invite/{token}` resolves. Optional display name on join (localStorage). **No hard presence / peer cap** — WS accepts unlimited joiners for a `sceneId`. Mesh voice may degrade at high N. |
| **Voice** | WebRTC **mesh** (STUN). Signaling over `WS /ws/scene/{id}`: `rtc_offer` / `rtc_answer` / `rtc_ice`. Presence: `voiceEnabled` / `voiceSpeaking`. |
| **Drawing** | Ephemeral spatial strokes on the back wall. WS: `draw_stroke` / `draw_clear`; hub keeps ≤200 strokes; included on `welcome`. |
| **Intent** | Post-scan group goal. WS: `intent_open` / `intent_draft` / `intent_idea`. Web modal → `POST /ai/layout` → Accept. |
| **Timeline** | Version snapshots. `GET /scene/{id}/timeline`, restore / branch. WS `timeline`. |
| **Disagreement** | A/B proposals + ghosts; blend / picks. WS `disagreement`. |
| **Existing furniture** | `source: 'existing'` (non-wall) is relocatable/removable for planning; structure (`wall`, …) stays protected in validators. |

iOS: **[apps/ios/README.md](apps/ios/README.md)** — invite links + selecting existing furniture in AR (stubs).

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
| `POST` | `/scene/{sceneId}/invites` | Create shareable invite token |
| `GET` | `/scene/{sceneId}/invites` | List invites for scene |
| `GET` | `/scene/{sceneId}/invites/default` | Ensure + return one invite |
| `GET` | `/invite/{token}` | Resolve token → `sceneId` + `joinPath` |
| `GET` | `/scene/{sceneId}/timeline` | Version history snapshots |
| `POST` | `/scene/{sceneId}/timeline/restore` | Restore scene to an entry |
| `POST` | `/scene/{sceneId}/timeline/branch` | Fork named branch → new `sceneId` |
| `GET` | `/scene/{sceneId}/disagreement` | Active A/B disagreement or `null` |
| `POST` | `/scene/{sceneId}/disagreement` | Open proposal A |
| `POST` | `/scene/{sceneId}/disagreement/{id}/counter` | Set / replace proposal B |
| `POST` | `/scene/{sceneId}/disagreement/{id}/compromise` | Blend / picks / a / b |
| `POST` | `/scene/{sceneId}/disagreement/{id}/resolve` | Accept A, B, or cancel |
| `POST` | `/ai/layout` | Hybrid planner ops (**not** applied until client Accept) |
| `GET` | `/catalog` | Seed products |
| `POST` | `/commerce/cart/summary` | Cart from scene products |
| `POST` | `/commerce/checkout` | Stripe test Checkout or sandbox stub URL |
| `WS` | `/ws/scene/{sceneId}` | `welcome` / `presence` / `scene` / `patch` / `lock` + voice `rtc_*` + `draw_*` + `intent_*` + `timeline` + `disagreement` — **unlimited presence** |

Web client connects to the WebSocket by default (`apps/web/lib/ws.ts`). Set `NEXT_PUBLIC_SCENE_WS=0` to use HTTP-only.

---

## Repo layout

```text
apps/web          Next.js + R3F digital twin
apps/api          FastAPI scene store, ops, AI stub, catalog, invites
apps/ios          RoomPlan capture + RealityKit viewer + AR ops stub
packages/schema   Shared Zod/TS types + demo seed
```

Web twin pieces:

- `lib/api.ts` / `lib/sceneStore.ts` — fetch, optimistic ops, Accept lerp, undo, intent, invites, timeline, disagreement
- `lib/objectPolicy.ts` — structure vs relocatable existing furniture
- `components/SceneCanvas`, `ObjectGizmo`, `SelectionBar`, `InviteModal`, `IntentModal`, `SidebarShell`, …

---

## Architecture notes

- **Ops-only AI**: planner returns `MOVE_OBJECT` / `ADD_OBJECT` / …; applier + validators own legality.
- **Existing furniture**: validators allow relocate/delete for non-structure objects (including `source: existing`); walls / openings stay fixed.
- **Invites**: in-memory tokens; join URL is enough for demos (no auth gate).
- **Versioning**: every successful envelope increments `version`; clients send `baseVersion`.
- **Timeline**: in-memory append log of scene snapshots for restore / branch demos.
- **Coordinate system**: Y-up meters, origin at floor center (see schema package).

---

## Status

**Working for demo:** web ←→ API scene loop, **invite links (unlimited peers)**, **post-scan Plan with friends**, drag / clear existing furniture, hybrid AI accept/reject, timeline restore/branch, disagreement A/B, catalog/budget, checkout stub/Stripe, WS presence/patch/locks, WebRTC voice mesh + wall drawing + ghost avatars, polished UX chrome, iOS RoomPlan/AR scaffold + Plan this room sheet.

**Optional / later polish:** deep Supabase auth & Realtime channel (local WS is the required path), richer Stripe UX, TURN for cellular voice, iOS WebRTC/AVAudio join + deep-link invite handler.
