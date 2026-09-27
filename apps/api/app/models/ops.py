from __future__ import annotations

from typing import Literal

from pydantic import Field

from .base import CamelModel
from .scene import Dimensions, Scene


OpType = Literal[
    'MOVE_OBJECT',
    'ROTATE_OBJECT',
    'ADD_OBJECT',
    'DELETE_OBJECT',
    'REPLACE_OBJECT',
]


class SceneOperation(CamelModel):
    type: OpType
    object_id: str | None = None
    target_position: list[float] | None = Field(default=None, min_length=3, max_length=3)
    target_rotation: list[float] | None = Field(default=None, min_length=4, max_length=4)
    asset_id: str | None = None
    product_id: str | None = None
    object_type: str | None = None
    dimensions: Dimensions | None = None
    movable: bool | None = None
    source: Literal['existing', 'catalog'] | None = None
    model_url: str | None = None


class OperationEnvelope(CamelModel):
    base_version: int = Field(ge=0)
    actor_id: str | None = None
    op_id: str | None = None
    label: str | None = None
    operations: list[SceneOperation] = Field(min_length=1)


class OperationsResult(CamelModel):
    accepted: bool
    scene_id: str
    version: int
    applied: int
    scene: Scene
    warnings: list[str] | None = None
