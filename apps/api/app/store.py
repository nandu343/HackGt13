"""Scene store abstraction: in-memory by default, optional Supabase backend.

Also keeps an in-memory timeline (version snapshots) and active disagreement
state for collaborative restore / branch / compromise demos.
"""

from __future__ import annotations

import asyncio
import re
import secrets
import threading
import uuid
from datetime import datetime, timezone
from typing import Literal, Protocol

from fastapi import HTTPException

from .config import get_settings
from .locks import acquire_lock, assert_ops_respect_locks, release_lock
from .models import (
    Disagreement,
    DisagreementCompromiseRequest,
    DisagreementCounterRequest,
    DisagreementCreateRequest,
    DisagreementProposal,
    DisagreementResolveRequest,
    OperationEnvelope,
    OperationsResult,
    Scene,
    SceneInvite,
    SceneInviteCreateRequest,
    SceneInviteList,
    SceneInviteResolve,
    SceneObject,
    SceneOperation,
    SoftLockResult,
    TimelineBranchRequest,
    TimelineBranchResult,
    TimelineEntry,
    TimelineList,
    TimelineRestoreRequest,
)
from .ops import OpApplyError, apply_operations
from .seed import fresh_demo_scene

# Main uvicorn loop — set on app startup so sync routes can broadcast safely.
_main_loop: asyncio.AbstractEventLoop | None = None

MAX_TIMELINE_ENTRIES = 80


def set_main_loop(loop: asyncio.AbstractEventLoop | None) -> None:
    global _main_loop
    _main_loop = loop


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')


def _slug(name: str) -> str:
    cleaned = re.sub(r'[^a-zA-Z0-9_-]+', '-', name.strip().lower()).strip('-')
    return (cleaned or 'branch')[:40]


class SceneBackend(Protocol):
    def get(self, scene_id: str) -> Scene | None: ...

    def put(self, scene: Scene) -> None: ...

    def ensure_seed(self) -> None: ...


class MemoryBackend:
    def __init__(self) -> None:
        self._scenes: dict[str, Scene] = {}
        self._lock = threading.RLock()

    def get(self, scene_id: str) -> Scene | None:
        with self._lock:
            scene = self._scenes.get(scene_id)
            return scene.model_copy(deep=True) if scene else None

    def put(self, scene: Scene) -> None:
        with self._lock:
            self._scenes[scene.scene_id] = scene.model_copy(deep=True)

    def ensure_seed(self) -> None:
        with self._lock:
            if 'scene_party_001' not in self._scenes:
                self._scenes['scene_party_001'] = fresh_demo_scene()


def _scene_diff_ops(from_scene: Scene, to_scene: Scene) -> list[SceneOperation]:
    """Build ops that transform from_scene into to_scene (demo-scale)."""
    ops: list[SceneOperation] = []
    prev_ids = {o.id for o in from_scene.objects}
    next_ids = {o.id for o in to_scene.objects}
    prev_by = {o.id: o for o in from_scene.objects}
    next_by = {o.id: o for o in to_scene.objects}

    for oid in prev_ids - next_ids:
        ops.append(SceneOperation(type='DELETE_OBJECT', object_id=oid))

    for oid in next_ids - prev_ids:
        obj = next_by[oid]
        ops.append(
            SceneOperation(
                type='ADD_OBJECT',
                object_id=obj.id,
                object_type=obj.type,
                product_id=obj.product_id,
                asset_id=obj.asset_id,
                source=obj.source,
                target_position=list(obj.transform.position),
                target_rotation=list(obj.transform.rotation),
                dimensions=obj.dimensions.model_copy(deep=True) if obj.dimensions else None,
                movable=obj.movable,
            )
        )

    for oid in prev_ids & next_ids:
        a = prev_by[oid]
        b = next_by[oid]
        if a.transform.position != b.transform.position:
            ops.append(
                SceneOperation(
                    type='MOVE_OBJECT',
                    object_id=oid,
                    target_position=list(b.transform.position),
                )
            )
        if a.transform.rotation != b.transform.rotation:
            ops.append(
                SceneOperation(
                    type='ROTATE_OBJECT',
                    object_id=oid,
                    target_rotation=list(b.transform.rotation),
                )
            )
        if a.product_id != b.product_id or a.asset_id != b.asset_id:
            ops.append(
                SceneOperation(
                    type='REPLACE_OBJECT',
                    object_id=oid,
                    product_id=b.product_id,
                    asset_id=b.asset_id,
                )
            )
    return ops


