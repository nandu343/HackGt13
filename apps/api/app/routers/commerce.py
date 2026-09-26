"""Commerce: live cart summary + sandbox checkout (Stripe test or stub)."""

from __future__ import annotations

import uuid
from collections import defaultdict

from fastapi import APIRouter, HTTPException

from ..config import get_settings
from ..models import (
    CartLineItem,
    CartSummary,
    CartSummaryRequest,
    CheckoutRequest,
    CheckoutResponse,
)
from ..seed import catalog_by_id
from ..store import get_store

router = APIRouter(prefix='/commerce', tags=['commerce'])


def _build_cart(scene_id: str, budget: float | None) -> CartSummary:
    scene = get_store().get_scene(scene_id)
    catalog = catalog_by_id()
    counts: dict[str, int] = defaultdict(int)
    for obj in scene.objects:
        if obj.product_id:
            counts[obj.product_id] += 1

    items: list[CartLineItem] = []
    subtotal = 0.0
    purchasable_subtotal = 0.0
    virtual_only_count = 0
    currency = scene.currency or 'USD'

    for product_id, qty in counts.items():
        product = catalog.get(product_id)
        if not product:
            continue
        line = product.price * qty
        subtotal += line
        purchasable = product.purchasable and not product.virtual_only
        if purchasable:
            purchasable_subtotal += line
        else:
            virtual_only_count += qty
        items.append(
            CartLineItem(
                product_id=product_id,
                name=product.name,
                quantity=qty,
                unit_price=product.price,
                line_total=line,
                purchasable=purchasable,
                virtual_only=bool(product.virtual_only),
            )
        )
        currency = product.currency or currency

    remaining = (budget - purchasable_subtotal) if budget is not None else None
    return CartSummary(
        scene_id=scene_id,
        currency=currency,
        items=items,
        subtotal=subtotal,
        purchasable_subtotal=purchasable_subtotal,
        virtual_only_count=virtual_only_count,
        budget=budget,
        remaining=remaining,
    )


@router.post('/cart/summary', response_model=CartSummary)
def cart_summary(payload: CartSummaryRequest) -> CartSummary:
    """Aggregate scene productIds into a live shopping summary."""
    try:
        return _build_cart(payload.scene_id, payload.budget)
    except HTTPException:
        raise


@router.post('/checkout', response_model=CheckoutResponse)
def checkout(payload: CheckoutRequest) -> CheckoutResponse:
    """Create a Stripe test-mode Checkout Session, or a sandbox stub URL.

    Never charges real cards. Only purchasable (non-virtual) items are included.
    """
    try:
        cart = _build_cart(payload.scene_id, None)
    except HTTPException:
        raise

    purchasable = [i for i in cart.items if i.purchasable and not i.virtual_only]
    if not purchasable:
        raise HTTPException(
            status_code=400,
            detail='No purchasable items in scene cart (virtual-only items excluded)',
        )

    amount = sum(i.line_total for i in purchasable)
    settings = get_settings()
    success = payload.success_url or settings.stripe_success_url
    cancel = payload.cancel_url or settings.stripe_cancel_url

    if settings.stripe_secret_key:
        session = _create_stripe_session(
            purchasable,
            currency=cart.currency,
            success_url=success,
            cancel_url=cancel,
            customer_email=payload.customer_email,
            secret_key=settings.stripe_secret_key,
        )
        if session is not None:
            return session

    # Sandbox stub — demo-safe fake checkout page URL
    session_id = f'stub_{uuid.uuid4().hex[:12]}'
    stub_url = (
        f'{success}?checkout=sandbox&session_id={session_id}'
        f'&amount={amount:.2f}&currency={cart.currency}'
    )
    return CheckoutResponse(
        mode='sandbox_stub',
        checkout_url=stub_url,
        session_id=session_id,
        amount_total=amount,
        currency=cart.currency,
        line_item_count=len(purchasable),
        message=(
            'Stripe key not set — returning sandbox stub checkout URL. '
            'Set STRIPE_SECRET_KEY for real test-mode Checkout Sessions.'
        ),
    )


def _create_stripe_session(
    items: list[CartLineItem],
    *,
    currency: str,
    success_url: str,
    cancel_url: str,
    customer_email: str | None,
    secret_key: str,
) -> CheckoutResponse | None:
    try:
        import stripe
    except ImportError:
        return None

    stripe.api_key = secret_key
    line_items = []
    for item in items:
        # Stripe expects unit amounts in the smallest currency unit
        unit_amount = int(round(item.unit_price * 100))
        if unit_amount <= 0:
            continue
        line_items.append(
            {
                'price_data': {
                    'currency': currency.lower(),
                    'product_data': {'name': item.name},
                    'unit_amount': unit_amount,
                },
                'quantity': item.quantity,
            }
        )
    if not line_items:
        return None

    try:
        session = stripe.checkout.Session.create(
            mode='payment',
            line_items=line_items,
            success_url=success_url + ('&' if '?' in success_url else '?') + 'session_id={CHECKOUT_SESSION_ID}',
            cancel_url=cancel_url,
            customer_email=customer_email,
        )
    except Exception:
        return None

    amount_total = (session.amount_total or 0) / 100.0
    return CheckoutResponse(
        mode='stripe_test',
        checkout_url=session.url or success_url,
        session_id=session.id,
        amount_total=amount_total,
        currency=currency,
        line_item_count=len(line_items),
        message='Stripe test-mode Checkout Session created (no live charges).',
    )
