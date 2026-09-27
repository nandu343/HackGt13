"""Shared post-process: value-rank ADD_OBJECT picks, then spatial validators."""

from __future__ import annotations

from ..models import CatalogItem, LayoutResponse, Scene
from ..validators import scene_product_total, validate_operations
from .value_picker import apply_value_picks


def postprocess_layout(
    scene: Scene,
    response: LayoutResponse,
    catalog: dict[str, CatalogItem],
) -> LayoutResponse:
    """Value-score ADD_OBJECT products, then validate/clamp ops.

    AI `budget` is treated as an *incremental* shopping allowance on top of the
    scene's current product total (existing furniture already in the room).
    """
    incremental = response.constraints.budget
    shopping_budget = incremental if incremental is not None else float('inf')

    # Hybrid path: re-rank ADD_OBJECT productId/assetId peers for bang-for-buck.
    value_ops, value_picks = apply_value_picks(
        response.operations,
        catalog,
        shopping_budget,
        prefer_purchasable=True,
    )
    response = response.model_copy(
        update={
            'operations': value_ops,
            'value_picks': value_picks or None,
        }
    )

    original_count = len(response.operations)
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

    # Keep value_picks tied to surviving ADD_OBJECT ops (prefer object_id match).
    kept_object_ids = {
        op.object_id for op in cleaned if op.type == 'ADD_OBJECT' and op.object_id
    }
    kept_product_ids = {
        op.product_id for op in cleaned if op.type == 'ADD_OBJECT' and op.product_id
    }
    surviving_picks = []
    for vp in response.value_picks or []:
        if vp.object_id:
            if vp.object_id in kept_object_ids:
                surviving_picks.append(vp)
        elif vp.product_id in kept_product_ids:
            surviving_picks.append(vp)
    if surviving_picks:
        warnings.append(
            f'Value picks: {", ".join(vp.product_id for vp in surviving_picks[:4])}'
            + ('…' if len(surviving_picks) > 4 else '')
        )

    # Attach modelUrl from catalog onto ADD_OBJECT ops so clients render GLB/USDZ meshes.
    # Prefer generated lookalike under /media/meshes when available.
    from ..model_assets import resolve_model_url
    from ..mesh import ensure_product_mesh

    hydrated = []
    for op in cleaned:
        if op.type == 'ADD_OBJECT':
            product = catalog.get(op.product_id) if op.product_id else None
            url = (
                op.model_url
                or (product.model_url if product else None)
                or resolve_model_url(asset_id=op.asset_id, product_id=op.product_id)
            )
            if product is not None:
                try:
                    mesh = ensure_product_mesh(product)
                    # Prefer USDZ for AR clients, else generated GLB, else catalog URL.
                    url = mesh.model_url_usdz or mesh.model_url_glb or url
                except Exception:
                    pass
            if url and op.model_url != url:
                op = op.model_copy(update={'model_url': url})
            if product and not op.asset_id and product.asset_id:
                op = op.model_copy(update={'asset_id': product.asset_id})
        hydrated.append(op)
    cleaned = hydrated

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
        value_picks=surviving_picks or None,
    )
