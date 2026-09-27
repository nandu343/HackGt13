# Optional USDZ furniture (iOS)

Ship matching `.usdz` files here (same basenames as web GLBs, e.g. `sofa.usdz`)
to load via RealityKit when `modelUrl` ends in `.usdz`.

Until then, Live AR and the map twin use `FurnitureMeshBuilder` multi-mesh
composites (sofa with arms/back, tables with legs, lamps with shade, etc.).

Web continues to use GLB under `apps/web/public/models/`.
