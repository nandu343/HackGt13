"""Canonical demo scene + catalog mirrored from packages/schema/src/seed.ts."""

from __future__ import annotations

from copy import deepcopy
from typing import Literal

from .models import CatalogItem, Dimensions, RoomBounds, Scene, SceneObject, Transform

QualityTier = Literal['budget', 'standard', 'premium']


def _obj(
    *,
    id: str,
    type: str,
    position: list[float],
    rotation: list[float] | None = None,
    scale: list[float] | None = None,
    dimensions: dict[str, float] | None = None,
    source: str | None = None,
    movable: bool = True,
    product_id: str | None = None,
    asset_id: str | None = None,
) -> SceneObject:
    return SceneObject(
        id=id,
        type=type,
        source=source,  # type: ignore[arg-type]
        movable=movable,
        transform=Transform(
            position=position,
            rotation=rotation or [0, 0, 0, 1],
            scale=scale or [1, 1, 1],
        ),
        dimensions=Dimensions(**dimensions) if dimensions else None,
        product_id=product_id,
        asset_id=asset_id,
    )


def build_demo_scene() -> Scene:
    scene = Scene(
        scene_id='scene_party_001',
        room_id='room_001',
        version=1,
        bounds=RoomBounds(width=5.42, length=6.31, height=2.68),
        objects=[
            _obj(
                id='sofa_1',
                type='sofa',
                source='existing',
                movable=True,
                position=[1.2, 0.41, -1.4],
                rotation=[0, 0.707, 0, 0.707],
                dimensions={'width': 2.1, 'height': 0.82, 'depth': 0.91},
                product_id='product_sofa_01',
            ),
            _obj(
                id='lamp_17',
                type='floor_lamp',
                source='catalog',
                movable=True,
                position=[-1.62, 0.86, 2.1],
                asset_id='asset_lamp_12',
                product_id='product_39',
                dimensions={'width': 0.4, 'height': 1.72, 'depth': 0.4},
            ),
            _obj(
                id='table_05',
                type='table',
                source='catalog',
                movable=True,
                position=[1.5, 0.375, 0.2],
                product_id='product_table_05',
                dimensions={'width': 1.4, 'height': 0.75, 'depth': 1.1},
            ),
            _obj(
                id='wall_north',
                type='wall',
                source='existing',
                movable=False,
                position=[0, 1.34, -3.155],
                dimensions={'width': 5.42, 'height': 2.68, 'depth': 0.12},
            ),
        ],
        budget_used=0.0,
        currency='USD',
    )
    return scene


def _item(
    product_id: str,
    name: str,
    price: float,
    *,
    width: float,
    height: float,
    depth: float,
    asset_id: str,
    tags: list[str],
    category: str,
    rating: float,
    quality_tier: QualityTier = 'standard',
    purchasable: bool = True,
    virtual_only: bool = False,
) -> CatalogItem:
    return CatalogItem(
        product_id=product_id,
        name=name,
        price=price,
        dimensions=Dimensions(width=width, height=height, depth=depth),
        asset_id=asset_id,
        tags=tags,
        category=category,
        rating=rating,
        quality_tier=quality_tier,
        purchasable=purchasable,
        virtual_only=virtual_only,
    )


