from __future__ import annotations

import os
from functools import lru_cache
from pathlib import Path


def _load_dotenv() -> None:
    try:
        from dotenv import load_dotenv
    except ImportError:
        return
    # Prefer repo-root .env, then apps/api/.env
    root = Path(__file__).resolve().parents[3]
    load_dotenv(root / '.env')
    load_dotenv(Path(__file__).resolve().parents[1] / '.env', override=False)


_load_dotenv()


@lru_cache
def get_settings() -> 'Settings':
    return Settings()


class Settings:
    def __init__(self) -> None:
        origins = os.getenv(
            'CORS_ORIGINS',
            'http://localhost:3000,http://127.0.0.1:3000',
        )
        self.cors_origins = [o.strip() for o in origins.split(',') if o.strip()]
        self.scene_store = os.getenv('SCENE_STORE', 'memory').lower()
        self.supabase_url = os.getenv('SUPABASE_URL', '').strip()
        self.supabase_service_key = os.getenv('SUPABASE_SERVICE_KEY', '').strip()
        self.supabase_db_url = os.getenv('SUPABASE_DB_URL', '').strip()
        # xAI Grok (OpenAI-compatible); OPENAI_API_KEY kept as deprecated alias
        self.xai_api_key = (
            os.getenv('XAI_API_KEY', '').strip()
            or os.getenv('OPENAI_API_KEY', '').strip()
        )
        # Commerce (Phase 4) — Stripe test mode optional; stub otherwise
        self.stripe_secret_key = os.getenv('STRIPE_SECRET_KEY', '').strip()
        self.stripe_success_url = os.getenv(
            'STRIPE_SUCCESS_URL', 'http://localhost:3000/?checkout=success'
        ).strip()
        self.stripe_cancel_url = os.getenv(
            'STRIPE_CANCEL_URL', 'http://localhost:3000/?checkout=cancel'
        ).strip()
        # Soft-lock TTL seconds (Phase 5)
        try:
            self.lock_ttl_seconds = int(os.getenv('LOCK_TTL_SECONDS', '30'))
        except ValueError:
            self.lock_ttl_seconds = 30

    @property
    def use_supabase(self) -> bool:
        return (
            self.scene_store == 'supabase'
            and bool(self.supabase_url)
            and bool(self.supabase_service_key or self.supabase_db_url)
        )

