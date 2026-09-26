from fastapi import APIRouter

from ..models import CatalogItem
from ..seed import DEMO_CATALOG

router = APIRouter(tags=['catalog'])


@router.get('/catalog', response_model=list[CatalogItem])
def get_catalog() -> list[CatalogItem]:
    return DEMO_CATALOG
