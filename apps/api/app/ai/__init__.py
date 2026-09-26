"""Hybrid AI layout planner: rules always, LLM when XAI_API_KEY is set."""

from .planner import plan_layout

__all__ = ['plan_layout']
