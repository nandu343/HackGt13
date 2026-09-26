"""Shareable scene invite tokens — unlimited joiners per scene."""

from __future__ import annotations

from .base import CamelModel


class SceneInvite(CamelModel):
    token: str
    scene_id: str
    created_at: str
    created_by: str | None = None
    label: str | None = None


class SceneInviteCreateRequest(CamelModel):
    actor_id: str | None = None
    label: str | None = None


class SceneInviteList(CamelModel):
    scene_id: str
    invites: list[SceneInvite]


class SceneInviteResolve(CamelModel):
    token: str
    scene_id: str
    # Relative web join path, e.g. `/?scene=…&invite=TOKEN`.
    join_path: str
