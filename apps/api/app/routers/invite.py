"""Public invite resolve (token → sceneId + join path)."""

from fastapi import APIRouter

from ..models import SceneInviteResolve
from ..store import get_store

router = APIRouter(tags=['invite'])


@router.get('/invite/{token}', response_model=SceneInviteResolve)
def resolve_invite(token: str) -> SceneInviteResolve:
    """Resolve a shareable invite token to a scene join path (unlimited peers)."""
    return get_store().resolve_invite(token)
