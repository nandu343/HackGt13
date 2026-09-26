"""Bang-for-buck value scorer for catalog picks (high rating, low cost, still good).

Used by the rule planner and as a hybrid post-step when ADD_OBJECT proposes a
productId/assetId — swaps to a better value peer in the same category/tags when
one exists under remaining budget and minRating.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable

from ..models import CatalogItem, SceneOperation, ValuePick

DEFAULT_MIN_RATING = 3.5
_TIER_BOOST = {
    'budget': 1.0,
    'standard': 1.05,
    'premium': 1.08,
}


@dataclass(frozen=True)
class ScoredCandidate:
    item: CatalogItem
    score: float
    reason: str


def effective_rating(item: CatalogItem) -> float:
    """Fall back to a neutral rating when seed data omitted one."""
    if item.rating is not None:
        return float(item.rating)
    # Virtual helpers: treat as unrated junk for shopping ranking.
    if item.virtual_only or not item.purchasable:
        return 0.0
    return 3.8


def bang_for_buck_score(
    item: CatalogItem,
    budget_remaining: float,
    *,
    min_rating: float = DEFAULT_MIN_RATING,
    prefer_purchasable: bool = True,
) -> float | None:
    """Return value score or None if the item is ineligible.

    score ≈ (rating^1.5 / (price+1)) × headroom × purchasable/tier boosts
    so high-rated cheap goods win, junk below min_rating is rejected, and
    picks stay under remaining budget.
    """
    rating = effective_rating(item)
    if rating < min_rating:
        return None

    price = float(item.price)
    if prefer_purchasable and (item.virtual_only or not item.purchasable):
        return None
    if price > budget_remaining + 1e-6:
        return None
    # Free virtuals would dominate if allowed; already filtered above.
    if price <= 0 and (item.virtual_only or not item.purchasable):
        return None

    # Soft preference for leaving budget headroom for later adds.
    denom = max(budget_remaining, 1.0)
    headroom = 1.0 + max(0.0, budget_remaining - price) / denom
    tier = _TIER_BOOST.get(item.quality_tier or 'standard', 1.0)
    purchasable_boost = 1.12 if (item.purchasable and not item.virtual_only) else 0.55

    return (rating**1.5) / (price + 1.0) * headroom * tier * purchasable_boost


def _format_reason(item: CatalogItem, score: float) -> str:
    rating = effective_rating(item)
    tier = item.quality_tier or 'standard'
    return (
        f'Best value: {item.name} ★{rating:.1f} @ ${item.price:.0f} '
        f'({tier}, score {score:.3f})'
    )


def filter_candidates(
    catalog: dict[str, CatalogItem] | Iterable[CatalogItem],
    *,
    tags: Iterable[str] | None = None,
    category: str | None = None,
    exclude_ids: set[str] | None = None,
    prefer_purchasable: bool = True,
) -> list[CatalogItem]:
    items = catalog.values() if isinstance(catalog, dict) else catalog
    tag_set = set(tags) if tags else None
    exclude = exclude_ids or set()
    out: list[CatalogItem] = []
    for item in items:
        if item.product_id in exclude:
            continue
        if prefer_purchasable and (item.virtual_only or not item.purchasable):
            continue
        if category and item.category != category:
            continue
        if tag_set:
            item_tags = set(item.tags or [])
            if not item_tags.intersection(tag_set):
                continue
        out.append(item)
    return out


def rank_candidates(
    candidates: Iterable[CatalogItem],
    budget_remaining: float,
    *,
    min_rating: float = DEFAULT_MIN_RATING,
    prefer_purchasable: bool = True,
) -> list[ScoredCandidate]:
    scored: list[ScoredCandidate] = []
    for item in candidates:
        score = bang_for_buck_score(
            item,
            budget_remaining,
            min_rating=min_rating,
            prefer_purchasable=prefer_purchasable,
        )
        if score is None:
            continue
        scored.append(
            ScoredCandidate(item=item, score=score, reason=_format_reason(item, score))
        )
    scored.sort(key=lambda c: (-c.score, c.item.price, c.item.product_id))
    return scored


def pick_best_value(
    catalog: dict[str, CatalogItem],
    *,
    budget_remaining: float,
    tags: Iterable[str] | None = None,
    category: str | None = None,
    min_rating: float = DEFAULT_MIN_RATING,
    prefer_purchasable: bool = True,
    exclude_ids: set[str] | None = None,
) -> ScoredCandidate | None:
    """Pick the highest bang-for-buck catalog item matching filters."""
    candidates = filter_candidates(
        catalog,
        tags=tags,
        category=category,
        exclude_ids=exclude_ids,
        prefer_purchasable=prefer_purchasable,
    )
    # If tag filter emptied the list, fall back to category-only.
    if not candidates and tags and category:
        candidates = filter_candidates(
            catalog,
            category=category,
            exclude_ids=exclude_ids,
            prefer_purchasable=prefer_purchasable,
        )
    ranked = rank_candidates(
        candidates,
        budget_remaining,
        min_rating=min_rating,
        prefer_purchasable=prefer_purchasable,
    )
    return ranked[0] if ranked else None


def _peer_candidates(
    catalog: dict[str, CatalogItem],
    proposed: CatalogItem,
    *,
    prefer_purchasable: bool,
) -> list[CatalogItem]:
    """Peers for value swaps: same category (never cross-category via ambient tags)."""
    if proposed.category:
        peers = filter_candidates(
            catalog,
            category=proposed.category,
            prefer_purchasable=prefer_purchasable,
        )
    else:
        # No category — use role-ish tags, ignoring ambient scenario tags.
        ambient = {'party', 'movie', 'dining', 'study', 'living', 'virtual', 'helper'}
        role_tags = [t for t in (proposed.tags or []) if t not in ambient]
        peers = filter_candidates(
            catalog,
            tags=role_tags or proposed.tags,
            prefer_purchasable=prefer_purchasable,
        )
    if not peers:
        peers = [proposed]
    elif proposed.product_id not in {p.product_id for p in peers}:
        peers.append(proposed)
    return peers


def apply_value_picks(
    operations: list[SceneOperation],
    catalog: dict[str, CatalogItem],
    budget: float,
    *,
    min_rating: float = DEFAULT_MIN_RATING,
    prefer_purchasable: bool = True,
) -> tuple[list[SceneOperation], list[ValuePick]]:
    """For each ADD_OBJECT with productId/assetId, re-rank peers and swap if better.

    Tracks spend so later adds see remaining budget. Non-ADD ops pass through.
    """
    spent = 0.0
    out: list[SceneOperation] = []
    picks: list[ValuePick] = []

    for op in operations:
        if op.type != 'ADD_OBJECT':
            out.append(op)
            continue

        proposed: CatalogItem | None = None
        if op.product_id and op.product_id in catalog:
            proposed = catalog[op.product_id]
        elif op.asset_id:
            for item in catalog.values():
                if item.asset_id == op.asset_id:
                    proposed = item
                    break

        remaining = max(0.0, budget - spent)
        if proposed is None:
            out.append(op)
            continue

        peers = _peer_candidates(
            catalog, proposed, prefer_purchasable=prefer_purchasable
        )
        ranked = rank_candidates(
            peers,
            remaining,
            min_rating=min_rating,
            prefer_purchasable=prefer_purchasable,
        )

        # If nothing clears min_rating/budget, keep original when it fits budget.
        if not ranked:
            if proposed.price <= remaining + 1e-6:
                out.append(op)
                spent += proposed.price
            # else drop spend-impossible add (postprocess validators also catch)
            else:
                out.append(op)
            continue

        best = ranked[0]
        chosen = best.item
        replaced = (
            proposed.product_id if chosen.product_id != proposed.product_id else None
        )
        if replaced:
            op = op.model_copy(
                update={
                    'product_id': chosen.product_id,
                    'asset_id': chosen.asset_id or op.asset_id,
                    'dimensions': chosen.dimensions or op.dimensions,
                }
            )
            reason = (
                f'Swapped {proposed.name} → {chosen.name}: '
                f'★{effective_rating(chosen):.1f} @ ${chosen.price:.0f} '
                f'beats ★{effective_rating(proposed):.1f} @ ${proposed.price:.0f} '
                f'(score {best.score:.3f})'
            )
        else:
            reason = best.reason

        picks.append(
            ValuePick(
                product_id=chosen.product_id,
                name=chosen.name,
                score=round(best.score, 4),
                reason=reason,
                object_id=op.object_id,
                replaced_product_id=replaced,
                rating=effective_rating(chosen),
                price=chosen.price,
            )
        )
        out.append(op)
        spent += chosen.price

    return out, picks
