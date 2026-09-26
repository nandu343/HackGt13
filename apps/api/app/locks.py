"""Soft-lock helpers for collaborative editing."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

from fastapi import HTTPException

from .config import get_settings
from .models import Scene, SceneObject, SoftLockResult
from .validators import can_relocate


def _parse_iso(value: str | None) -> datetime | None:
    if not value:
        return None
    try:
        text = value.replace('Z', '+00:00')
        return datetime.fromisoformat(text)
    except ValueError:
        return None


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def to_iso(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).isoformat().replace('+00:00', 'Z')


def is_lock_active(obj: SceneObject, *, now: datetime | None = None) -> bool:
    if not obj.locked_by:
        return False
    expiry = _parse_iso(obj.locked_until)
    if expiry is None:
        return True  # locked with no TTL treated as active until released
    return expiry > (now or utc_now())


def lock_holder(obj: SceneObject, *, now: datetime | None = None) -> str | None:
    if is_lock_active(obj, now=now):
        return obj.locked_by
    return None


def clear_expired_locks(scene: Scene) -> bool:
    """Clear expired locks in-place. Returns True if any cleared."""
    now = utc_now()
    changed = False
    for obj in scene.objects:
        if obj.locked_by and not is_lock_active(obj, now=now):
            obj.locked_by = None
            obj.locked_until = None
            changed = True
    return changed


def acquire_lock(
    scene: Scene,
    *,
    object_id: str,
    actor_id: str,
    ttl_seconds: int | None = None,
) -> SoftLockResult:
    clear_expired_locks(scene)
    obj = next((o for o in scene.objects if o.id == object_id), None)
    if obj is None:
        raise HTTPException(status_code=404, detail=f'Object {object_id} not found')
    if not can_relocate(obj):
        raise HTTPException(
            status_code=400,
            detail='Cannot lock structure (walls stay fixed)',
        )

    holder = lock_holder(obj)
    if holder and holder != actor_id:
        return SoftLockResult(
            ok=False,
            scene_id=scene.scene_id,
            object_id=object_id,
            locked_by=holder,
            locked_until=obj.locked_until,
            message=f'Object locked by {holder}',
            scene=scene,
        )

    ttl = ttl_seconds if ttl_seconds is not None else get_settings().lock_ttl_seconds
    until = utc_now() + timedelta(seconds=ttl)
    obj.locked_by = actor_id
    obj.locked_until = to_iso(until)
    return SoftLockResult(
        ok=True,
        scene_id=scene.scene_id,
        object_id=object_id,
        locked_by=actor_id,
        locked_until=obj.locked_until,
        message='Lock acquired',
        scene=scene,
    )


def release_lock(
    scene: Scene,
    *,
    object_id: str,
    actor_id: str,
    force: bool = False,
) -> SoftLockResult:
    clear_expired_locks(scene)
    obj = next((o for o in scene.objects if o.id == object_id), None)
    if obj is None:
        raise HTTPException(status_code=404, detail=f'Object {object_id} not found')

    holder = lock_holder(obj)
    if holder and holder != actor_id and not force:
        return SoftLockResult(
            ok=False,
            scene_id=scene.scene_id,
            object_id=object_id,
            locked_by=holder,
            locked_until=obj.locked_until,
            message=f'Object locked by {holder}',
            scene=scene,
        )

    obj.locked_by = None
    obj.locked_until = None
    return SoftLockResult(
        ok=True,
        scene_id=scene.scene_id,
        object_id=object_id,
        locked_by=None,
        locked_until=None,
        message='Lock released',
        scene=scene,
    )


def assert_ops_respect_locks(scene: Scene, operations, actor_id: str | None) -> None:
    """Reject mutations on objects locked by someone else."""
    clear_expired_locks(scene)
    objects = {o.id: o for o in scene.objects}
    for op in operations:
        oid = getattr(op, 'object_id', None)
        if not oid or oid not in objects:
            continue
        if op.type == 'ADD_OBJECT':
            continue
        obj = objects[oid]
        holder = lock_holder(obj)
        if holder and holder != actor_id:
            raise HTTPException(
                status_code=409,
                detail={
                    'message': f'Object {oid} is locked by {holder}',
                    'objectId': oid,
                    'lockedBy': holder,
                    'lockedUntil': obj.locked_until,
                },
            )
