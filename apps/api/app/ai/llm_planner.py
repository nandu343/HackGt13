"""Optional xAI Grok LLM planner — structured LayoutResponse JSON only."""

from __future__ import annotations

import json
import logging
from typing import Any

from ..models import CatalogItem, ConstraintSet, LayoutRequest, LayoutResponse, Scene, SceneOperation
from .classifier import Scenario

logger = logging.getLogger(__name__)

# OpenAI-compatible chat completions at https://api.x.ai/v1
XAI_BASE_URL = 'https://api.x.ai/v1'
# Default Grok chat model suitable for structured JSON (xAI docs)
DEFAULT_XAI_MODEL = 'grok-4.6'

SYSTEM_PROMPT = """You are a spatial layout planner for a 3D room twin.
Return ONLY valid JSON matching this schema (camelCase keys):
{
  "scenario": "party"|"study"|"dinner"|"movie",
  "reasoningSummary": string,
  "operations": [
    {
      "type": "MOVE_OBJECT"|"ROTATE_OBJECT"|"ADD_OBJECT"|"DELETE_OBJECT"|"REPLACE_OBJECT",
      "objectId": string optional,
      "targetPosition": [x,y,z] optional,
      "targetRotation": [x,y,z,w] quaternion optional,
      "productId": string optional,
      "assetId": string optional,
      "objectType": string optional,
      "source": "existing"|"catalog" optional
    }
  ],
  "constraints": {
    "budget": number,
    "guestCount": number,
    "mustHave": string[] optional,
    "clearCenter": boolean optional
  },
  "warnings": string[] optional
}

Rules:
- Emit operations only — never return a full scene JSON.
- Prefer MOVE/ROTATE of existing movable objects; ADD_OBJECT from catalog productIds when needed.
- Prefer high-rated, lower-cost purchasable catalog items that still meet quality (rating >= ~3.5); avoid virtualOnly when shopping.
- Stay within budget and room bounds (meters, Y-up, origin at floor center).
- Clear the room center for party/dinner when asked.
- Do not move immovable walls.
"""


def _scene_brief(scene: Scene) -> dict[str, Any]:
    return {
        'sceneId': scene.scene_id,
        'bounds': scene.bounds.model_dump(by_alias=True),
        'version': scene.version,
        'objects': [
            {
                'id': o.id,
                'type': o.type,
                'movable': o.movable,
                'position': o.transform.position,
                'productId': o.product_id,
            }
            for o in scene.objects
        ],
    }


def _catalog_brief(catalog: dict[str, CatalogItem], limit: int = 24) -> list[dict[str, Any]]:
    items = list(catalog.values())[:limit]
    return [
        {
            'productId': i.product_id,
            'name': i.name,
            'price': i.price,
            'rating': i.rating,
            'qualityTier': i.quality_tier,
            'tags': i.tags,
            'category': i.category,
            'assetId': i.asset_id,
            'purchasable': i.purchasable,
            'virtualOnly': i.virtual_only,
            'dimensions': i.dimensions.model_dump(by_alias=True) if i.dimensions else None,
        }
        for i in items
    ]


def plan_with_llm(
    scene: Scene,
    request: LayoutRequest,
    catalog: dict[str, CatalogItem],
    *,
    api_key: str,
    scenario: Scenario,
) -> LayoutResponse | None:
    """Call xAI Grok chat completions; return None on any failure so caller can fall back."""
    try:
        from openai import OpenAI
    except ImportError:
        logger.warning('openai package not installed; skipping LLM planner')
        return None

    client = OpenAI(api_key=api_key, base_url=XAI_BASE_URL)
    user_payload = {
        'prompt': request.prompt,
        'guestCount': request.guest_count,
        'budget': request.budget,
        'hintScenario': scenario,
        'scene': _scene_brief(scene),
        'catalog': _catalog_brief(catalog),
    }

    try:
        response = client.chat.completions.create(
            model=DEFAULT_XAI_MODEL,
            temperature=0.3,
            response_format={'type': 'json_object'},
            messages=[
                {'role': 'system', 'content': SYSTEM_PROMPT},
                {'role': 'user', 'content': json.dumps(user_payload)},
            ],
        )
        content = response.choices[0].message.content or '{}'
        data = json.loads(content)
    except Exception as exc:
        logger.warning('LLM planner failed: %s', exc)
        return None

    try:
        ops_raw = data.get('operations') or data.get('Operations') or []
        operations = [SceneOperation.model_validate(op) for op in ops_raw]
        constraints_raw = data.get('constraints') or data.get('Constraints') or {}
        constraints = ConstraintSet.model_validate(constraints_raw) if constraints_raw else ConstraintSet()
        if constraints.budget is None:
            constraints.budget = request.budget
        if constraints.guest_count is None:
            constraints.guest_count = request.guest_count
        return LayoutResponse(
            scenario=str(data.get('scenario') or scenario),
            reasoning_summary=str(
                data.get('reasoningSummary')
                or data.get('reasoning_summary')
                or f'LLM {scenario} layout for prompt.'
            ),
            operations=operations,
            constraints=constraints,
            warnings=data.get('warnings'),
        )
    except Exception as exc:
        logger.warning('LLM response parse failed: %s', exc)
        return None
