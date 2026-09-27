"""Meshy.ai text-to-3D client (optional — requires MESHY_API_KEY)."""

from __future__ import annotations

import json
import time
import urllib.error
import urllib.request
from dataclasses import dataclass


MESHY_BASE = 'https://api.meshy.ai/openapi/v2'


@dataclass
class MeshyUrls:
    glb: str | None = None
    usdz: str | None = None


def create_text_to_3d(
    *,
    api_key: str,
    prompt: str,
    timeout_seconds: float = 90.0,
) -> MeshyUrls:
    """Create a Meshy preview task, poll until done, return model download URLs."""
    body = {
        'mode': 'preview',
        'prompt': prompt[:600],
        'art_style': 'realistic',
        'should_remesh': True,
        'topology': 'triangle',
        'target_polycount': 12000,
    }
    task_id = _post_json(
        f'{MESHY_BASE}/text-to-3d',
        body,
        api_key=api_key,
    ).get('result')
    if not task_id:
        raise RuntimeError('Meshy did not return a task id')

    deadline = time.time() + timeout_seconds
    while time.time() < deadline:
        data = _get_json(f'{MESHY_BASE}/text-to-3d/{task_id}', api_key=api_key)
        status = (data.get('status') or '').upper()
        if status == 'SUCCEEDED':
            urls = data.get('model_urls') or {}
            return MeshyUrls(glb=urls.get('glb'), usdz=urls.get('usdz'))
        if status in ('FAILED', 'CANCELED'):
            raise RuntimeError(f'Meshy task {status}: {data.get("task_error")}')
        time.sleep(2.5)
    raise TimeoutError('Meshy text-to-3D timed out')


def download_bytes(url: str, *, api_key: str | None = None) -> bytes:
    req = urllib.request.Request(url, headers=_headers(api_key))
    with urllib.request.urlopen(req, timeout=60) as resp:
        return resp.read()


def _headers(api_key: str | None) -> dict[str, str]:
    h = {'Content-Type': 'application/json', 'Accept': 'application/json'}
    if api_key:
        h['Authorization'] = f'Bearer {api_key}'
    return h


def _post_json(url: str, body: dict, *, api_key: str) -> dict:
    data = json.dumps(body).encode('utf-8')
    req = urllib.request.Request(url, data=data, headers=_headers(api_key), method='POST')
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read().decode('utf-8'))
    except urllib.error.HTTPError as e:
        detail = e.read().decode('utf-8', errors='replace')
        raise RuntimeError(f'Meshy POST {e.code}: {detail[:200]}') from e


def _get_json(url: str, *, api_key: str) -> dict:
    req = urllib.request.Request(url, headers=_headers(api_key))
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read().decode('utf-8'))
    except urllib.error.HTTPError as e:
        detail = e.read().decode('utf-8', errors='replace')
        raise RuntimeError(f'Meshy GET {e.code}: {detail[:200]}') from e
