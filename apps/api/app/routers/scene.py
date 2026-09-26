from fastapi import APIRouter, HTTPException, Query

from ..models import (
    OperationEnvelope,
    OperationsResult,
    Scene,
    SoftLockReleaseRequest,
    SoftLockRequest,
    SoftLockResult,
)
from ..store import get_store

router = APIRouter(prefix='/scene', tags=['scene'])


@router.get('/{scene_id}', response_model=Scene)
def get_scene(scene_id: str) -> Scene:
    return get_store().get_scene(scene_id)


@router.put('/{scene_id}', response_model=Scene)
def put_scene(scene_id: str, scene: Scene) -> Scene:
    """Replace/upsert a full scene (RoomPlan export / iOS scaffold)."""
    if scene.scene_id != scene_id:
        raise HTTPException(
            status_code=400,
            detail='sceneId in body must match path',
        )
    return get_store().put_scene(scene)


@router.post('', response_model=Scene, status_code=201)
def post_scene(scene: Scene) -> Scene:
    """Create or replace a scene by body.sceneId (RoomPlan export)."""
    return get_store().put_scene(scene)


@router.post('/{scene_id}/operations', response_model=OperationsResult)
def apply_operations(
    scene_id: str,
    envelope: OperationEnvelope,
    budget: float | None = Query(default=None, description='Optional budget ceiling'),
) -> OperationsResult:
    return get_store().apply_envelope(scene_id, envelope, budget_ceiling=budget)


@router.post('/{scene_id}/locks', response_model=SoftLockResult)
def lock_object(scene_id: str, payload: SoftLockRequest) -> SoftLockResult:
    """Acquire a soft lock (lockedBy + TTL) on an object for collaborative editing."""
    return get_store().lock_object(
        scene_id,
        object_id=payload.object_id,
        actor_id=payload.actor_id,
        ttl_seconds=payload.ttl_seconds,
    )


@router.post('/{scene_id}/locks/release', response_model=SoftLockResult)
def unlock_object(scene_id: str, payload: SoftLockReleaseRequest) -> SoftLockResult:
    """Release a soft lock held by actorId."""
    return get_store().unlock_object(
        scene_id,
        object_id=payload.object_id,
        actor_id=payload.actor_id,
    )
