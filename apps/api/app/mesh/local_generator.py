"""Minimal glTF 2.0 binary (GLB) writer — product-specific box assemblies, no deps."""

from __future__ import annotations

import json
import struct
from typing import Iterable


def _pack_glb(gltf_json: dict, bin_blob: bytes) -> bytes:
    json_bytes = json.dumps(gltf_json, separators=(',', ':')).encode('utf-8')
    # Pad JSON to 4-byte boundary with spaces
    while len(json_bytes) % 4:
        json_bytes += b' '
    # Pad BIN to 4-byte boundary with zeros
    bin_padded = bin_blob
    while len(bin_padded) % 4:
        bin_padded += b'\x00'

    total = 12 + 8 + len(json_bytes) + 8 + len(bin_padded)
    header = struct.pack('<4sII', b'glTF', 2, total)
    json_chunk = struct.pack('<I4s', len(json_bytes), b'JSON') + json_bytes
    bin_chunk = struct.pack('<I4s', len(bin_padded), b'BIN\x00') + bin_padded
    return header + json_chunk + bin_chunk


def _box_mesh(
    cx: float,
    cy: float,
    cz: float,
    sx: float,
    sy: float,
    sz: float,
    color: tuple[float, float, float],
) -> tuple[bytes, dict, list[float]]:
    """Axis-aligned box centered at (cx,cy,cz) with size (sx,sy,sz). Returns bin, mesh def, min/max."""
    hx, hy, hz = sx * 0.5, sy * 0.5, sz * 0.5
    # 8 corners
    corners = [
        (cx - hx, cy - hy, cz - hz),
        (cx + hx, cy - hy, cz - hz),
        (cx + hx, cy + hy, cz - hz),
        (cx - hx, cy + hy, cz - hz),
        (cx - hx, cy - hy, cz + hz),
        (cx + hx, cy - hy, cz + hz),
        (cx + hx, cy + hy, cz + hz),
        (cx - hx, cy + hy, cz + hz),
    ]
    # 12 triangles (36 indices) — outward faces
    faces = [
        0, 1, 2, 0, 2, 3,  # -Z
        5, 4, 7, 5, 7, 6,  # +Z
        4, 0, 3, 4, 3, 7,  # -X
        1, 5, 6, 1, 6, 2,  # +X
        3, 2, 6, 3, 6, 7,  # +Y
        4, 5, 1, 4, 1, 0,  # -Y
    ]
    positions: list[float] = []
    colors: list[float] = []
    indices: list[int] = []
    for i, (a, b, c) in enumerate(zip(faces[0::3], faces[1::3], faces[2::3])):
        base = len(positions) // 3
        for vi in (a, b, c):
            positions.extend(corners[vi])
            colors.extend([*color, 1.0])
        indices.extend([base, base + 1, base + 2])

    pos_bytes = struct.pack(f'<{len(positions)}f', *positions)
    col_bytes = struct.pack(f'<{len(colors)}f', *colors)
    idx_bytes = struct.pack(f'<{len(indices)}H', *indices)
    # Align idx to 4 bytes for subsequent accessors if needed — we'll concat carefully
    while len(idx_bytes) % 4:
        idx_bytes += b'\x00'

    blob = pos_bytes + col_bytes + idx_bytes
    pos_len = len(pos_bytes)
    col_len = len(col_bytes)
    # Actual index count before padding
    index_count = len(indices)
    index_byte_len = index_count * 2

    mins = [cx - hx, cy - hy, cz - hz]
    maxs = [cx + hx, cy + hy, cz + hz]
    meta = {
        'pos_offset': 0,
        'pos_len': pos_len,
        'col_offset': pos_len,
        'col_len': col_len,
        'idx_offset': pos_len + col_len,
        'idx_len': index_byte_len,
        'vertex_count': len(positions) // 3,
        'index_count': index_count,
        'mins': mins,
        'maxs': maxs,
        'blob': blob,
    }
    return blob, meta, mins + maxs


