from fastapi import APIRouter

from .ai import router as ai_router
from .catalog import router as catalog_router
from .commerce import router as commerce_router
from .health import router as health_router
from .invite import router as invite_router
from .mesh import router as mesh_router
from .scene import router as scene_router
from .ws import router as ws_router

api_router = APIRouter()
api_router.include_router(health_router)
api_router.include_router(invite_router)
api_router.include_router(scene_router)
api_router.include_router(ai_router)
api_router.include_router(catalog_router)
api_router.include_router(mesh_router)
api_router.include_router(commerce_router)
api_router.include_router(ws_router)
