"""In-memory WebSocket hub for scene presence + broadcast.

Local fallback when Supabase Realtime is not configured. Required for demo.
Also relays WebRTC voice signaling and ephemeral drawing strokes.
"""

from __future__ import annotations

import asyncio
import json
import threading
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any

from fastapi import WebSocket

from ..models import DrawingStroke, PresenceUser, Scene, SceneOperation

MAX_STROKES_PER_SCENE = 200


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')


@dataclass
class SceneRoom:
    scene_id: str
    sockets: set[WebSocket] = field(default_factory=set)
    presence: dict[str, PresenceUser] = field(default_factory=dict)
    # user_id -> websocket (for targeted RTC signaling)
    user_sockets: dict[str, WebSocket] = field(default_factory=dict)
    strokes: dict[str, DrawingStroke] = field(default_factory=dict)
    lock: asyncio.Lock = field(default_factory=asyncio.Lock)


class SceneHub:
    def __init__(self) -> None:
        self._rooms: dict[str, SceneRoom] = {}
        self._guard = threading.RLock()

    def _room(self, scene_id: str) -> SceneRoom:
        with self._guard:
            if scene_id not in self._rooms:
                self._rooms[scene_id] = SceneRoom(scene_id=scene_id)
            return self._rooms[scene_id]

    async def connect(self, scene_id: str, websocket: WebSocket) -> SceneRoom:
        await websocket.accept()
        room = self._room(scene_id)
        async with room.lock:
            room.sockets.add(websocket)
        return room

    async def disconnect(self, scene_id: str, websocket: WebSocket, user_id: str | None) -> None:
        room = self._room(scene_id)
        async with room.lock:
            room.sockets.discard(websocket)
            if user_id and user_id in room.presence:
                del room.presence[user_id]
            if user_id and room.user_sockets.get(user_id) is websocket:
                del room.user_sockets[user_id]
        await self.broadcast_presence(scene_id)

    async def upsert_presence(self, scene_id: str, user: PresenceUser, websocket: WebSocket | None = None) -> list[PresenceUser]:
        room = self._room(scene_id)
        user.last_seen_at = user.last_seen_at or _utc_now_iso()
        async with room.lock:
            room.presence[user.user_id] = user
            if websocket is not None:
                room.user_sockets[user.user_id] = websocket
            snapshot = list(room.presence.values())
        return snapshot

    def presence_list(self, scene_id: str) -> list[PresenceUser]:
        room = self._room(scene_id)
        return list(room.presence.values())

    def strokes_list(self, scene_id: str) -> list[DrawingStroke]:
        room = self._room(scene_id)
        return list(room.strokes.values())

    async def add_stroke(self, scene_id: str, stroke: DrawingStroke) -> DrawingStroke:
        room = self._room(scene_id)
        stroke.created_at = stroke.created_at or _utc_now_iso()
        async with room.lock:
            room.strokes[stroke.stroke_id] = stroke
            # Cap memory for hackathon demos
            if len(room.strokes) > MAX_STROKES_PER_SCENE:
                ordered = sorted(
                    room.strokes.values(),
                    key=lambda s: s.created_at or '',
                )
                for old in ordered[: len(room.strokes) - MAX_STROKES_PER_SCENE]:
                    room.strokes.pop(old.stroke_id, None)
        return stroke

    async def clear_strokes(
        self, scene_id: str, *, actor_id: str | None, scope: str
    ) -> list[str]:
        room = self._room(scene_id)
        removed: list[str] = []
        async with room.lock:
            if scope == 'all':
                removed = list(room.strokes.keys())
                room.strokes.clear()
            elif actor_id:
                for sid, stroke in list(room.strokes.items()):
                    if stroke.actor_id == actor_id:
                        del room.strokes[sid]
                        removed.append(sid)
        return removed

    async def broadcast(self, scene_id: str, message: dict[str, Any]) -> None:
        room = self._room(scene_id)
        async with room.lock:
            sockets = list(room.sockets)
        dead: list[WebSocket] = []
        payload = json.dumps(message)
        for ws in sockets:
            try:
                await ws.send_text(payload)
            except Exception:
                dead.append(ws)
        if dead:
            async with room.lock:
                for ws in dead:
                    room.sockets.discard(ws)

    async def send_to_user(
        self, scene_id: str, user_id: str, message: dict[str, Any]
    ) -> bool:
        room = self._room(scene_id)
        async with room.lock:
            ws = room.user_sockets.get(user_id)
        if ws is None:
            return False
        try:
            await ws.send_text(json.dumps(message))
            return True
        except Exception:
            return False

    async def broadcast_presence(self, scene_id: str) -> None:
        users = self.presence_list(scene_id)
        await self.broadcast(
            scene_id,
            {
                'type': 'presence',
                'sceneId': scene_id,
                'presence': [u.model_dump(by_alias=True) for u in users],
            },
        )

    async def broadcast_scene(self, scene: Scene) -> None:
        await self.broadcast(
            scene.scene_id,
            {
                'type': 'scene',
                'sceneId': scene.scene_id,
                'version': scene.version,
                'scene': scene.model_dump(by_alias=True),
            },
        )

    async def broadcast_patch(
        self,
        scene: Scene,
        operations: list[SceneOperation],
        *,
        from_version: int,
    ) -> None:
        await self.broadcast(
            scene.scene_id,
            {
                'type': 'patch',
                'sceneId': scene.scene_id,
                'fromVersion': from_version,
                'toVersion': scene.version,
                'version': scene.version,
                'operations': [o.model_dump(by_alias=True) for o in operations],
                'scene': scene.model_dump(by_alias=True),
            },
        )


_hub: SceneHub | None = None


def get_hub() -> SceneHub:
    global _hub
    if _hub is None:
        _hub = SceneHub()
    return _hub
