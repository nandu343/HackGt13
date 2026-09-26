# Auth, projects, and realtime (Phase 5)

Local demos do **not** need Supabase. Use the FastAPI in-memory store and:

```text
WS  /ws/scene/{sceneId}
```

## When Supabase env is set

| Variable | Purpose |
|----------|---------|
| `SUPABASE_URL` | Project URL |
| `SUPABASE_SERVICE_KEY` | Service role for API persistence |
| `SUPABASE_DB_URL` | Optional direct Postgres URL |
| `SCENE_STORE=supabase` | Opt into Postgres-backed scenes |
| `NEXT_PUBLIC_SUPABASE_URL` | Web client |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Web anon key |

Apply SQL:

1. `apps/api/migrations/001_init.sql`
2. `apps/api/migrations/002_auth_realtime.sql`

Enable Realtime on `scenes` (and optionally `scene_objects`) in the Dashboard.

## Auth flows (hackathon)

### Anonymous demo user

```ts
const { data, error } = await supabase.auth.signInAnonymously();
// data.user.id → actorId for ops + presence
```

Enable **Anonymous** under Authentication → Providers.

### Magic link

```ts
await supabase.auth.signInWithOtp({
  email,
  options: { emailRedirectTo: 'http://localhost:3000' },
});
```

Enable **Email** magic link; add `http://localhost:3000/**` to redirect URLs.

## Projects

- Table `projects` + `project_members` (see migration).
- Each project references one `scenes.scene_id`.
- Seed scene `scene_party_001` stays public (`project_id` null) for judges.

## Soft locks

- Object fields: `lockedBy`, `lockedUntil` (ISO UTC).
- REST: `POST /scene/{id}/locks` and `POST /scene/{id}/locks/release`
- Also via WS messages `{ type: "lock"|"unlock", objectId, actorId }`
- Default TTL: `LOCK_TTL_SECONDS` (30). Ops from another actor get `409`.

## Realtime channel (Supabase)

```ts
const channel = supabase.channel(`scene:${sceneId}`, {
  config: { presence: { key: userId } },
});
channel
  .on('postgres_changes', { event: '*', schema: 'public', table: 'scenes', filter: `scene_id=eq.${sceneId}` }, handler)
  .on('presence', { event: 'sync' }, () => { /* avatars */ })
  .subscribe(async (status) => {
    if (status === 'SUBSCRIBED') await channel.track({ userId, displayName, selectedObjectId });
  });
```

## WebSocket fallback (required local path)

```ts
const ws = new WebSocket(`ws://localhost:8000/ws/scene/${sceneId}`);
ws.onmessage = (e) => {
  const msg = JSON.parse(e.data);
  // welcome | presence | scene | patch | lock | pong | error
  // rtc_offer | rtc_answer | rtc_ice | draw_stroke | draw_clear
};
ws.send(JSON.stringify({
  type: 'join',
  user: {
    userId: 'u1',
    displayName: 'Ada',
    color: '#5b8',
    voiceEnabled: false,
    voiceSpeaking: false,
  },
}));
```

After `POST /scene/.../operations`, connected clients receive a `patch` (and full `scene`) broadcast from the API hub.

### Voice signaling (WebRTC mesh)

Media is peer-to-peer; the hub only relays:

```json
{ "type": "rtc_offer", "fromUserId": "a", "toUserId": "b", "sdp": { "type": "offer", "sdp": "..." } }
{ "type": "rtc_answer", "fromUserId": "b", "toUserId": "a", "sdp": { "type": "answer", "sdp": "..." } }
{ "type": "rtc_ice", "fromUserId": "a", "toUserId": "b", "candidate": { "candidate": "...", "sdpMid": "0", "sdpMLineIndex": 0 } }
```

Offerer = lexicographically smaller `userId`. Presence `voiceEnabled` / `voiceSpeaking` drive UI + mesh membership.

### Drawing strokes

```json
{
  "type": "draw_stroke",
  "stroke": {
    "strokeId": "stroke_…",
    "sceneId": "scene_party_001",
    "actorId": "web_abc",
    "color": "#e2b45c",
    "width": 0.025,
    "points": [[0, 1.2, -2.5], [0.3, 1.4, -2.5]],
    "plane": "wall"
  }
}
{ "type": "draw_clear", "actorId": "web_abc", "scope": "own" }
```

`welcome.strokes` is the in-memory snapshot (capped). Coordinates: Y-up meters, same as the scene graph.
