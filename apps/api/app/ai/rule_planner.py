"""Deterministic layout planner for party / study / dinner / movie scenarios."""

from __future__ import annotations

import math
import uuid
from typing import TYPE_CHECKING

from ..models import ConstraintSet, LayoutRequest, LayoutResponse, Scene, SceneOperation
from .classifier import Scenario, classify_scenario
from .value_picker import pick_best_value

if TYPE_CHECKING:
    from ..models import CatalogItem


def _pick(
    catalog: dict[str, CatalogItem],
    *,
    tags: tuple[str, ...] | None = None,
    category: str | None = None,
    max_price: float | None = None,
    include_virtual: bool = False,
) -> CatalogItem | None:
    """Prefer high-rated / low-cost purchasable goods under max_price (budget remaining)."""
    budget = max_price if max_price is not None else float('inf')
    scored = pick_best_value(
        catalog,
        budget_remaining=budget,
        tags=tags,
        category=category,
        prefer_purchasable=not include_virtual,
    )
    return scored.item if scored else None


def _movable(scene: Scene) -> list:
    return [o for o in scene.objects if o.movable is not False and o.type != 'wall']


def _perimeter_positions(
    scene: Scene,
    count: int,
    *,
    y: float = 0.4,
    inset: float = 0.9,
) -> list[list[float]]:
    """Distribute seating along room perimeter, clearing the center."""
    hw = scene.bounds.width / 2 - inset
    hl = scene.bounds.length / 2 - inset
    if count <= 0:
        return []
    # Rectangle path: N, E, S, W edges
    corners = [
        [hw, y, -hl],
        [hw, y, hl],
        [-hw, y, hl],
        [-hw, y, -hl],
    ]
    edge_lengths = [
        abs(corners[1][2] - corners[0][2]),
        abs(corners[2][0] - corners[1][0]),
        abs(corners[3][2] - corners[2][2]),
        abs(corners[0][0] - corners[3][0]),
    ]
    perimeter = sum(edge_lengths) or 1.0
    positions: list[list[float]] = []
    for i in range(count):
        dist = (i + 0.5) / count * perimeter
        acc = 0.0
        for e, length in enumerate(edge_lengths):
            if dist <= acc + length:
                t = (dist - acc) / length if length > 0 else 0
                a, b = corners[e], corners[(e + 1) % 4]
                positions.append(
                    [
                        a[0] + (b[0] - a[0]) * t,
                        y,
                        a[2] + (b[2] - a[2]) * t,
                    ]
                )
                break
            acc += length
    return positions


def _yaw_quat(yaw: float) -> list[float]:
    """Quaternion [x,y,z,w] for yaw around Y."""
    half = yaw / 2
    return [0.0, math.sin(half), 0.0, math.cos(half)]


def _add_product_op(
    product: CatalogItem,
    position: list[float],
    *,
    object_type: str | None = None,
    rotation: list[float] | None = None,
) -> SceneOperation:
    return SceneOperation(
        type='ADD_OBJECT',
        object_id=f'ai_{product.product_id}_{uuid.uuid4().hex[:6]}',
        object_type=object_type or product.category or product.name,
        product_id=product.product_id,
        asset_id=product.asset_id,
        target_position=position,
        target_rotation=rotation or [0, 0, 0, 1],
        dimensions=product.dimensions,
        source='catalog',
        movable=True,
    )


def _push_existing_to_perimeter(scene: Scene, ops: list[SceneOperation]) -> None:
    movable = _movable(scene)
    seats = [o for o in movable if o.type in ('sofa', 'chair', 'seating') or 'sofa' in o.type]
    others = [o for o in movable if o not in seats]
    # Clear center first: park tables/lamps in corners so seating moves don't collide
    corner_slots = [
        [scene.bounds.width / 2 - 0.7, None, scene.bounds.length / 2 - 0.7],
        [-scene.bounds.width / 2 + 0.7, None, scene.bounds.length / 2 - 0.7],
        [scene.bounds.width / 2 - 0.7, None, -scene.bounds.length / 2 + 0.7],
    ]
    for i, obj in enumerate(others):
        if obj.type == 'rug':
            continue
        slot = corner_slots[i % len(corner_slots)]
        ops.append(
            SceneOperation(
                type='MOVE_OBJECT',
                object_id=obj.id,
                target_position=[slot[0], obj.transform.position[1], slot[2]],
            )
        )
    positions = _perimeter_positions(scene, max(len(seats), 1), inset=1.15)
    for i, obj in enumerate(seats):
        pos = positions[i % len(positions)]
        y = obj.transform.position[1]
        target = [pos[0], y, pos[2]]
        yaw = math.atan2(-pos[0], -pos[2])
        ops.append(
            SceneOperation(
                type='MOVE_OBJECT',
                object_id=obj.id,
                target_position=target,
            )
        )
        ops.append(
            SceneOperation(
                type='ROTATE_OBJECT',
                object_id=obj.id,
                target_rotation=_yaw_quat(yaw),
            )
        )


