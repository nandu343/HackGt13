"""Catalog mesh generation + static media serving helpers."""

from __future__ import annotations

from fastapi import APIRouter, HTTPException
from fastapi.responses import FileResponse

from ..mesh import ensure_product_mesh, mesh_storage_dir
from ..models.base import CamelModel
from ..seed import DEMO_CATALOG

router = APIRouter(tags=['mesh'])


class MeshResponse(CamelModel):
    product_id: str
    status: str
    provider: str | None = None
    model_url: str | None = None
    model_url_usdz: str | None = None
    model_url_glb: str | None = None
    message: str | None = None


def _safe_mesh_name(filename: str) -> str:
    name = filename.replace('\\', '/').split('/')[-1]
    if not name or '..' in name or not (
        name.endswith('.glb') or name.endswith('.usdz')
    ):
        raise HTTPException(status_code=400, detail='Invalid mesh filename')
    return name


@router.post('/catalog/{product_id}/mesh', response_model=MeshResponse)
def generate_product_mesh(product_id: str, force: bool = False) -> MeshResponse:
    """Generate / cache a 1:1 product lookalike mesh.

    - Always writes a local keyword+dimension GLB under `storage/meshes/`.
    - When `MESHY_API_KEY` is set, kicks a background Meshy text-to-3D job (GLB+USDZ).
    """
    item = next((p for p in DEMO_CATALOG if p.product_id == product_id), None)
    if item is None:
        raise HTTPException(status_code=404, detail=f'Unknown product {product_id}')
    result = ensure_product_mesh(item, force=force)
    return MeshResponse(
        product_id=result.product_id,
        status=result.status,
        provider=result.provider,
        model_url=result.model_url,
        model_url_usdz=result.model_url_usdz,
        model_url_glb=result.model_url_glb,
        message=result.message,
    )


@router.get('/media/meshes/{filename}')
def get_mesh_file(filename: str):
    """Serve cached GLB/USDZ lookalikes."""
    safe = _safe_mesh_name(filename)
    path = mesh_storage_dir() / safe
    if not path.is_file():
        raise HTTPException(status_code=404, detail='Mesh not found')
    media = 'model/gltf-binary' if safe.endswith('.glb') else 'model/vnd.usdz+zip'
    return FileResponse(path, media_type=media, filename=safe)
