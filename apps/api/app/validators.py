"""Spatial validators applied before ops mutate a scene."""

from __future__ import annotations

from dataclasses import dataclass, field

from .models import CatalogItem, Scene, SceneObject, SceneOperation
from .seed import catalog_by_id


@dataclass
class ValidationResult:
    ok: bool = True
    errors: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)
    clamped_ops: list[SceneOperation] = field(default_factory=list)

    def fail(self, message: str) -> None:
        self.ok = False
        self.errors.append(message)


def _dims(obj: SceneObject) -> tuple[float, float, float]:
    d = obj.dimensions
    if not d:
        return 0.5, 0.5, 0.5
    return (
        d.width or 0.5,
        d.height or 0.5,
        d.depth or 0.5,
    )


def aabb(obj: SceneObject) -> tuple[float, float, float, float, float, float]:
    """Return (min_x, min_y, min_z, max_x, max_y, max_z) for an object."""
    w, h, depth = _dims(obj)
    x, y, z = obj.transform.position
    hx, hy, hz = w / 2, h / 2, depth / 2
    return x - hx, y - hy, z - hz, x + hx, y + hy, z + hz


def aabbs_overlap(
    a: tuple[float, float, float, float, float, float],
    b: tuple[float, float, float, float, float, float],
    epsilon: float = 1e-4,
) -> bool:
    return not (
        a[3] <= b[0] + epsilon
        or b[3] <= a[0] + epsilon
        or a[4] <= b[1] + epsilon
        or b[4] <= a[1] + epsilon
        or a[5] <= b[2] + epsilon
        or b[5] <= a[2] + epsilon
    )


def clamp_position_to_bounds(
    position: list[float],
    scene: Scene,
    dimensions: tuple[float, float, float] | None = None,
) -> tuple[list[float], bool]:
    """Clamp XZ (and Y) so the object's AABB stays inside room bounds."""
    w, length, height = scene.bounds.width, scene.bounds.length, scene.bounds.height
    hx = (dimensions[0] if dimensions else 0.0) / 2
    hz = (dimensions[2] if dimensions else 0.0) / 2
    hy = (dimensions[1] if dimensions else 0.0) / 2

    x, y, z = position[0], position[1], position[2]
    max_x = w / 2 - hx
    max_z = length / 2 - hz
    clamped = [
        max(-max_x, min(max_x, x)),
        max(hy, min(height - hy, y)) if dimensions else max(0.0, min(height, y)),
        max(-max_z, min(max_z, z)),
    ]
    changed = any(abs(clamped[i] - position[i]) > 1e-6 for i in range(3))
    return clamped, changed


def is_immovable(obj: SceneObject) -> bool:
    return obj.movable is False


def scene_product_total(scene: Scene, catalog: dict[str, CatalogItem] | None = None) -> float:
    prices = catalog or catalog_by_id()
    total = 0.0
    for obj in scene.objects:
        if not obj.product_id:
            continue
        item = prices.get(obj.product_id)
        if item:
            total += item.price
    return total