def _object_changed(base: SceneObject | None, other: SceneObject | None) -> bool:
    if base is None and other is None:
        return False
    if base is None or other is None:
        return True
    return (
        base.transform.position != other.transform.position
        or base.transform.rotation != other.transform.rotation
        or base.product_id != other.product_id
        or base.asset_id != other.asset_id
        or base.type != other.type
    )


def _build_compromise_scene(
    base: Scene,
    scene_a: Scene,
    scene_b: Scene,
    *,
    mode: Literal['blend', 'picks', 'a', 'b'],
    picks: dict[str, Literal['A', 'B']] | None,
) -> Scene:
    if mode == 'a':
        return scene_a.model_copy(deep=True)
    if mode == 'b':
        return scene_b.model_copy(deep=True)

    base_by = {o.id: o for o in base.objects}
    a_by = {o.id: o for o in scene_a.objects}
    b_by = {o.id: o for o in scene_b.objects}
    all_ids = set(base_by) | set(a_by) | set(b_by)
    picks = picks or {}

    chosen: dict[str, SceneObject] = {}
    for oid in all_ids:
        base_obj = base_by.get(oid)
        a_obj = a_by.get(oid)
        b_obj = b_by.get(oid)
        a_changed = _object_changed(base_obj, a_obj)
        b_changed = _object_changed(base_obj, b_obj)

        side: Literal['A', 'B'] | None = None
        if mode == 'picks' and oid in picks:
            side = picks[oid]
        elif a_changed and not b_changed:
            side = 'A'
        elif b_changed and not a_changed:
            side = 'B'
        elif a_changed and b_changed:
            # Conflict: prefer explicit pick, else A
            side = picks.get(oid, 'A')
        else:
            # Neither changed — keep base (or drop if deleted in both)
            if base_obj is not None:
                chosen[oid] = base_obj.model_copy(deep=True)
            continue

        src = a_obj if side == 'A' else b_obj
        if src is not None:
            chosen[oid] = src.model_copy(deep=True)
        # else: deleted on chosen side

    result = base.model_copy(deep=True)
    result.objects = list(chosen.values())
    return result


