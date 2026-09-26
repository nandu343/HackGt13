"""Shared post-process: run spatial validators; drop/fix illegal ops."""

from __future__ import annotations

from ..models import CatalogItem, LayoutResponse, Scene
from ..validators import scene_product_total, validate_operations


def postprocess_layout(
    scene: Scene,
    response: LayoutResponse,
    catalog: dict[str, CatalogItem],
) -> LayoutResponse:
    """Validate proposed ops; keep clamped/legal subset; attach fix warnings.

    AI `budget` is treated as an *incremental* shopping allowance on top of the
    scene's current product total (existing furniture already in the room).
    """
    original_count = len(response.operations)
    incremental = response.constraints.budget
    existing_total = scene_product_total(scene, catalog)
    budget_ceiling = (
        existing_total + incremental if incremental is not None else None
    )
    result = validate_operations(
        scene,
        response.operations,
        budget_ceiling=budget_ceiling,
        catalog=catalog,
    )

    warnings = list(response.warnings or [])
    warnings.extend(result.warnings)
    clamped = False

    if result.ok:
        cleaned = result.clamped_ops
        if result.warnings:
            clamped = True
            warnings.append('Some ops were auto-clamped to room bounds.')
    else:
        # Drop illegal ops by validating one-at-a-time and keeping survivors
        cleaned = []
        dropped: list[str] = []
        working_ops: list = []
        for op in response.operations:
            trial = working_ops + [op]
            trial_result = validate_operations(
                scene,
                trial,
                budget_ceiling=budget_ceiling,
                catalog=catalog,
            )
            if trial_result.ok:
                working_ops = trial_result.clamped_ops
                cleaned = working_ops
                if trial_result.warnings:
                    clamped = True
                warnings.extend(
                    w for w in trial_result.warnings if w not in warnings
                )
            else:
                reason = trial_result.errors[0] if trial_result.errors else 'invalid'
                dropped.append(f'Dropped {op.type} ({op.object_id}): {reason}')

        warnings.extend(dropped)
        if dropped:
            warnings.append(
                f'Auto-fixed layout: kept {len(cleaned)}/{original_count} ops.'
            )

    dropped_count = max(0, original_count - len(cleaned))
    fixed_ops = dropped_count + (1 if clamped and dropped_count == 0 else 0)
    if response.fixed_ops:
        fixed_ops = max(fixed_ops, response.fixed_ops)

    # Deduplicate warnings while preserving order
    seen: set[str] = set()
    unique_warnings: list[str] = []
    for w in warnings:
        if w not in seen:
            seen.add(w)
            unique_warnings.append(w)

    return LayoutResponse(
        scenario=response.scenario,
        reasoning_summary=response.reasoning_summary,
        operations=cleaned,
        constraints=response.constraints,
        warnings=unique_warnings or None,
        planner_mode=response.planner_mode,
        fixed_ops=fixed_ops or None,
    )