def validate_operations(
    scene: Scene,
    operations: list[SceneOperation],
    *,
    budget_ceiling: float | None = None,
    catalog: dict[str, CatalogItem] | None = None,
) -> ValidationResult:
    """Validate ops against a working copy of the scene (does not mutate input)."""
    result = ValidationResult()
    working = scene.model_copy(deep=True)
    objects = {o.id: o for o in working.objects}
    prices = catalog or catalog_by_id()
    result.clamped_ops = []

    for op in operations:
        patched = op.model_copy(deep=True)

        if op.type == 'MOVE_OBJECT':
            if not op.object_id or op.object_id not in objects:
                result.fail(f'MOVE_OBJECT: unknown objectId {op.object_id}')
                continue
            obj = objects[op.object_id]
            if is_immovable(obj):
                result.fail(f'MOVE_OBJECT: object {op.object_id} is immovable')
                continue
            if not op.target_position:
                result.fail(f'MOVE_OBJECT: targetPosition required for {op.object_id}')
                continue
            clamped, changed = clamp_position_to_bounds(
                list(op.target_position), working, _dims(obj)
            )
            if changed:
                result.warnings.append(f'Clamped position for {op.object_id} to room bounds')
                patched.target_position = clamped
            obj.transform.position = list(clamped)

        elif op.type == 'ROTATE_OBJECT':
            if not op.object_id or op.object_id not in objects:
                result.fail(f'ROTATE_OBJECT: unknown objectId {op.object_id}')
                continue
            obj = objects[op.object_id]
            if is_immovable(obj):
                result.fail(f'ROTATE_OBJECT: object {op.object_id} is immovable')
                continue
            if not op.target_rotation:
                result.fail(f'ROTATE_OBJECT: targetRotation required for {op.object_id}')
                continue
            obj.transform.rotation = list(op.target_rotation)

        elif op.type == 'DELETE_OBJECT':
            if not op.object_id or op.object_id not in objects:
                result.fail(f'DELETE_OBJECT: unknown objectId {op.object_id}')
                continue
            obj = objects[op.object_id]
            if is_immovable(obj):
                result.fail(f'DELETE_OBJECT: object {op.object_id} is immovable')
                continue
            del objects[op.object_id]
            working.objects = list(objects.values())

        elif op.type == 'REPLACE_OBJECT':
            if not op.object_id or op.object_id not in objects:
                result.fail(f'REPLACE_OBJECT: unknown objectId {op.object_id}')
                continue
            obj = objects[op.object_id]
            if is_immovable(obj):
                result.fail(f'REPLACE_OBJECT: object {op.object_id} is immovable')
                continue
            if op.product_id:
                item = prices.get(op.product_id)
                if item:
                    obj.product_id = item.product_id
                    obj.asset_id = item.asset_id
                    if item.dimensions:
                        obj.dimensions = item.dimensions.model_copy(deep=True)
            if op.asset_id:
                obj.asset_id = op.asset_id

        elif op.type == 'ADD_OBJECT':
            new_id = op.object_id or f'obj_{len(objects) + 1}'
            if new_id in objects:
                result.fail(f'ADD_OBJECT: objectId {new_id} already exists')
                continue
            position = list(op.target_position or [0, 0, 0])
            dims_model = op.dimensions
            product = prices.get(op.product_id) if op.product_id else None
            if product and product.dimensions and not dims_model:
                dims_model = product.dimensions
            dims_tuple = (
                (dims_model.width or 0.5, dims_model.height or 0.5, dims_model.depth or 0.5)
                if dims_model
                else (0.5, 0.5, 0.5)
            )
            clamped, changed = clamp_position_to_bounds(position, working, dims_tuple)
            if changed:
                result.warnings.append(f'Clamped position for new object {new_id} to room bounds')
                patched.target_position = clamped
                patched.object_id = new_id
            else:
                patched.object_id = new_id
            from .models import Transform

            new_obj = SceneObject(
                id=new_id,
                type=op.object_type or (product.name if product else 'object'),
                source=op.source or 'catalog',
                movable=True if op.movable is None else op.movable,
                transform=Transform(
                    position=list(clamped),
                    rotation=list(op.target_rotation or [0, 0, 0, 1]),
                    scale=[1, 1, 1],
                ),
                dimensions=dims_model,
                product_id=op.product_id or (product.product_id if product else None),
                asset_id=op.asset_id or (product.asset_id if product else None),
            )
            objects[new_id] = new_obj
            working.objects = list(objects.values())

        else:
            result.fail(f'Unsupported operation type: {op.type}')
            continue

        result.clamped_ops.append(patched)

    # AABB collision among movable / all non-wall objects after simulated apply
    ids = list(objects.keys())
    for i, id_a in enumerate(ids):
        a = objects[id_a]
        if a.type == 'wall':
            continue
        box_a = aabb(a)
        for id_b in ids[i + 1 :]:
            b = objects[id_b]
            if b.type == 'wall':
                continue
            if aabbs_overlap(box_a, aabb(b)):
                result.fail(f'AABB collision between {id_a} and {id_b}')

    total = scene_product_total(working, prices)
    working.budget_used = total
    if budget_ceiling is not None and total > budget_ceiling + 1e-6:
        result.fail(
            f'Budget exceeded: scene total {total:.2f} > ceiling {budget_ceiling:.2f}'
        )

    return result