class SceneStore:
    def __init__(self, backend: SceneBackend | None = None) -> None:
        self._backend = backend or MemoryBackend()
        self._backend.ensure_seed()
        self._apply_lock = threading.RLock()
        self._timeline: dict[str, list[TimelineEntry]] = {}
        self._disagreements: dict[str, Disagreement] = {}
        # token -> SceneInvite (in-memory; unlimited joiners via WS presence)
        self._invites: dict[str, SceneInvite] = {}
        self._invites_by_scene: dict[str, list[str]] = {}
        self._seed_timeline()

    def _seed_timeline(self) -> None:
        scene = self._backend.get('scene_party_001')
        if scene is None:
            return
        if 'scene_party_001' in self._timeline and self._timeline['scene_party_001']:
            return
        self._append_timeline_unlocked(
            scene,
            label='Seed room',
            actor_id='system',
            display_name='System',
            operations=None,
            branch_id='main',
        )

    def get_scene(self, scene_id: str) -> Scene:
        scene = self._backend.get(scene_id)
        if scene is None:
            raise HTTPException(status_code=404, detail=f'Scene {scene_id} not found')
        return scene

    def put_scene(self, scene: Scene, *, label: str | None = None, actor_id: str | None = None) -> Scene:
        """Upsert a full normalized scene (e.g. RoomPlan export from iOS)."""
        with self._apply_lock:
            existing = self._backend.get(scene.scene_id)
            stored = scene.model_copy(deep=True)
            if existing is not None:
                stored.version = max(existing.version + 1, stored.version)
            elif stored.version < 1:
                stored.version = 1
            self._backend.put(stored)
            entry = self._append_timeline_unlocked(
                stored,
                label=label or 'Full scene upsert',
                actor_id=actor_id or 'import',
                display_name=None,
                operations=None,
            )
            self._schedule_coro(self._broadcast_scene(stored))
            self._schedule_coro(self._broadcast_timeline(stored.scene_id, entry))
            return stored.model_copy(deep=True)

    def apply_envelope(
        self,
        scene_id: str,
        envelope: OperationEnvelope,
        *,
        budget_ceiling: float | None = None,
    ) -> OperationsResult:
        with self._apply_lock:
            current = self.get_scene(scene_id)
            if envelope.base_version != current.version:
                raise HTTPException(
                    status_code=409,
                    detail={
                        'message': 'Stale baseVersion',
                        'baseVersion': envelope.base_version,
                        'currentVersion': current.version,
                    },
                )
            assert_ops_respect_locks(current, envelope.operations, envelope.actor_id)
            from_version = current.version
            try:
                updated, warnings = apply_operations(
                    current,
                    envelope.operations,
                    budget_ceiling=budget_ceiling,
                    validate=True,
                )
            except OpApplyError as exc:
                raise HTTPException(status_code=400, detail={'errors': exc.errors}) from exc

            updated.version = current.version + 1
            self._backend.put(updated)
            result = OperationsResult(
                accepted=True,
                scene_id=updated.scene_id,
                version=updated.version,
                applied=len(envelope.operations),
                scene=updated,
                warnings=warnings or None,
            )
            label = envelope.label or f'Ops ×{len(envelope.operations)}'
            entry = self._append_timeline_unlocked(
                updated,
                label=label,
                actor_id=envelope.actor_id,
                display_name=None,
                operations=list(envelope.operations),
            )
            self._schedule_coro(
                self._broadcast_patch(updated, envelope.operations, from_version)
            )
            self._schedule_coro(self._broadcast_timeline(scene_id, entry))
            return result

    def lock_object(
        self,
        scene_id: str,
        *,
        object_id: str,
        actor_id: str,
        ttl_seconds: int | None = None,
    ) -> SoftLockResult:
        with self._apply_lock:
            scene = self.get_scene(scene_id)
            result = acquire_lock(
                scene,
                object_id=object_id,
                actor_id=actor_id,
                ttl_seconds=ttl_seconds,
            )
            if result.ok and result.scene:
                self._backend.put(result.scene)
                self._schedule_coro(self._broadcast_scene(result.scene))
            return result

    def unlock_object(
        self,
        scene_id: str,
        *,
        object_id: str,
        actor_id: str,
    ) -> SoftLockResult:
        with self._apply_lock:
            scene = self.get_scene(scene_id)
            result = release_lock(scene, object_id=object_id, actor_id=actor_id)
            if result.ok and result.scene:
                self._backend.put(result.scene)
                self._schedule_coro(self._broadcast_scene(result.scene))
            return result

    # --- Invites (shareable join links; no peer cap) -----------------------

    def create_invite(
        self, scene_id: str, req: SceneInviteCreateRequest | None = None
    ) -> SceneInvite:
        self.get_scene(scene_id)  # 404 if missing
        req = req or SceneInviteCreateRequest()
        with self._apply_lock:
            token = secrets.token_urlsafe(12)
            while token in self._invites:
                token = secrets.token_urlsafe(12)
            invite = SceneInvite(
                token=token,
                scene_id=scene_id,
                created_at=_utc_now_iso(),
                created_by=req.actor_id,
                label=req.label or 'Friends invite',
            )
            self._invites[token] = invite
            self._invites_by_scene.setdefault(scene_id, []).append(token)
            return invite.model_copy(deep=True)

    def list_invites(self, scene_id: str) -> SceneInviteList:
        self.get_scene(scene_id)
        with self._apply_lock:
            tokens = list(self._invites_by_scene.get(scene_id, []))
            invites = [
                self._invites[t].model_copy(deep=True)
                for t in tokens
                if t in self._invites
            ]
        return SceneInviteList(scene_id=scene_id, invites=invites)

    def resolve_invite(self, token: str) -> SceneInviteResolve:
        with self._apply_lock:
            invite = self._invites.get(token)
            if invite is None:
                raise HTTPException(status_code=404, detail='Invite not found')
            scene_id = invite.scene_id
        # Ensure scene still exists
        self.get_scene(scene_id)
        join_path = f'/?scene={scene_id}&invite={token}'
        return SceneInviteResolve(token=token, scene_id=scene_id, join_path=join_path)

    def ensure_default_invite(self, scene_id: str) -> SceneInvite:
        """Return the newest invite for a scene, or create one."""
        listed = self.list_invites(scene_id)
        if listed.invites:
            return listed.invites[-1]
        return self.create_invite(scene_id)

    # --- Timeline ---------------------------------------------------------

    def _append_timeline_unlocked(
        self,
        scene: Scene,
        *,
        label: str,
        actor_id: str | None,
        display_name: str | None,
        operations: list[SceneOperation] | None,
        branch_id: str = 'main',
        parent_entry_id: str | None = None,
    ) -> TimelineEntry:
        entries = self._timeline.setdefault(scene.scene_id, [])
        parent = parent_entry_id
        if parent is None and entries:
            parent = entries[-1].entry_id
        entry = TimelineEntry(
            entry_id=f'tl_{uuid.uuid4().hex[:10]}',
            scene_id=scene.scene_id,
            version=scene.version,
            label=label,
            actor_id=actor_id,
            display_name=display_name,
            branch_id=branch_id,
            parent_entry_id=parent,
            created_at=_utc_now_iso(),
            operations=[o.model_copy(deep=True) for o in operations] if operations else None,
            scene=scene.model_copy(deep=True),
        )
        entries.append(entry)
        if len(entries) > MAX_TIMELINE_ENTRIES:
            self._timeline[scene.scene_id] = entries[-MAX_TIMELINE_ENTRIES:]
        return entry

    def get_timeline(self, scene_id: str, *, branch_id: str | None = None) -> TimelineList:
        self.get_scene(scene_id)  # 404 if missing
        with self._apply_lock:
            entries = list(self._timeline.get(scene_id, []))
        if branch_id:
            entries = [e for e in entries if e.branch_id == branch_id]
        return TimelineList(
            scene_id=scene_id,
            branch_id=branch_id or 'main',
            entries=entries,
        )

    def restore_timeline(
        self, scene_id: str, req: TimelineRestoreRequest
    ) -> OperationsResult:
        with self._apply_lock:
            current = self.get_scene(scene_id)
            entries = self._timeline.get(scene_id, [])
            target = next((e for e in entries if e.entry_id == req.entry_id), None)
            if target is None:
                raise HTTPException(status_code=404, detail='Timeline entry not found')

            restored = target.scene.model_copy(deep=True)
            restored.scene_id = scene_id
            restored.version = current.version + 1
            # Clear soft locks on restore
            for obj in restored.objects:
                obj.locked_by = None
                obj.locked_until = None

            ops = _scene_diff_ops(current, restored)
            self._backend.put(restored)
            entry = self._append_timeline_unlocked(
                restored,
                label=f'Restored · {target.label}',
                actor_id=req.actor_id,
                display_name=req.display_name,
                operations=ops or None,
                branch_id=target.branch_id,
                parent_entry_id=target.entry_id,
            )
            result = OperationsResult(
                accepted=True,
                scene_id=restored.scene_id,
                version=restored.version,
                applied=len(ops),
                scene=restored,
                warnings=None,
            )
            self._schedule_coro(self._broadcast_scene(restored))
            self._schedule_coro(self._broadcast_timeline(scene_id, entry))
            return result

    def branch_timeline(
        self, scene_id: str, req: TimelineBranchRequest
    ) -> TimelineBranchResult:
        with self._apply_lock:
            self.get_scene(scene_id)
            entries = self._timeline.get(scene_id, [])
            target = next((e for e in entries if e.entry_id == req.entry_id), None)
            if target is None:
                raise HTTPException(status_code=404, detail='Timeline entry not found')

            slug = _slug(req.name)
            branch_id = slug
            branch_scene_id = f'{scene_id}__{slug}'
            if self._backend.get(branch_scene_id) is not None:
                branch_scene_id = f'{branch_scene_id}_{uuid.uuid4().hex[:4]}'

            forked = target.scene.model_copy(deep=True)
            forked.scene_id = branch_scene_id
            forked.version = 1
            for obj in forked.objects:
                obj.locked_by = None
                obj.locked_until = None
            self._backend.put(forked)

            entry = self._append_timeline_unlocked(
                forked,
                label=f'Branch “{req.name.strip()}” from v{target.version}',
                actor_id=req.actor_id,
                display_name=req.display_name,
                operations=None,
                branch_id=branch_id,
                parent_entry_id=target.entry_id,
            )
            # Also note the fork on the source timeline
            note = self._append_timeline_unlocked(
                self.get_scene(scene_id),
                label=f'Forked → {branch_scene_id}',
                actor_id=req.actor_id,
                display_name=req.display_name,
                operations=None,
                branch_id='main',
                parent_entry_id=target.entry_id,
            )
            result = TimelineBranchResult(
                source_scene_id=scene_id,
                branch_id=branch_id,
                branch_scene_id=branch_scene_id,
                entry=entry,
                scene=forked,
            )
            self._schedule_coro(self._broadcast_timeline(scene_id, note))
            self._schedule_coro(self._broadcast_scene(forked))
            return result

    # --- Disagreement -----------------------------------------------------

    def get_disagreement(self, scene_id: str) -> Disagreement | None:
        self.get_scene(scene_id)
        with self._apply_lock:
            d = self._disagreements.get(scene_id)
            return d.model_copy(deep=True) if d else None

    def create_disagreement(
        self, scene_id: str, req: DisagreementCreateRequest
    ) -> Disagreement:
        with self._apply_lock:
            current = self.get_scene(scene_id)
            existing = self._disagreements.get(scene_id)
            if existing and existing.status in ('open', 'countered'):
                raise HTTPException(
                    status_code=409,
                    detail='An active disagreement already exists for this scene',
                )
            if req.base_version is not None and req.base_version != current.version:
                raise HTTPException(
                    status_code=409,
                    detail={
                        'message': 'Stale baseVersion',
                        'baseVersion': req.base_version,
                        'currentVersion': current.version,
                    },
                )
            try:
                preview, _ = apply_operations(
                    current, req.operations, validate=True
                )
            except OpApplyError as exc:
                raise HTTPException(status_code=400, detail={'errors': exc.errors}) from exc

            proposal = DisagreementProposal(
                actor_id=req.actor_id,
                display_name=req.display_name,
                label=req.label or 'Proposal A',
                operations=[o.model_copy(deep=True) for o in req.operations],
                scene=preview.model_copy(deep=True),
                created_at=_utc_now_iso(),
            )
            disagreement = Disagreement(
                disagreement_id=f'dis_{uuid.uuid4().hex[:10]}',
                scene_id=scene_id,
                status='open',
                base_version=current.version,
                base_scene=current.model_copy(deep=True),
                proposal_a=proposal,
                proposal_b=None,
                created_at=_utc_now_iso(),
            )
            self._disagreements[scene_id] = disagreement
            self._schedule_coro(self._broadcast_disagreement(disagreement))
            return disagreement.model_copy(deep=True)

    def counter_disagreement(
        self, scene_id: str, disagreement_id: str, req: DisagreementCounterRequest
    ) -> Disagreement:
        with self._apply_lock:
            d = self._require_active_disagreement(scene_id, disagreement_id)
            if req.actor_id == d.proposal_a.actor_id and d.proposal_b is None:
                # Allow same actor to replace A before a counter exists
                try:
                    preview, _ = apply_operations(
                        d.base_scene, req.operations, validate=True
                    )
                except OpApplyError as exc:
                    raise HTTPException(status_code=400, detail={'errors': exc.errors}) from exc
                d.proposal_a = DisagreementProposal(
                    actor_id=req.actor_id,
                    display_name=req.display_name,
                    label=req.label or d.proposal_a.label or 'Proposal A',
                    operations=[o.model_copy(deep=True) for o in req.operations],
                    scene=preview.model_copy(deep=True),
                    created_at=_utc_now_iso(),
                )
            else:
                try:
                    preview, _ = apply_operations(
                        d.base_scene, req.operations, validate=True
                    )
                except OpApplyError as exc:
                    raise HTTPException(status_code=400, detail={'errors': exc.errors}) from exc
                d.proposal_b = DisagreementProposal(
                    actor_id=req.actor_id,
                    display_name=req.display_name,
                    label=req.label or 'Proposal B',
                    operations=[o.model_copy(deep=True) for o in req.operations],
                    scene=preview.model_copy(deep=True),
                    created_at=_utc_now_iso(),
                )
                d.status = 'countered'
            self._disagreements[scene_id] = d
            self._schedule_coro(self._broadcast_disagreement(d))
            return d.model_copy(deep=True)

    def compromise_disagreement(
        self, scene_id: str, disagreement_id: str, req: DisagreementCompromiseRequest
    ) -> OperationsResult:
        with self._apply_lock:
            d = self._require_active_disagreement(scene_id, disagreement_id)
            if d.proposal_b is None and req.mode not in ('a',):
                raise HTTPException(
                    status_code=400,
                    detail='Proposal B required for blend/picks/b (use mode=a to accept A)',
                )
            scene_a = d.proposal_a.scene
            if scene_a is None:
                scene_a, _ = apply_operations(
                    d.base_scene, d.proposal_a.operations, validate=False
                )
            scene_b = d.proposal_b.scene if d.proposal_b else d.base_scene
            if d.proposal_b and scene_b is None:
                scene_b, _ = apply_operations(
                    d.base_scene, d.proposal_b.operations, validate=False
                )

            target = _build_compromise_scene(
                d.base_scene,
                scene_a,
                scene_b,
                mode=req.mode,
                picks=req.picks,
            )
            current = self.get_scene(scene_id)
            ops = _scene_diff_ops(current, target)
            if not ops:
                d.status = 'resolved'
                d.resolved_at = _utc_now_iso()
                d.resolve_mode = req.mode
                self._disagreements[scene_id] = d
                self._schedule_coro(self._broadcast_disagreement(d))
                return OperationsResult(
                    accepted=True,
                    scene_id=current.scene_id,
                    version=current.version,
                    applied=0,
                    scene=current,
                    warnings=['Compromise matched current scene — nothing to apply'],
                )

            envelope = OperationEnvelope(
                base_version=current.version,
                actor_id=req.actor_id,
                op_id=f'compromise_{uuid.uuid4().hex[:8]}',
                label=f'Compromise · {req.mode}',
                operations=ops,
            )
            # Inline apply (already holding lock) — duplicate core of apply_envelope
            try:
                updated, warnings = apply_operations(
                    current, ops, validate=True
                )
            except OpApplyError as exc:
                raise HTTPException(status_code=400, detail={'errors': exc.errors}) from exc
            from_version = current.version
            updated.version = current.version + 1
            self._backend.put(updated)
            entry = self._append_timeline_unlocked(
                updated,
                label=envelope.label or 'Compromise',
                actor_id=req.actor_id,
                display_name=req.display_name,
                operations=ops,
            )
            d.status = 'resolved'
            d.resolved_at = _utc_now_iso()
            d.resolve_mode = req.mode
            self._disagreements[scene_id] = d
            result = OperationsResult(
                accepted=True,
                scene_id=updated.scene_id,
                version=updated.version,
                applied=len(ops),
                scene=updated,
                warnings=warnings or None,
            )
            self._schedule_coro(self._broadcast_patch(updated, ops, from_version))
            self._schedule_coro(self._broadcast_timeline(scene_id, entry))
            self._schedule_coro(self._broadcast_disagreement(d))
            return result

    def resolve_disagreement(
        self, scene_id: str, disagreement_id: str, req: DisagreementResolveRequest
    ) -> OperationsResult | Disagreement:
        with self._apply_lock:
            d = self._require_active_disagreement(scene_id, disagreement_id)
            if req.choice == 'cancel':
                d.status = 'cancelled'
                d.resolved_at = _utc_now_iso()
                d.resolve_mode = 'cancel'
                self._disagreements[scene_id] = d
                self._schedule_coro(self._broadcast_disagreement(d))
                return d.model_copy(deep=True)

            mode: Literal['a', 'b'] = 'a' if req.choice == 'A' else 'b'
            if mode == 'b' and d.proposal_b is None:
                raise HTTPException(status_code=400, detail='No proposal B to accept')
            # Re-enter compromise without re-acquiring (we hold lock) via inline
            compromise_req = DisagreementCompromiseRequest(
                actor_id=req.actor_id,
                display_name=req.display_name,
                mode=mode,
            )
        # Drop lock then call compromise (it re-acquires)
        return self.compromise_disagreement(scene_id, disagreement_id, compromise_req)

    def _require_active_disagreement(
        self, scene_id: str, disagreement_id: str
    ) -> Disagreement:
        self.get_scene(scene_id)
        d = self._disagreements.get(scene_id)
        if d is None or d.disagreement_id != disagreement_id:
            raise HTTPException(status_code=404, detail='Disagreement not found')
        if d.status not in ('open', 'countered'):
            raise HTTPException(status_code=409, detail=f'Disagreement is {d.status}')
        return d

    def _schedule_coro(self, coro) -> None:
        loop = _main_loop
        if loop is not None and loop.is_running():
            asyncio.run_coroutine_threadsafe(coro, loop)
            return
        try:
            running = asyncio.get_running_loop()
            running.create_task(coro)
        except RuntimeError:
            coro.close()

    async def _broadcast_patch(self, scene: Scene, operations, from_version: int) -> None:
        from .realtime import get_hub

        await get_hub().broadcast_patch(scene, operations, from_version=from_version)

    async def _broadcast_scene(self, scene: Scene) -> None:
        from .realtime import get_hub

        await get_hub().broadcast_scene(scene)

    async def _broadcast_timeline(self, scene_id: str, entry: TimelineEntry) -> None:
        from .realtime import get_hub

        await get_hub().broadcast(
            scene_id,
            {
                'type': 'timeline',
                'sceneId': scene_id,
                'entry': entry.model_dump(by_alias=True),
                'timeline': [
                    e.model_dump(by_alias=True)
                    for e in self._timeline.get(scene_id, [])
                ],
            },
        )

    async def _broadcast_disagreement(self, disagreement: Disagreement) -> None:
        from .realtime import get_hub

        await get_hub().broadcast(
            disagreement.scene_id,
            {
                'type': 'disagreement',
                'sceneId': disagreement.scene_id,
                'disagreement': disagreement.model_dump(by_alias=True),
            },
        )


_store: SceneStore | None = None


def get_store() -> SceneStore:
    global _store
    if _store is None:
        _store = create_store()
    return _store


def create_store() -> SceneStore:
    settings = get_settings()
    if settings.use_supabase:
        from .persistence.supabase_store import SupabaseBackend

        try:
            backend = SupabaseBackend()
            return SceneStore(backend)
        except Exception:
            # Fall back so local demo never requires live Supabase
            return SceneStore(MemoryBackend())
    return SceneStore(MemoryBackend())


def reset_store_for_tests() -> None:
    global _store
    _store = None
