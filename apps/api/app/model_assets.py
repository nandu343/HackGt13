"""Map catalog asset_id / product_id → public model URL (GLB on web)."""

from __future__ import annotations

ASSET_MODEL_URL: dict[str, str] = {
    'asset_sofa_01': '/models/sofa.glb',
    'asset_chair_fold_01': '/models/loungeChair.glb',
    'asset_chair_dining_02': '/models/chairDesk.glb',
    'asset_stool_bar_01': '/models/stool.glb',
    'asset_beanbag_01': '/models/beanbag.glb',
    'asset_table_05': '/models/table.glb',
    'asset_desk_study_01': '/models/desk.glb',
    'asset_table_dining_01': '/models/sideTable.glb',
    'asset_lamp_12': '/models/lampRoundFloor.glb',
    'asset_party_lights_03': '/models/string_lights.glb',
    'asset_lamp_desk_01': '/models/lampSquareTable.glb',
    'asset_pendant_dinner_01': '/models/pendant.glb',
    'asset_backdrop_12': '/models/backdrop.glb',
    'asset_plant_tall_02': '/models/pottedPlant.glb',
    'asset_rug_party_01': '/models/rugRectangle.glb',
    'asset_projector_screen_01': '/models/projector_screen.glb',
}

PRODUCT_MODEL_URL: dict[str, str] = {
    'product_sofa_01': '/models/sofa.glb',
    'chair_fold_01': '/models/loungeChair.glb',
    'chair_dining_02': '/models/chairDesk.glb',
    'stool_bar_01': '/models/stool.glb',
    'beanbag_01': '/models/beanbag.glb',
    'product_table_05': '/models/table.glb',
    'desk_study_01': '/models/desk.glb',
    'table_dining_01': '/models/sideTable.glb',
    'product_39': '/models/lampRoundFloor.glb',
    'party_lights_03': '/models/string_lights.glb',
    'lamp_desk_01': '/models/lampSquareTable.glb',
    'pendant_dinner_01': '/models/pendant.glb',
    'backdrop_12': '/models/backdrop.glb',
    'plant_tall_02': '/models/pottedPlant.glb',
    'rug_party_01': '/models/rugRectangle.glb',
    'projector_screen_01': '/models/projector_screen.glb',
}


def resolve_model_url(
    *,
    model_url: str | None = None,
    asset_id: str | None = None,
    product_id: str | None = None,
) -> str | None:
    if model_url:
        return model_url
    if asset_id and asset_id in ASSET_MODEL_URL:
        return ASSET_MODEL_URL[asset_id]
    if product_id and product_id in PRODUCT_MODEL_URL:
        return PRODUCT_MODEL_URL[product_id]
    return None