def _plan_party(
    scene: Scene,
    catalog: dict[str, CatalogItem],
    budget: float,
    guest_count: int,
) -> tuple[list[SceneOperation], list[str], str]:
    ops: list[SceneOperation] = []
    warnings: list[str] = []
    spent = 0.0
    _push_existing_to_perimeter(scene, ops)

    remaining = budget - spent
    lights = _pick(catalog, tags=('party', 'lighting'), max_price=remaining)
    if lights:
        ops.append(
            _add_product_op(
                lights,
                [0.0, scene.bounds.height - 0.3, -scene.bounds.length / 2 + 0.4],
                object_type='string_lights',
            )
        )
        spent += lights.price
        remaining = budget - spent

    backdrop = _pick(catalog, tags=('party', 'decor'), max_price=remaining)
    if backdrop and backdrop.product_id != (lights.product_id if lights else None):
        ops.append(
            _add_product_op(
                backdrop,
                [-scene.bounds.width / 2 + 0.5, 1.2, -scene.bounds.length / 2 + 0.35],
                object_type='backdrop',
            )
        )
        spent += backdrop.price
        remaining = budget - spent

    chairs_needed = max(0, min(guest_count // 3, 6))
    chair = _pick(catalog, tags=('seating', 'party'), category='seating', max_price=remaining)
    if chair and chairs_needed:
        perim = _perimeter_positions(scene, chairs_needed, y=0.43, inset=1.1)
        for i, pos in enumerate(perim):
            if spent + chair.price > budget:
                warnings.append(f'Stopped adding chairs at {i}; budget limit')
                break
            # Skip if product already in scene as existing large seating nearby — still add folding chairs
            ops.append(_add_product_op(chair, pos, object_type='chair'))
            spent += chair.price

    rug = _pick(catalog, tags=('party', 'floor'), max_price=budget - spent)
    if rug:
        ops.append(_add_product_op(rug, [0.0, 0.01, 0.0], object_type='rug'))
        spent += rug.price

    summary = (
        f'Party layout: seating to perimeter for {guest_count} guests, clear dance center, '
        f'add lights/backdrop within ${budget:.0f} (planned adds ~${spent:.0f}).'
    )
    return ops, warnings, summary


def _plan_study(
    scene: Scene,
    catalog: dict[str, CatalogItem],
    budget: float,
    guest_count: int,
) -> tuple[list[SceneOperation], list[str], str]:
    ops: list[SceneOperation] = []
    warnings: list[str] = []
    spent = 0.0
    # Push sofa to back wall; clear desk zone near window (positive Z)
    for obj in _movable(scene):
        if obj.type == 'sofa' or 'sofa' in obj.type:
            ops.append(
                SceneOperation(
                    type='MOVE_OBJECT',
                    object_id=obj.id,
                    target_position=[0.0, obj.transform.position[1], -scene.bounds.length / 2 + 1.2],
                )
            )
        elif obj.type == 'table':
            ops.append(
                SceneOperation(
                    type='MOVE_OBJECT',
                    object_id=obj.id,
                    target_position=[0.8, obj.transform.position[1], 1.4],
                )
            )

    desk = _pick(catalog, tags=('desk', 'study', 'table'), category='tables', max_price=budget)
    if desk:
        ops.append(_add_product_op(desk, [-1.2, 0.375, 1.5], object_type='desk'))
        spent += desk.price

    lamp = _pick(catalog, tags=('lighting',), category='lighting', max_price=budget - spent)
    if lamp:
        ops.append(_add_product_op(lamp, [-1.6, 0.86, 1.8], object_type='desk_lamp'))
        spent += lamp.price

    chair = _pick(catalog, tags=('seating',), category='seating', max_price=budget - spent)
    if chair:
        ops.append(_add_product_op(chair, [-1.2, 0.43, 0.9], object_type='chair'))
        spent += chair.price

    plant = _pick(catalog, tags=('decor',), category='decor', max_price=budget - spent)
    if plant:
        ops.append(_add_product_op(plant, [2.0, 0.7, 2.2], object_type='plant'))

    summary = (
        f'Study layout: focus desk zone, sofa against back wall, task lighting '
        f'for {guest_count} within ${budget:.0f}.'
    )
    return ops, warnings, summary


def _plan_dinner(
    scene: Scene,
    catalog: dict[str, CatalogItem],
    budget: float,
    guest_count: int,
) -> tuple[list[SceneOperation], list[str], str]:
    ops: list[SceneOperation] = []
    warnings: list[str] = []
    spent = 0.0
    # Center dining table
    for obj in _movable(scene):
        if obj.type == 'table':
            ops.append(
                SceneOperation(
                    type='MOVE_OBJECT',
                    object_id=obj.id,
                    target_position=[0.0, obj.transform.position[1], 0.0],
                )
            )
        elif obj.type == 'sofa' or 'sofa' in obj.type:
            ops.append(
                SceneOperation(
                    type='MOVE_OBJECT',
                    object_id=obj.id,
                    target_position=[scene.bounds.width / 2 - 1.2, obj.transform.position[1], -1.5],
                )
            )

    table = _pick(catalog, tags=('table', 'dining'), category='tables', max_price=budget)
    # Only add if no table already being centered
    has_table = any(o.type == 'table' for o in scene.objects)
    if table and not has_table:
        ops.append(_add_product_op(table, [0.0, 0.375, 0.0], object_type='dining_table'))
        spent += table.price

    chairs_n = max(2, min(guest_count, 8))
    chair = _pick(catalog, tags=('seating',), category='seating', max_price=budget - spent)
    if chair:
        radius = 1.35
        for i in range(chairs_n):
            if spent + chair.price > budget:
                warnings.append(f'Stopped seating at {i} chairs due to budget')
                break
            angle = 2 * math.pi * i / chairs_n
            pos = [math.cos(angle) * radius, 0.43, math.sin(angle) * radius]
            ops.append(
                _add_product_op(
                    chair,
                    pos,
                    object_type='chair',
                    rotation=_yaw_quat(angle + math.pi),
                )
            )
            spent += chair.price

    light = _pick(catalog, tags=('lighting',), max_price=budget - spent)
    if light:
        ops.append(
            _add_product_op(
                light,
                [0.0, scene.bounds.height - 0.5, 0.0],
                object_type='pendant',
            )
        )

    summary = (
        f'Dinner layout: centered table with surrounding chairs for {guest_count}, '
        f'within ${budget:.0f}.'
    )
    return ops, warnings, summary


def _plan_movie(
    scene: Scene,
    catalog: dict[str, CatalogItem],
    budget: float,
    guest_count: int,
) -> tuple[list[SceneOperation], list[str], str]:
    ops: list[SceneOperation] = []
    warnings: list[str] = []
    spent = 0.0
    # Screen / backdrop on north wall; seating facing it
    for obj in _movable(scene):
        if obj.type == 'sofa' or 'sofa' in obj.type:
            ops.append(
                SceneOperation(
                    type='MOVE_OBJECT',
                    object_id=obj.id,
                    target_position=[0.0, obj.transform.position[1], 1.5],
                )
            )
            ops.append(
                SceneOperation(
                    type='ROTATE_OBJECT',
                    object_id=obj.id,
                    target_rotation=_yaw_quat(math.pi),  # face -Z (screen)
                )
            )
        elif obj.type == 'table':
            ops.append(
                SceneOperation(
                    type='MOVE_OBJECT',
                    object_id=obj.id,
                    target_position=[0.0, obj.transform.position[1], 0.6],
                )
            )

    screen = (
        _pick(catalog, tags=('movie',), category='decor', max_price=budget)
        or _pick(catalog, tags=('movie', 'decor'), max_price=budget)
    )
    if screen:
        ops.append(
            _add_product_op(
                screen,
                [0.0, 1.3, -scene.bounds.length / 2 + 0.25],
                object_type='screen',
            )
        )
        spent += screen.price

    chairs_n = max(0, min(guest_count // 2, 4))
    chair = _pick(catalog, tags=('seating',), category='seating', max_price=budget - spent)
    if chair and chairs_n:
        for i in range(chairs_n):
            if spent + chair.price > budget:
                break
            x = -1.2 + i * 0.8
            ops.append(
                _add_product_op(
                    chair,
                    [x, 0.43, 2.0],
                    object_type='chair',
                    rotation=_yaw_quat(math.pi),
                )
            )
            spent += chair.price

    lamp = _pick(catalog, tags=('lighting',), category='lighting', max_price=budget - spent)
    if lamp and (not screen or lamp.product_id != screen.product_id):
        ops.append(_add_product_op(lamp, [2.0, 0.86, 1.8], object_type='floor_lamp'))

    summary = (
        f'Movie layout: screen on far wall, seating facing it for {guest_count}, '
        f'dim ambient within ${budget:.0f}.'
    )
    return ops, warnings, summary


_PLANNERS = {
    'party': _plan_party,
    'study': _plan_study,
    'dinner': _plan_dinner,
    'movie': _plan_movie,
}


def plan_with_rules(
    scene: Scene,
    request: LayoutRequest,
    catalog: dict[str, CatalogItem],
    *,
    scenario: Scenario | None = None,
) -> LayoutResponse:
    scenario = scenario or classify_scenario(request.prompt)
    budget = request.budget
    guest_count = request.guest_count
    planner = _PLANNERS[scenario]
    ops, warnings, summary = planner(scene, catalog, budget, guest_count)

    constraints = request.constraints or ConstraintSet()
    if constraints.budget is None:
        constraints.budget = budget
    if constraints.guest_count is None:
        constraints.guest_count = guest_count
    if constraints.clear_center is None:
        constraints.clear_center = scenario in ('party', 'dinner')
    if constraints.must_have is None:
        defaults = {
            'party': ['dance_space', 'photo_area'],
            'study': ['desk', 'task_light'],
            'dinner': ['table', 'seating'],
            'movie': ['screen', 'facing_seats'],
        }
        constraints.must_have = defaults.get(scenario)

    return LayoutResponse(
        scenario=scenario,
        reasoning_summary=summary,
        operations=ops,
        constraints=constraints,
        warnings=warnings or None,
    )
