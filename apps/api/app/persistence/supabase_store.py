"""Optional Supabase Postgres persistence.

Configured via SCENE_STORE=supabase plus SUPABASE_URL / SUPABASE_SERVICE_KEY
or SUPABASE_DB_URL. Local runs default to in-memory + FastAPI WebSocket
(see apps/api/docs/AUTH_REALTIME.md). When env is set, this client upserts
scene payloads; Realtime presence/locks are documented for the web client.
"""

from __future__ import annotations

from ..config import get_settings
from ..models import Scene
from ..seed import fresh_demo_scene


class SupabaseBackend:
    """REST-backed scene store. Falls back to an in-process dict on remote errors.

    Auth (magic link / anonymous), project membership, and Realtime channels
    live on the Supabase client side — see migrations/002_auth_realtime.sql.
    """

    def __init__(self) -> None:
        settings = get_settings()
        if not settings.supabase_url and not settings.supabase_db_url:
            raise RuntimeError('Supabase env vars not configured')
        self._url = settings.supabase_url
        self._key = settings.supabase_service_key
        self._db_url = settings.supabase_db_url
        self._client = None
        if self._url and self._key:
            try:
                from supabase import create_client  # type: ignore

                self._client = create_client(self._url, self._key)
            except ImportError as exc:
                raise RuntimeError(
                    'supabase package not installed; pip install supabase or use SCENE_STORE=memory'
                ) from exc
        else:
            raise RuntimeError(
                'Supabase REST client requires SUPABASE_URL and SUPABASE_SERVICE_KEY; '
                'use SCENE_STORE=memory for local demo'
            )
        self._memory_fallback: dict[str, Scene] = {}

    def ensure_seed(self) -> None:
        existing = self.get('scene_party_001')
        if existing is None:
            self.put(fresh_demo_scene())

    def get(self, scene_id: str) -> Scene | None:
        if self._client is None:
            return self._memory_fallback.get(scene_id)
        try:
            response = (
                self._client.table('scenes')
                .select('payload')
                .eq('scene_id', scene_id)
                .limit(1)
                .execute()
            )
            rows = response.data or []
            if not rows:
                return None
            return Scene.model_validate(rows[0]['payload'])
        except Exception:
            return self._memory_fallback.get(scene_id)

    def put(self, scene: Scene) -> None:
        payload = scene.model_dump(by_alias=True)
        self._memory_fallback[scene.scene_id] = scene.model_copy(deep=True)
        if self._client is None:
            return
        try:
            self._client.table('scenes').upsert(
                {
                    'scene_id': scene.scene_id,
                    'version': scene.version,
                    'room_id': scene.room_id,
                    'payload': payload,
                }
            ).execute()
        except Exception:
            # Keep local fallback so apply still works if remote is down
            pass