DEMO_CATALOG: list[CatalogItem] = [
    # Seating — folding chair is cheap but below "good" floor for demo junk filter
    _item(
        'product_sofa_01',
        'Lounge Sofa',
        899,
        width=2.1,
        height=0.82,
        depth=0.91,
        asset_id='asset_sofa_01',
        tags=['seating', 'living'],
        category='seating',
        rating=4.6,
        quality_tier='premium',
    ),
    _item(
        'chair_fold_01',
        'Folding Chair',
        35,
        width=0.48,
        height=0.86,
        depth=0.52,
        asset_id='asset_chair_fold_01',
        tags=['seating', 'party'],
        category='seating',
        rating=3.2,
        quality_tier='budget',
    ),
    _item(
        'chair_dining_02',
        'Dining Chair',
        79,
        width=0.46,
        height=0.92,
        depth=0.5,
        asset_id='asset_chair_dining_02',
        tags=['seating', 'dining'],
        category='seating',
        rating=4.3,
        quality_tier='standard',
    ),
    _item(
        'stool_bar_01',
        'Bar Stool',
        65,
        width=0.4,
        height=1.05,
        depth=0.4,
        asset_id='asset_stool_bar_01',
        tags=['seating', 'party'],
        category='seating',
        rating=4.4,
        quality_tier='standard',
    ),
    _item(
        'beanbag_01',
        'Bean Bag',
        55,
        width=0.9,
        height=0.7,
        depth=0.9,
        asset_id='asset_beanbag_01',
        tags=['seating', 'movie', 'party'],
        category='seating',
        rating=4.1,
        quality_tier='budget',
    ),
    # Tables / desks
    _item(
        'product_table_05',
        'Coffee Table',
        249,
        width=1.4,
        height=0.75,
        depth=1.1,
        asset_id='asset_table_05',
        tags=['table', 'living'],
        category='tables',
        rating=4.2,
        quality_tier='standard',
    ),
    _item(
        'desk_study_01',
        'Study Desk',
        189,
        width=1.2,
        height=0.75,
        depth=0.6,
        asset_id='asset_desk_study_01',
        tags=['desk', 'study', 'table'],
        category='tables',
        rating=4.5,
        quality_tier='standard',
    ),
    _item(
        'table_dining_01',
        'Dining Table',
        420,
        width=1.8,
        height=0.75,
        depth=0.9,
        asset_id='asset_table_dining_01',
        tags=['table', 'dining'],
        category='tables',
        rating=4.4,
        quality_tier='premium',
    ),
    # Lighting
    _item(
        'product_39',
        'Arc Floor Lamp',
        129,
        width=0.4,
        height=1.72,
        depth=0.4,
        asset_id='asset_lamp_12',
        tags=['lighting'],
        category='lighting',
        rating=4.0,
        quality_tier='standard',
    ),
    _item(
        'party_lights_03',
        'String Party Lights',
        28,
        width=3.0,
        height=0.05,
        depth=0.05,
        asset_id='asset_party_lights_03',
        tags=['party', 'lighting'],
        category='lighting',
        rating=4.5,
        quality_tier='budget',
    ),
    _item(
        'lamp_desk_01',
        'Task Desk Lamp',
        42,
        width=0.2,
        height=0.45,
        depth=0.2,
        asset_id='asset_lamp_desk_01',
        tags=['lighting', 'study'],
        category='lighting',
        rating=4.4,
        quality_tier='standard',
    ),
    _item(
        'pendant_dinner_01',
        'Pendant Light',
        95,
        width=0.45,
        height=0.35,
        depth=0.45,
        asset_id='asset_pendant_dinner_01',
        tags=['lighting', 'dining'],
        category='lighting',
        rating=4.3,
        quality_tier='standard',
    ),
    # Decor / party / movie
    _item(
        'backdrop_12',
        'Photo Backdrop',
        45,
        width=2.0,
        height=2.4,
        depth=0.08,
        asset_id='asset_backdrop_12',
        tags=['party', 'decor', 'movie'],
        category='decor',
        rating=4.2,
        quality_tier='budget',
    ),
    _item(
        'plant_tall_02',
        'Tall Floor Plant',
        62,
        width=0.45,
        height=1.4,
        depth=0.45,
        asset_id='asset_plant_tall_02',
        tags=['decor'],
        category='decor',
        rating=4.0,
        quality_tier='standard',
    ),
    _item(
        'rug_party_01',
        'Dance Floor Rug',
        89,
        width=2.0,
        height=0.02,
        depth=2.0,
        asset_id='asset_rug_party_01',
        tags=['party', 'floor'],
        category='floor',
        rating=4.1,
        quality_tier='standard',
    ),
    _item(
        'projector_screen_01',
        'Projector Screen',
        149,
        width=2.4,
        height=1.5,
        depth=0.06,
        asset_id='asset_projector_screen_01',
        tags=['movie', 'decor'],
        category='decor',
        rating=4.5,
        quality_tier='standard',
    ),
    # Virtual-only (layout helpers, not checkout)
    _item(
        'virtual_marker_01',
        'Layout Marker',
        0,
        width=0.2,
        height=0.05,
        depth=0.2,
        asset_id='asset_virtual_marker_01',
        tags=['virtual', 'helper'],
        category='virtual',
        rating=0.0,
        quality_tier='budget',
        purchasable=False,
        virtual_only=True,
    ),
    _item(
        'virtual_glow_orb',
        'Ambient Glow Orb',
        0,
        width=0.3,
        height=0.3,
        depth=0.3,
        asset_id='asset_virtual_glow_orb',
        tags=['virtual', 'lighting', 'party'],
        category='virtual',
        rating=0.0,
        quality_tier='budget',
        purchasable=False,
        virtual_only=True,
    ),
]


def catalog_by_id() -> dict[str, CatalogItem]:
    return {item.product_id: item for item in DEMO_CATALOG}


def fresh_demo_scene() -> Scene:
    scene = deepcopy(build_demo_scene())
    prices = catalog_by_id()
    total = 0.0
    for obj in scene.objects:
        if obj.product_id and obj.product_id in prices:
            total += prices[obj.product_id].price
    scene.budget_used = total
    return scene
