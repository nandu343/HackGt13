"""Hybrid planner entry: rules always; LLM when XAI_API_KEY is set."""

from __future__ import annotations

from ..config import get_settings
from ..models import LayoutRequest, LayoutResponse, Scene
from ..seed import catalog_by_id
from .classifier import classify_scenario
from .llm_planner import plan_with_llm
from .postprocess import postprocess_layout
from .rule_planner import plan_with_rules


def plan_layout(scene: Scene, request: LayoutRequest) -> LayoutResponse:
    catalog = catalog_by_id()
    scenario = classify_scenario(request.prompt)
    settings = get_settings()

    response: LayoutResponse | None = None
    source = 'rules'

    if settings.xai_api_key:
        response = plan_with_llm(
            scene,
            request,
            catalog,
            api_key=settings.xai_api_key,
            scenario=scenario,
        )
        if response is not None:
            source = 'llm'

    if response is None:
        response = plan_with_rules(scene, request, catalog, scenario=scenario)
        source = 'rules'

    response.planner_mode = 'llm' if source == 'llm' else 'rules'

    # Prefix reasoning with planner source for web Accept/Reject UX
    if not response.reasoning_summary.startswith('['):
        response.reasoning_summary = f'[{source}] {response.reasoning_summary}'

    return postprocess_layout(scene, response, catalog)
