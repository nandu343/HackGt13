"""Ensure a product has a cached lookalike mesh under storage/meshes/."""

from __future__ import annotations

import logging
import threading
from dataclasses import dataclass
from pathlib import Path

from ..config import get_settings
from ..models import CatalogItem
from .local_generator import build_product_glb
from . import meshy_client

log = logging.getLogger(__name__)

# In-flight generation locks per product
_locks: dict[str, threading.Lock] = {}
_locks_guard = threading.Lock()


@dataclass
class MeshResult:
    product_id: str
    status: str  # ready | generating | error
    provider: str
    model_url: str | None = None
    model_url_glb: str | None = None
    model_url_usdz: str | None = None
    message: str | None = None


def mesh_storage_dir() -> Path:
    # apps/api/storage/meshes
    root = Path(__file__).resolve().parents[2] / 'storage' / 'meshes'
    root.mkdir(parents=True, exist_ok=True)
    return root


def _product_lock(product_id: str) -> threading.Lock:
    with _locks_guard:
        if product_id not in _locks:
            _locks[product_id] = threading.Lock()
        return _locks[product_id]


def _prompt_for(item: CatalogItem) -> str:
    dims = item.dimensions
    dim_txt = ''
    if dims:
        dim_txt = (
            f' Exact real-world size {dims.width:.2f}m wide × '
            f'{dims.height:.2f}m tall × {dims.depth:.2f}m deep.'
        )
    desc = item.description or ''
    tags = ', '.join(item.tags or [])
    return (
        f'Photorealistic product 3D model of "{item.name}". {desc} '
        f'Category tags: {tags}.{dim_txt} '
        f'Studio product shot, clean geometry, no people, centered on ground.'
    )


def ensure_product_mesh(item: CatalogItem, *, force: bool = False) -> MeshResult:
    """Return cached mesh URLs; generate local GLB immediately; kick Meshy in background when keyed."""
    pid = item.product_id
    store = mesh_storage_dir()
    glb_path = store / f'{pid}.glb'
    usdz_path = store / f'{pid}.usdz'

    with _product_lock(pid):
        settings = get_settings()
        if force or not glb_path.exists():
            w = float(item.dimensions.width) if item.dimensions and item.dimensions.width else 0.6
            h = float(item.dimensions.height) if item.dimensions and item.dimensions.height else 0.6
            d = float(item.dimensions.depth) if item.dimensions and item.dimensions.depth else 0.6
            glb_bytes = build_product_glb(
                name=item.name,
                description=item.description,
                width=w,
                height=h,
                depth=d,
                tags=item.tags,
            )
            glb_path.write_bytes(glb_bytes)
            log.info('Wrote local lookalike GLB for %s (%d bytes)', pid, len(glb_bytes))

        # Optional Meshy upgrade (background) when API key present and no USDZ yet
        if settings.meshy_api_key and (force or not usdz_path.exists()):
            threading.Thread(
                target=_meshy_job,
                args=(item, settings.meshy_api_key),
                daemon=True,
                name=f'meshy-{pid}',
            ).start()
            provider = 'meshy_pending' if not usdz_path.exists() else 'meshy'
            msg = 'Local lookalike ready; Meshy USDZ generating in background'
        else:
            provider = 'local'
            msg = (
                'Local keyword+dimension lookalike GLB'
                if not settings.meshy_api_key
                else 'Cached mesh'
            )

        glb_url = f'/media/meshes/{pid}.glb'
        usdz_url = f'/media/meshes/{pid}.usdz' if usdz_path.exists() else None
        # Prefer USDZ for iOS when present; GLB for web; modelUrl = best available
        primary = usdz_url or glb_url
        # Also keep catalog-style /models fallback if no generated file somehow
        return MeshResult(
            product_id=pid,
            status='ready',
            provider=provider,
            model_url=primary,
            model_url_glb=glb_url if glb_path.exists() else None,
            model_url_usdz=usdz_url,
            message=msg,
        )


def _meshy_job(item: CatalogItem, api_key: str) -> None:
    pid = item.product_id
    store = mesh_storage_dir()
    try:
        urls = meshy_client.create_text_to_3d(api_key=api_key, prompt=_prompt_for(item))
        if urls.glb:
            (store / f'{pid}.glb').write_bytes(
                meshy_client.download_bytes(urls.glb, api_key=api_key)
            )
        if urls.usdz:
            (store / f'{pid}.usdz').write_bytes(
                meshy_client.download_bytes(urls.usdz, api_key=api_key)
            )
        log.info('Meshy mesh cached for %s (glb=%s usdz=%s)', pid, bool(urls.glb), bool(urls.usdz))
    except Exception as exc:  # noqa: BLE001 — background job must not crash process
        log.warning('Meshy job failed for %s: %s', pid, exc)
