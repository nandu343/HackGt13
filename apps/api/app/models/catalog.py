from __future__ import annotations

from typing import Literal

from .base import CamelModel
from .ops import SceneOperation
from .scene import Dimensions


class ConstraintSet(CamelModel):
    budget: float | None = None
    guest_count: int | None = None
    must_have: list[str] | None = None
    clear_center: bool | None = None


class LayoutRequest(CamelModel):
    scene_id: str
    prompt: str
    guest_count: int = 15
    budget: float = 150.0
    constraints: ConstraintSet | None = None


class ValuePick(CamelModel):
    """Light rationale for a value-scored ADD_OBJECT product choice."""

    product_id: str
    name: str | None = None
    score: float
    reason: str
    object_id: str | None = None
    replaced_product_id: str | None = None
    rating: float | None = None
    price: float | None = None


class LayoutResponse(CamelModel):
    scenario: str
    reasoning_summary: str
    operations: list[SceneOperation]
    constraints: ConstraintSet
    warnings: list[str] | None = None
    planner_mode: Literal['rules', 'llm'] | None = None
    fixed_ops: int | None = None
    value_picks: list[ValuePick] | None = None


QualityTier = Literal['budget', 'standard', 'premium']


class Product(CamelModel):
    product_id: str
    name: str
    price: float
    currency: str = 'USD'
    dimensions: Dimensions | None = None
    asset_id: str | None = None
    # Public web path to GLB (or USDZ for iOS) e.g. /models/sofa.glb
    model_url: str | None = None
    # Retailer product page — Shop / Recommendations "Open website".
    product_url: str | None = None
    website_url: str | None = None
    tags: list[str] | None = None
    purchasable: bool = True
    virtual_only: bool = False
    # Customer rating 1–5; used by bang-for-buck value scorer.
    rating: float | None = None
    quality_tier: QualityTier | None = None


class CatalogItem(Product):
    category: str | None = None
    thumbnail_url: str | None = None


class CartLineItem(CamelModel):
    product_id: str
    name: str
    quantity: int
    unit_price: float
    line_total: float
    purchasable: bool = True
    virtual_only: bool = False


class CartSummary(CamelModel):
    scene_id: str
    currency: str
    items: list[CartLineItem]
    subtotal: float
    purchasable_subtotal: float | None = None
    virtual_only_count: int | None = None
    budget: float | None = None
    remaining: float | None = None


class CartSummaryRequest(CamelModel):
    scene_id: str
    budget: float | None = None


class CheckoutRequest(CamelModel):
    scene_id: str
    success_url: str | None = None
    cancel_url: str | None = None
    customer_email: str | None = None


class CheckoutResponse(CamelModel):
    mode: str
    checkout_url: str
    session_id: str
    amount_total: float
    currency: str
    line_item_count: int
    message: str | None = None
