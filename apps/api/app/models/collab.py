"""Timeline history + collaborative disagreement / compromise DTOs."""

from __future__ import annotations

from typing import Literal

from pydantic import Field

from .base import CamelModel
from .ops import SceneOperation
from .scene import Scene


class TimelineEntry(CamelModel):
    entry_id: str
    scene_id: str
    version: int
    label: str
    actor_id: str | None = None
    display_name: str | None = None
    branch_id: str = 'main'
    parent_entry_id: str | None = None
    created_at: str
    operations: list[SceneOperation] | None = None
    scene: Scene


class TimelineList(CamelModel):
    scene_id: str
    branch_id: str = 'main'
    entries: list[TimelineEntry] = Field(default_factory=list)


class TimelineRestoreRequest(CamelModel):
    entry_id: str
    actor_id: str
    display_name: str | None = None


class TimelineBranchRequest(CamelModel):
    entry_id: str
    name: str = Field(min_length=1, max_length=48)
    actor_id: str
    display_name: str | None = None


class TimelineBranchResult(CamelModel):
    source_scene_id: str
    branch_id: str
    branch_scene_id: str
    entry: TimelineEntry
    scene: Scene


class DisagreementProposal(CamelModel):
    actor_id: str
    display_name: str | None = None
    label: str | None = None
    operations: list[SceneOperation] = Field(min_length=1)
    scene: Scene | None = None
    created_at: str | None = None


class Disagreement(CamelModel):
    disagreement_id: str
    scene_id: str
    status: Literal['open', 'countered', 'resolved', 'cancelled'] = 'open'
    base_version: int
    base_scene: Scene
    proposal_a: DisagreementProposal
    proposal_b: DisagreementProposal | None = None
    created_at: str
    resolved_at: str | None = None
    resolve_mode: str | None = None


class DisagreementCreateRequest(CamelModel):
    actor_id: str
    display_name: str | None = None
    label: str | None = None
    operations: list[SceneOperation] = Field(min_length=1)
    base_version: int | None = None


class DisagreementCounterRequest(CamelModel):
    actor_id: str
    display_name: str | None = None
    label: str | None = None
    operations: list[SceneOperation] = Field(min_length=1)


class DisagreementCompromiseRequest(CamelModel):
    actor_id: str
    display_name: str | None = None
    mode: Literal['blend', 'picks', 'a', 'b'] = 'blend'
    """picks: objectId -> 'A' | 'B' for conflicting objects."""
    picks: dict[str, Literal['A', 'B']] | None = None


class DisagreementResolveRequest(CamelModel):
    actor_id: str
    choice: Literal['A', 'B', 'cancel']
    display_name: str | None = None
