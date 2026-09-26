from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .config import get_settings
from .routers import api_router
from .store import get_store, set_main_loop

app = FastAPI(title='Shared Spatial AI API', version='0.3.0')

settings = get_settings()
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=['*'],
    allow_headers=['*'],
)

app.include_router(api_router)


@app.on_event('startup')
async def on_startup() -> None:
    import asyncio

    set_main_loop(asyncio.get_running_loop())
    get_store()
