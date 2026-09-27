"""Deterministic scene operation applier."""

from __future__ import annotations

import uuid

from .models import Scene, SceneObject, SceneOperation, Transform
from .seed import catalog_by_id
from .validators import clamp_position_to_bounds, scene_product_total, validate_operations


class OpApplyError(Exception):
    def __init__(self, message: str, *, errors: list[str] | None = None):
        super().__init__(message)
        self.errors = errors or [message]


def apply_operations(
    scene: Scene,
    operations: list[SceneOperation],
    *,
    budget_ceiling: float | None = None,
    validate: bool = True,
) -> tuple[Scene, list[str]]:
    """
    Validate (optional) then apply operations to a deep copy of the scene.
    Returns (new_scene, warnings). Does not bump version — caller / store does.
    """
    warnings: list[str] = []
    ops = operations

    if validate:
        result = validate_operations(scene, operations, budget_ceiling=budget_ceiling)
        if not result.ok:
            raise OpApplyError('; '.join(result.errors), errors=result.errors)
        warnings = list(result.warnings)
        ops = result.clamped_ops

    working = scene.model_copy(deep=True)
    objects = {o.id: o for o in working.objects}
    catalog = catalog_by_id()

    for op in ops:
        if op.type == 'MOVE_OBJECT':
            assert op.object_id and op.target_position
            obj = objects[op.object_id]
            obj.transform.position = list(op.target_position)

        elif op.type == 'ROTATE_OBJECT':
            assert op.object_id and op.target_rotation
            obj = objects[op.object_id]
            obj.transform.rotation = list(op.target_rotation)

        elif op.type == 'DELETE_OBJECT':
            assert op.object_id
            del objects[op.object_id]

        elif op.type == 'REPLACE_OBJECT':
            assert op.object_id
            obj = objects[op.object_id]
            if op.product_id and op.product_id in catalog:
                item = catalog[op.product_id]
                obj.product_id = item.product_id
                obj.asset_id = item.asset_id
                obj.model_url = item.model_url or obj.model_url
                if item.dimensions:
                    obj.dimensions = item.dimensions.model_copy(deep=True)
            if op.asset_id:
                obj.asset_id = op.asset_id
            if op.model_url:
                obj.model_url = op.model_url

        elif op.type == 'ADD_OBJECT':
            new_id = op.object_id or f'obj_{uuid.uuid4().hex[:8]}'
            product = catalog.get(op.product_id) if op.product_id else None
            dims = op.dimensions or (product.dimensions if product else None)
            position = list(op.target_position or [0, 0, 0])
            dims_tuple = (
                (dims.width or 0.5, dims.height or 0.5, dims.depth or 0.5)
                if dims
                else (0.5, 0.5, 0.5)
            )
            clamped, _ = clamp_position_to_bounds(position, working, dims_tuple)
            model_url = op.model_url or (product.model_url if product else None)
            if not model_url:
                from .model_assets import resolve_model_url

                model_url = resolve_model_url(
                    asset_id=op.asset_id or (product.asset_id if product else None),
                    product_id=op.product_id or (product.product_id if product else None),
                )
            objects[new_id] = SceneObject(
                id=new_id,
                type=op.object_type or (product.name if product else 'object'),
                source=op.source or 'catalog',
                movable=True if op.movable is None else op.movable,
                transform=Transform(
                    position=list(clamped),
                    rotation=list(op.target_rotation or [0, 0, 0, 1]),
                    scale=[1, 1, 1],
                ),
                dimensions=dims,
                product_id=op.product_id or (product.product_id if product else None),
                asset_id=op.asset_id or (product.asset_id if product else None),
                model_url=model_url,
            )

    working.objects = list(objects.values())
    working.budget_used = scene_product_total(working, catalog)
    return working, warnings
