"""WebSocket /ws/scene/{sceneId} — presence, scene, voice signaling, drawing."""

from __future__ import annotations

import json

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from ..models import DrawingStroke, PresenceUser
from ..realtime import get_hub
from ..store import get_store

router = APIRouter(tags=['realtime'])


def _parse_presence_user(data: dict, fallback_uid: str | None = None) -> PresenceUser | None:
    user_raw = data.get('user') or {}
    uid = (
        user_raw.get('userId')
        or user_raw.get('user_id')
        or data.get('userId')
        or fallback_uid
    )
    if not uid:
        return None
    return PresenceUser(
        user_id=uid,
        display_name=user_raw.get('displayName')
        or user_raw.get('display_name')
        or uid,
        color=user_raw.get('color'),
        selected_object_id=user_raw.get('selectedObjectId')
        or user_raw.get('selected_object_id'),
        voice_enabled=user_raw.get('voiceEnabled')
        if 'voiceEnabled' in user_raw
        else user_raw.get('voice_enabled'),
        voice_speaking=user_raw.get('voiceSpeaking')
        if 'voiceSpeaking' in user_raw
        else user_raw.get('voice_speaking'),
    )


@router.websocket('/ws/scene/{scene_id}')
async def scene_websocket(websocket: WebSocket, scene_id: str) -> None:
    hub = get_hub()
    store = get_store()

    # Ensure scene exists (404-style close if missing)
    try:
        scene = store.get_scene(scene_id)
    except Exception:
        await websocket.close(code=4404)
        return

    await hub.connect(scene_id, websocket)
    user_id: str | None = None

    await websocket.send_json(
        {
            'type': 'welcome',
            'sceneId': scene_id,
            'version': scene.version,
            'scene': scene.model_dump(by_alias=True),
            'presence': [u.model_dump(by_alias=True) for u in hub.presence_list(scene_id)],
            'strokes': [s.model_dump(by_alias=True) for s in hub.strokes_list(scene_id)],
            'message': 'Connected to in-memory scene channel (voice + drawing enabled).',
        }
    )

    try:
        while True:
            raw = await websocket.receive_text()
            try:
                data = json.loads(raw)
            except json.JSONDecodeError:
                await websocket.send_json({'type': 'error', 'message': 'Invalid JSON'})
                continue

            msg_type = data.get('type')
            if msg_type == 'ping':
                await websocket.send_json({'type': 'pong', 'sceneId': scene_id})
                continue

            if msg_type in ('join', 'presence'):
                user = _parse_presence_user(data, user_id)
                if not user:
                    await websocket.send_json(
                        {'type': 'error', 'message': 'user.userId required'}
                    )
                    continue
                # Preserve voice flags if client omits them on selection-only presence updates
                existing = next(
                    (u for u in hub.presence_list(scene_id) if u.user_id == user.user_id),
                    None,
                )
                if existing:
                    if user.voice_enabled is None:
                        user.voice_enabled = existing.voice_enabled
                    if user.voice_speaking is None:
                        user.voice_speaking = existing.voice_speaking
                user_id = user.user_id
                await hub.upsert_presence(scene_id, user, websocket)
                await hub.broadcast_presence(scene_id)
                continue

            if msg_type == 'leave':
                if user_id:
                    await hub.disconnect(scene_id, websocket, user_id)
                    user_id = None
                continue

            if msg_type == 'lock':
                actor = data.get('actorId') or data.get('actor_id') or user_id
                object_id = data.get('objectId') or data.get('object_id')
                if not actor or not object_id:
                    await websocket.send_json(
                        {'type': 'error', 'message': 'actorId and objectId required'}
                    )
                    continue
                result = store.lock_object(
                    scene_id,
                    object_id=object_id,
                    actor_id=actor,
                    ttl_seconds=data.get('ttlSeconds') or data.get('ttl_seconds'),
                )
                await hub.broadcast(
                    scene_id,
                    {
                        'type': 'lock',
                        'sceneId': scene_id,
                        'payload': result.model_dump(by_alias=True),
                        'scene': result.scene.model_dump(by_alias=True)
                        if result.scene
                        else None,
                    },
                )
                continue

            if msg_type == 'unlock':
                actor = data.get('actorId') or data.get('actor_id') or user_id
                object_id = data.get('objectId') or data.get('object_id')
                if not actor or not object_id:
                    await websocket.send_json(
                        {'type': 'error', 'message': 'actorId and objectId required'}
                    )
                    continue
                result = store.unlock_object(
                    scene_id, object_id=object_id, actor_id=actor
                )
                await hub.broadcast(
                    scene_id,
                    {
                        'type': 'lock',
                        'sceneId': scene_id,
                        'payload': result.model_dump(by_alias=True),
                        'scene': result.scene.model_dump(by_alias=True)
                        if result.scene
                        else None,
                    },
                )
                continue

            # --- WebRTC voice signaling (mesh) ---
            if msg_type in ('rtc_offer', 'rtc_answer', 'rtc_ice'):
                from_uid = (
                    data.get('fromUserId')
                    or data.get('from_user_id')
                    or user_id
                )
                to_uid = data.get('toUserId') or data.get('to_user_id')
                if not from_uid or not to_uid:
                    await websocket.send_json(
                        {
                            'type': 'error',
                            'message': 'fromUserId and toUserId required for RTC',
                        }
                    )
                    continue
                relay = {
                    'type': msg_type,
                    'sceneId': scene_id,
                    'fromUserId': from_uid,
                    'toUserId': to_uid,
                }
                if msg_type in ('rtc_offer', 'rtc_answer'):
                    sdp = data.get('sdp')
                    if not sdp:
                        await websocket.send_json(
                            {'type': 'error', 'message': 'sdp required'}
                        )
                        continue
                    relay['sdp'] = sdp
                else:
                    candidate = data.get('candidate')
                    if candidate is None:
                        await websocket.send_json(
                            {'type': 'error', 'message': 'candidate required'}
                        )
                        continue
                    relay['candidate'] = candidate
                ok = await hub.send_to_user(scene_id, to_uid, relay)
                if not ok:
                    await websocket.send_json(
                        {
                            'type': 'error',
                            'message': f'Peer {to_uid} not connected',
                        }
                    )
                continue

            # --- Spatial whiteboard ---
            if msg_type == 'draw_stroke':
                stroke_raw = data.get('stroke') or data
                try:
                    stroke = DrawingStroke.model_validate(
                        {
                            'strokeId': stroke_raw.get('strokeId')
                            or stroke_raw.get('stroke_id'),
                            'sceneId': stroke_raw.get('sceneId')
                            or stroke_raw.get('scene_id')
                            or scene_id,
                            'actorId': stroke_raw.get('actorId')
                            or stroke_raw.get('actor_id')
                            or user_id,
                            'color': stroke_raw.get('color') or '#6ec8e8',
                            'width': stroke_raw.get('width') or 0.02,
                            'points': stroke_raw.get('points'),
                            'plane': stroke_raw.get('plane'),
                            'createdAt': stroke_raw.get('createdAt')
                            or stroke_raw.get('created_at'),
                        }
                    )
                except Exception as exc:
                    await websocket.send_json(
                        {'type': 'error', 'message': f'Invalid stroke: {exc}'}
                    )
                    continue
                if stroke.scene_id != scene_id:
                    stroke.scene_id = scene_id
                await hub.add_stroke(scene_id, stroke)
                await hub.broadcast(
                    scene_id,
                    {
                        'type': 'draw_stroke',
                        'sceneId': scene_id,
                        'stroke': stroke.model_dump(by_alias=True),
                    },
                )
                continue

            if msg_type == 'draw_clear':
                actor = data.get('actorId') or data.get('actor_id') or user_id
                scope = data.get('scope') or 'own'
                if scope not in ('own', 'all'):
                    await websocket.send_json(
                        {'type': 'error', 'message': 'scope must be own|all'}
                    )
                    continue
                removed = await hub.clear_strokes(
                    scene_id, actor_id=actor, scope=scope
                )
                await hub.broadcast(
                    scene_id,
                    {
                        'type': 'draw_clear',
                        'sceneId': scene_id,
                        'scope': scope,
                        'actorId': actor,
                        'removedStrokeIds': removed,
                        'strokes': [
                            s.model_dump(by_alias=True)
                            for s in hub.strokes_list(scene_id)
                        ],
                    },
                )
                continue

            await websocket.send_json(
                {'type': 'error', 'message': f'Unknown message type: {msg_type}'}
            )
    except WebSocketDisconnect:
        await hub.disconnect(scene_id, websocket, user_id)
