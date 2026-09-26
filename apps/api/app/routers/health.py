from fastapi import APIRouter

from ..store import get_store

router = APIRouter(tags=['health'])


@router.get('/health')
def health():
    store_mode = 'memory'
    try:
        from ..config import get_settings

        settings = get_settings()
        store_mode = 'supabase' if settings.use_supabase else 'memory'
    except Exception:
        pass
    # Touch store so seed is loaded
    get_store()
    return {
        'status': 'ok',
        'service': 'shared-spatial-ai-api',
        'store': store_mode,
    }
