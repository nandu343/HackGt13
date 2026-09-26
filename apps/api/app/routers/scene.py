from fastapi import APIRouter, HTTPException, Query

from ..models import (
    Disagreement,
    DisagreementCompromiseRequest,
    DisagreementCounterRequest,
    DisagreementCreateRequest,
    DisagreementResolveRequest,
    OperationEnvelope,
    OperationsResult,
    Scene,
    SceneInvite,
    SceneInviteCreateRequest,
    SceneInviteList,
    SoftLockReleaseRequest,
    SoftLockRequest,
    SoftLockResult,
    TimelineBranchRequest,
    TimelineBranchResult,
    TimelineList,
    TimelineRestoreRequest,
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


# --- Invites (unlimited peers via WS presence) ----------------------------


@router.post('/{scene_id}/invites', response_model=SceneInvite, status_code=201)
def create_invite(
    scene_id: str, payload: SceneInviteCreateRequest | None = None
) -> SceneInvite:
    """Create a shareable invite token for this scene (no joiner cap)."""
    return get_store().create_invite(scene_id, payload or SceneInviteCreateRequest())


@router.get('/{scene_id}/invites', response_model=SceneInviteList)
def list_invites(scene_id: str) -> SceneInviteList:
    return get_store().list_invites(scene_id)


@router.get('/{scene_id}/invites/default', response_model=SceneInvite)
def default_invite(scene_id: str) -> SceneInvite:
    """Ensure at least one invite exists and return it (demo convenience)."""
    return get_store().ensure_default_invite(scene_id)


# --- Timeline -------------------------------------------------------------


@router.get('/{scene_id}/timeline', response_model=TimelineList)
def get_timeline(
    scene_id: str,
    branch_id: str | None = Query(default=None, alias='branchId'),
) -> TimelineList:
    return get_store().get_timeline(scene_id, branch_id=branch_id)


@router.post('/{scene_id}/timeline/restore', response_model=OperationsResult)
def restore_timeline(scene_id: str, payload: TimelineRestoreRequest) -> OperationsResult:
    return get_store().restore_timeline(scene_id, payload)


@router.post('/{scene_id}/timeline/branch', response_model=TimelineBranchResult)
def branch_timeline(scene_id: str, payload: TimelineBranchRequest) -> TimelineBranchResult:
    return get_store().branch_timeline(scene_id, payload)


# --- Disagreement ---------------------------------------------------------


@router.get('/{scene_id}/disagreement', response_model=Disagreement | None)
def get_disagreement(scene_id: str) -> Disagreement | None:
    return get_store().get_disagreement(scene_id)


@router.post('/{scene_id}/disagreement', response_model=Disagreement, status_code=201)
def create_disagreement(
    scene_id: str, payload: DisagreementCreateRequest
) -> Disagreement:
    return get_store().create_disagreement(scene_id, payload)


@router.post(
    '/{scene_id}/disagreement/{disagreement_id}/counter',
    response_model=Disagreement,
)
def counter_disagreement(
    scene_id: str,
    disagreement_id: str,
    payload: DisagreementCounterRequest,
) -> Disagreement:
    return get_store().counter_disagreement(scene_id, disagreement_id, payload)


@router.post(
    '/{scene_id}/disagreement/{disagreement_id}/compromise',
    response_model=OperationsResult,
)
def compromise_disagreement(
    scene_id: str,
    disagreement_id: str,
    payload: DisagreementCompromiseRequest,
) -> OperationsResult:
    return get_store().compromise_disagreement(scene_id, disagreement_id, payload)


@router.post(
    '/{scene_id}/disagreement/{disagreement_id}/resolve',
)
def resolve_disagreement(
    scene_id: str,
    disagreement_id: str,
    payload: DisagreementResolveRequest,
):
    return get_store().resolve_disagreement(scene_id, disagreement_id, payload)
