from __future__ import annotations

from typing import Literal

from pydantic import Field

from .base import CamelModel


class Transform(CamelModel):
    position: list[float] = Field(min_length=3, max_length=3)
    rotation: list[float] = Field(min_length=4, max_length=4)
    scale: list[float] | None = Field(default=None, min_length=3, max_length=3)


class Dimensions(CamelModel):
    width: float | None = None
    height: float | None = None
    depth: float | None = None


class SceneObject(CamelModel):
    id: str
    type: str
    source: Literal['existing', 'catalog'] | None = None
    movable: bool | None = True
    transform: Transform
    dimensions: Dimensions | None = None
    product_id: str | None = None
    asset_id: str | None = None
    locked_by: str | None = None
    locked_until: str | None = None


class RoomBounds(CamelModel):
    width: float
    length: float
    height: float


class Scene(CamelModel):
    scene_id: str
    room_id: str | None = None
    version: int = 0
    bounds: RoomBounds
    objects: list[SceneObject] = Field(default_factory=list)
    budget_used: float | None = 0.0
    currency: str | None = 'USD'