def build_product_glb(
    *,
    name: str,
    description: str | None,
    width: float,
    height: float,
    depth: float,
    tags: Iterable[str] | None = None,
) -> bytes:
    """Build a lookalike GLB from product keywords + exact catalog meters (Y-up)."""
    text = f'{name} {description or ""} {" ".join(tags or [])}'.lower()
    w, h, d = max(width, 0.05), max(height, 0.05), max(depth, 0.05)
    parts: list[tuple[float, float, float, float, float, float, tuple[float, float, float]]] = []

    def add(cx, cy, cz, sx, sy, sz, rgb):
        parts.append((cx, cy, cz, sx, sy, sz, rgb))

    wood = (0.55, 0.38, 0.22)
    fabric = (0.25, 0.45, 0.48)
    metal = (0.55, 0.55, 0.58)
    green = (0.2, 0.55, 0.28)
    cream = (0.85, 0.82, 0.75)

    if any(k in text for k in ('sofa', 'couch', 'loveseat', 'sectional')):
        add(0, h * 0.18, 0, w * 0.98, h * 0.28, d * 0.88, fabric)
        add(0, h * 0.38, -d * 0.32, w * 0.96, h * 0.52, d * 0.18, fabric)
        add(-w * 0.42, h * 0.32, 0.02, w * 0.12, h * 0.38, d * 0.85, fabric)
        add(w * 0.42, h * 0.32, 0.02, w * 0.12, h * 0.38, d * 0.85, fabric)
        for i in range(3):
            x = -w * 0.28 + i * (w * 0.28)
            add(x, h * 0.34, 0.05, w * 0.26, h * 0.12, d * 0.55, (0.3, 0.5, 0.52))
        for sx in (-1, 1):
            for sz in (-1, 1):
                add(sx * w * 0.4, h * 0.04, sz * d * 0.35, 0.06, h * 0.08, 0.06, wood)
    elif any(k in text for k in ('bean', 'pouf')):
        add(0, h * 0.4, 0, w * 0.95, h * 0.8, d * 0.95, (0.55, 0.25, 0.7))
        add(0, h * 0.75, 0, w * 0.45, h * 0.25, d * 0.45, (0.6, 0.3, 0.75))
    elif 'stool' in text or 'bar seat' in text:
        add(0, h * 0.88, 0, w * 0.9, h * 0.08, d * 0.9, wood)
        add(0, h * 0.45, 0, 0.07, h * 0.7, 0.07, metal)
        add(0, h * 0.05, 0, w * 0.55, 0.04, d * 0.55, metal)
    elif 'chair' in text and 'fold' in text:
        add(0, h * 0.42, 0, w * 0.9, h * 0.08, d * 0.85, fabric)
        add(0, h * 0.62, -d * 0.35, w * 0.88, h * 0.48, 0.06, fabric)
        add(-w * 0.2, h * 0.35, 0, 0.04, h * 0.7, 0.04, metal)
        add(w * 0.2, h * 0.35, 0, 0.04, h * 0.7, 0.04, metal)
    elif 'chair' in text:
        add(0, h * 0.42, 0, w * 0.9, max(h * 0.08, 0.04), d * 0.85, wood)
        add(0, h * 0.7, -d * 0.38, w * 0.88, h * 0.5, 0.05, wood)
        for sx in (-1, 1):
            for sz in (-1, 1):
                add(sx * w * 0.35, h * 0.2, sz * d * 0.35, 0.04, h * 0.4, 0.04, wood)
    elif any(k in text for k in ('desk', 'workstation')):
        add(0, h * 0.92, 0, w, max(h * 0.06, 0.035), d, wood)
        add(-w * 0.35, h * 0.55, 0, w * 0.28, h * 0.55, d * 0.85, wood)
        for sx in (-1, 1):
            for sz in (-1, 1):
                add(sx * w * 0.42, h * 0.4, sz * d * 0.38, 0.05, h * 0.8, 0.05, wood)
    elif any(k in text for k in ('table', 'coffee')):
        add(0, h * 0.92, 0, w, max(h * 0.07, 0.04), d, wood)
        for sx in (-1, 1):
            for sz in (-1, 1):
                add(sx * w * 0.4, h * 0.42, sz * d * 0.38, 0.07, h * 0.82, 0.07, wood)
    elif any(k in text for k in ('pendant', 'chandelier')):
        add(0, h * 0.15, 0, 0.03, h * 0.35, 0.03, metal)
        add(0, h * 0.55, 0, w * 0.9, h * 0.45, d * 0.9, cream)
    elif any(k in text for k in ('string', 'fairy', 'party light')):
        add(0, h * 0.5, 0, w, 0.02, 0.02, metal)
        for i in range(6):
            t = (i + 0.5) / 6
            add(-w * 0.45 + t * w, h * 0.35, 0, 0.06, 0.06, 0.06, (1, 0.85, 0.3))
    elif any(k in text for k in ('lamp', 'light', 'floor lamp', 'arc')):
        add(0, h * 0.05, 0, w * 0.45, 0.05, d * 0.45, metal)
        add(0, h * 0.45, 0, 0.04, h * 0.75, 0.04, metal)
        add(0, h * 0.88, 0, w * 0.55, h * 0.18, d * 0.55, cream)
    elif 'plant' in text:
        add(0, h * 0.12, 0, w * 0.45, h * 0.22, d * 0.45, (0.45, 0.28, 0.18))
        add(0, h * 0.55, 0, w * 0.55, h * 0.55, d * 0.55, green)
        add(0, h * 0.85, 0.05, w * 0.35, h * 0.25, d * 0.35, (0.25, 0.6, 0.3))
    elif any(k in text for k in ('rug', 'mat', 'carpet')):
        add(0, h * 0.5, 0, w, max(h, 0.02), d, (0.35, 0.5, 0.4))
        add(0, h * 0.6, 0, w * 0.7, max(h, 0.02), d * 0.7, (0.4, 0.55, 0.45))
    elif any(k in text for k in ('backdrop', 'photo', 'screen', 'projector')):
        add(0, h * 0.5, 0, w, h, max(d, 0.04), cream)
        add(0, 0.03, 0, w * 0.9, 0.04, max(d, 0.2), metal)
    else:
        # Distinct generic: beveled box + accent strip from name hash
        hue = (sum(ord(c) for c in name) % 50) / 50.0
        base = (0.3 + hue * 0.4, 0.35, 0.55 - hue * 0.2)
        add(0, h * 0.5, 0, w, h, d, base)
        add(0, h * 0.92, 0, w * 0.9, h * 0.08, d * 0.9, (base[0] + 0.1, base[1] + 0.1, base[2]))

    # Assemble multi-primitive GLB
    blobs: list[bytes] = []
    accessors = []
    buffer_views = []
    meshes_primitives = []
    offset = 0
    global_min = [1e9, 1e9, 1e9]
    global_max = [-1e9, -1e9, -1e9]

    for cx, cy, cz, sx, sy, sz, rgb in parts:
        blob, meta, _ = _box_mesh(cx, cy, cz, sx, sy, sz, rgb)
        # Shift cy so object sits on y=0 floor (bottom at 0)
        # Parts already use cy relative to product height with bottom near 0.

        for i in range(3):
            global_min[i] = min(global_min[i], meta['mins'][i])
            global_max[i] = max(global_max[i], meta['maxs'][i])

        bv_pos = len(buffer_views)
        buffer_views.append(
            {'buffer': 0, 'byteOffset': offset + meta['pos_offset'], 'byteLength': meta['pos_len'], 'target': 34962}
        )
        buffer_views.append(
            {'buffer': 0, 'byteOffset': offset + meta['col_offset'], 'byteLength': meta['col_len'], 'target': 34962}
        )
        buffer_views.append(
            {'buffer': 0, 'byteOffset': offset + meta['idx_offset'], 'byteLength': meta['idx_len'], 'target': 34963}
        )
        acc_pos = len(accessors)
        accessors.append(
            {
                'bufferView': bv_pos,
                'componentType': 5126,
                'count': meta['vertex_count'],
                'type': 'VEC3',
                'max': meta['maxs'],
                'min': meta['mins'],
            }
        )
        accessors.append(
            {
                'bufferView': bv_pos + 1,
                'componentType': 5126,
                'count': meta['vertex_count'],
                'type': 'VEC4',
            }
        )
        accessors.append(
            {
                'bufferView': bv_pos + 2,
                'componentType': 5123,
                'count': meta['index_count'],
                'type': 'SCALAR',
            }
        )
        meshes_primitives.append(
            {
                'attributes': {'POSITION': acc_pos, 'COLOR_0': acc_pos + 1},
                'indices': acc_pos + 2,
                'mode': 4,
            }
        )
        blobs.append(meta['blob'])
        offset += len(meta['blob'])

    bin_blob = b''.join(blobs)
    # Lift so min Y == 0 (floor contact)
    # Already authored near floor; skip transform for simplicity.

    gltf = {
        'asset': {'version': '2.0', 'generator': 'SharedSpatialAI-local-lookalike'},
        'buffers': [{'byteLength': len(bin_blob)}],
        'bufferViews': buffer_views,
        'accessors': accessors,
        'meshes': [{'name': name[:48] or 'product', 'primitives': meshes_primitives}],
        'nodes': [{'mesh': 0, 'name': name[:48] or 'product'}],
        'scenes': [{'nodes': [0]}],
        'scene': 0,
    }
    return _pack_glb(gltf, bin_blob)
