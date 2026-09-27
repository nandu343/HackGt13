# Optional USDZ furniture (iOS)

Drop matching `.usdz` files here so Live AR loads **photogrammetry / CAD** meshes
instead of RealityKit composites.

## Naming (must match web GLB stems)

| Catalog productId | Bundle / GLB stem | Web path |
|-------------------|-------------------|----------|
| `product_sofa_01` | `sofa` | `/models/sofa.glb` |
| `chair_fold_01` | `loungeChair` | `/models/loungeChair.glb` |
| `chair_dining_02` | `chairDesk` | `/models/chairDesk.glb` |
| `stool_bar_01` | `stool` | `/models/stool.glb` |
| `beanbag_01` | `beanbag` | `/models/beanbag.glb` |
| `product_table_05` | `table` | `/models/table.glb` |
| `desk_study_01` | `desk` | `/models/desk.glb` |
| `table_dining_01` | `sideTable` | `/models/sideTable.glb` |
| `product_39` | `lampRoundFloor` | `/models/lampRoundFloor.glb` |
| `party_lights_03` | `string_lights` | `/models/string_lights.glb` |
| `lamp_desk_01` | `lampSquareTable` | `/models/lampSquareTable.glb` |
| `pendant_dinner_01` | `pendant` | `/models/pendant.glb` |
| `backdrop_12` | `backdrop` | `/models/backdrop.glb` |
| `plant_tall_02` | `pottedPlant` | `/models/pottedPlant.glb` |
| `rug_party_01` | `rugRectangle` | `/models/rugRectangle.glb` |
| `projector_screen_01` | `projector_screen` | `/models/projector_screen.glb` |

Place files as `sofa.usdz`, `loungeChair.usdz`, etc. in this folder (or bundle root).
Add them to the Xcode target (Copy Bundle Resources).

## Scale

`FurnitureMeshBuilder` always fits the loaded USDZ **visual bounds** to catalog
`dimensions` (width × height × depth in **meters**). A 2.1 m sofa is ~2.1 m in AR.

## Converting GLB → USDZ (Mac only)

Windows cannot run Apple's Reality Converter / `usdzconvert`. On a Mac:

```bash
# Reality Converter GUI, or:
xcrun usdzconvert apps/web/public/models/sofa.glb apps/ios/SharedSpatialAI/Models/sofa.usdz
```

Until USDZ files ship, iOS uses **distinct per-SKU RealityKit composites**
(`ProductModelCatalog` → `FurnitureMeshBuilder`) that still read at 1:1 meters.
