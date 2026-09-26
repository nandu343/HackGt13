"""Realtime / presence / soft-lock / voice / drawing DTOs."""

from __future__ import annotations

from typing import Any, Literal

from pydantic import Field

from .base import CamelModel
from .ops import SceneOperation
from .scene import Scene


class PresenceUser(CamelModel):
    user_id: str
    display_name: str
    color: str | None = None
    selected_object_id: str | None = None
    last_seen_at: str | None = None
    voice_enabled: bool | None = None
    voice_speaking: bool | None = None
    # Ghost avatar standing point + optional facing (Y-up meters)
    position: list[float] | None = None
    look_direction: list[float] | None = None


class DrawingStroke(CamelModel):
    stroke_id: str
    scene_id: str
    actor_id: str
    color: str = '#6ec8e8'
    width: float = 0.02
    points: list[list[float]] = Field(min_length=2)
    plane: Literal['wall', 'floor', 'free'] | None = None
    created_at: str | None = None


class IntentIdea(CamelModel):
    """Short collaborative suggestion for post-scan planning."""

    idea_id: str
    scene_id: str
    actor_id: str
    display_name: str | None = None
    text: str = Field(min_length=1, max_length=280)
    created_at: str | None = None


class IntentDraft(CamelModel):
    """Live shared draft while the group plans the room."""

    actor_id: str | None = None
    display_name: str | None = None
    scenario: str | None = None
    prompt: str | None = None
    guest_count: int | None = None
    budget: float | None = None


class SoftLockRequest(CamelModel):
    object_id: str
    actor_id: str
    ttl_seconds: int | None = Field(default=None, ge=1, le=300)


class SoftLockReleaseRequest(CamelModel):
    object_id: str
    actor_id: str


class SoftLockResult(CamelModel):
    ok: bool
    scene_id: str
    object_id: str
    locked_by: str | None = None
    locked_until: str | None = None
    message: str | None = None
    scene: Scene | None = None


class WsClientMessage(CamelModel):
    type: Literal[
        'join',
        'leave',
        'presence',
        'ping',
        'lock',
        'unlock',
        'rtc_offer',
        'rtc_answer',
        'rtc_ice',
        'draw_stroke',
        'draw_clear',
        'intent_open',
        'intent_close',
        'intent_draft',
        'intent_idea',
    ]
    user: PresenceUser | None = None
    object_id: str | None = None
    actor_id: str | None = None
    ttl_seconds: int | None = None
    stroke: DrawingStroke | None = None
    scope: Literal['own', 'all'] | None = None
    from_user_id: str | None = None
    to_user_id: str | None = None
    sdp: dict[str, Any] | None = None
    candidate: dict[str, Any] | None = None
    draft: IntentDraft | None = None
    idea: IntentIdea | None = None


class WsServerMessage(CamelModel):
    type: Literal[
        'welcome',
        'presence',
        'scene',
        'patch',
        'lock',
        'error',
        'pong',
        'rtc_offer',
        'rtc_answer',
        'rtc_ice',
        'draw_stroke',
        'draw_clear',
        'draw_snapshot',
        'intent_open',
        'intent_close',
        'intent_draft',
        'intent_idea',
        'intent_snapshot',
        'timeline',
        'disagreement',
    ]
    scene_id: str | None = None
    presence: list[PresenceUser] | None = None
    scene: Scene | None = None
    version: int | None = None
    operations: list[SceneOperation] | None = None
    payload: dict[str, Any] | None = None
    message: str | None = None
    strokes: list[DrawingStroke] | None = None
    stroke: DrawingStroke | None = None
    scope: Literal['own', 'all'] | None = None
    actor_id: str | None = None
    from_user_id: str | None = None
    to_user_id: str | None = None
    sdp: dict[str, Any] | None = None
    candidate: dict[str, Any] | None = None
    draft: IntentDraft | None = None
    idea: IntentIdea | None = None
    ideas: list[IntentIdea] | None = None
    intent_open: bool | None = None
    timeline: list[dict[str, Any]] | None = None
    disagreement: dict[str, Any] | None = None
