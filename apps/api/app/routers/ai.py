from fastapi import APIRouter, HTTPException

from ..ai import plan_layout
from ..models import LayoutRequest, LayoutResponse
from ..store import get_store

router = APIRouter(prefix='/ai', tags=['ai'])


@router.post('/layout', response_model=LayoutResponse, response_model_exclude_none=True)
def generate_layout(payload: LayoutRequest) -> LayoutResponse:
    """Hybrid AI planner: rule-based always; LLM when XAI_API_KEY is set.

    Ops are validated/clamped but NOT applied — client must Accept via /scene/.../operations.
    """
    try:
        scene = get_store().get_scene(payload.scene_id)
    except HTTPException:
        raise

    return plan_layout(scene, payload)
