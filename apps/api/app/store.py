"""Scene store abstraction: in-memory by default, optional Supabase backend."""

from __future__ import annotations

import asyncio
import threading
from typing import Protocol

from fastapi import HTTPException

from .config import get_settings
from .locks import acquire_lock, assert_ops_respect_locks, release_lock
from .models import OperationEnvelope, OperationsResult, Scene, SoftLockResult
from .ops import OpApplyError, apply_operations
from .seed import fresh_demo_scene

# Main uvicorn loop — set on app startup so sync routes can broadcast safely.
_main_loop: asyncio.AbstractEventLoop | None = None


def set_main_loop(loop: asyncio.AbstractEventLoop | None) -> None:
    global _main_loop
    _main_loop = loop


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


class SceneStore:
    def __init__(self, backend: SceneBackend | None = None) -> None:
        self._backend = backend or MemoryBackend()
        self._backend.ensure_seed()
        self._apply_lock = threading.RLock()

    def get_scene(self, scene_id: str) -> Scene:
        scene = self._backend.get(scene_id)
        if scene is None:
            raise HTTPException(status_code=404, detail=f'Scene {scene_id} not found')
        return scene

    def put_scene(self, scene: Scene) -> Scene:
        """Upsert a full normalized scene (e.g. RoomPlan export from iOS)."""
        with self._apply_lock:
            existing = self._backend.get(scene.scene_id)
            stored = scene.model_copy(deep=True)
            if existing is not None:
                stored.version = max(existing.version + 1, stored.version)
            elif stored.version < 1:
                stored.version = 1
            self._backend.put(stored)
            self._schedule_coro(self._broadcast_scene(stored))
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
            self._schedule_coro(
                self._broadcast_patch(updated, envelope.operations, from_version)
            )
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
