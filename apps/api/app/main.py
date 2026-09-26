from fastapi import FastAPI
from pydantic import BaseModel

app = FastAPI(title='Shared Spatial AI API', version='0.1.0')


class SceneOperation(BaseModel):
    type: str
    object_id: str | None = None
    target_position: list[float] | None = None
    asset_id: str | None = None
    product_id: str | None = None


class LayoutRequest(BaseModel):
    prompt: str
    guest_count: int = 15
    budget: float = 150.0


@app.get('/health')
def health():
    return {'status': 'ok', 'service': 'shared-spatial-ai-api'}


@app.get('/scene')
def get_scene():
    return {
        'sceneId': 'scene_party_001',
        'version': 1,
        'bounds': {'width': 5.42, 'length': 6.31, 'height': 2.68},
        'objects': [
            {'id': 'sofa_1', 'type': 'sofa', 'position': [1.2, 0, -1.4], 'dimensions': [2.1, 0.82, 0.91]},
            {'id': 'lamp_17', 'type': 'lamp', 'position': [-1.6, 0, 2.1], 'dimensions': [0.4, 1.72, 0.4]},
            {'id': 'table_05', 'type': 'table', 'position': [1.5, 0, 0.2], 'dimensions': [1.4, 0.75, 1.1]}
        ]
    }


@app.post('/ai/layout')
def generate_layout(payload: LayoutRequest):
    return {
        'scenario': 'party',
        'reasoning_summary': 'Create open central floor area and move seating toward perimeter.',
        'operations': [
            {'type': 'MOVE_OBJECT', 'object_id': 'sofa_1', 'target_position': [2.1, 0, -2.2]},
            {'type': 'ADD_OBJECT', 'asset_id': 'party_lights_03', 'target_position': [0, 2.4, -3.0]},
            {'type': 'ADD_PRODUCT', 'product_id': 'backdrop_12', 'target_position': [-2.2, 0, -2.9]}
        ],
        'constraints': {
            'budget': payload.budget,
            'guest_count': payload.guest_count,
            'must_have': ['dance_space', 'photo_area']
        }
    }


@app.post('/scene/operations')
def apply_scene_operations(operations: list[SceneOperation]):
    return {
        'accepted': True,
        'applied': len(operations),
        'operations': [op.model_dump(exclude_none=True) for op in operations]
    }
