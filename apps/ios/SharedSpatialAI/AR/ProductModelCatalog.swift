import Foundation

/// Catalog ↔ 3D asset mapping (mirrors `apps/web/lib/modelAssets.ts` + API `model_assets.py`).
/// Web serves GLB under `/models/*.glb`; iOS prefers matching USDZ in the bundle
/// (`SharedSpatialAI/Models/*.usdz`) or a product-specific RealityKit composite.
enum ProductModelCatalog {
    /// Distinct mesh family per purchasable SKU (and virtual helpers).
    enum MeshKey: String, CaseIterable {
        case loungeSofa
        case foldingLoungeChair
        case diningChair
        case barStool
        case beanbag
        case coffeeTable
        case studyDesk
        case diningTable
        case arcFloorLamp
        case stringLights
        case taskDeskLamp
        case pendant
        case photoBackdrop
        case tallPlant
        case danceRug
        case projectorScreen
        case layoutMarker
        case glowOrb
        case wall
        case generic
    }

    /// Basename without extension — same as web GLB stem (e.g. `sofa` ↔ `sofa.glb` / `sofa.usdz`).
    static let productAssetStem: [String: String] = [
        "product_sofa_01": "sofa",
        "chair_fold_01": "loungeChair",
        "chair_dining_02": "chairDesk",
        "stool_bar_01": "stool",
        "beanbag_01": "beanbag",
        "product_table_05": "table",
        "desk_study_01": "desk",
        "table_dining_01": "sideTable",
        "product_39": "lampRoundFloor",
        "party_lights_03": "string_lights",
        "lamp_desk_01": "lampSquareTable",
        "pendant_dinner_01": "pendant",
        "backdrop_12": "backdrop",
        "plant_tall_02": "pottedPlant",
        "rug_party_01": "rugRectangle",
        "projector_screen_01": "projector_screen"
    ]

    static let assetIdStem: [String: String] = [
        "asset_sofa_01": "sofa",
        "asset_chair_fold_01": "loungeChair",
        "asset_chair_dining_02": "chairDesk",
        "asset_stool_bar_01": "stool",
        "asset_beanbag_01": "beanbag",
        "asset_table_05": "table",
        "asset_desk_study_01": "desk",
        "asset_table_dining_01": "sideTable",
        "asset_lamp_12": "lampRoundFloor",
        "asset_party_lights_03": "string_lights",
        "asset_lamp_desk_01": "lampSquareTable",
        "asset_pendant_dinner_01": "pendant",
        "asset_backdrop_12": "backdrop",
        "asset_plant_tall_02": "pottedPlant",
        "asset_rug_party_01": "rugRectangle",
        "asset_projector_screen_01": "projector_screen"
    ]

    static let stemToMeshKey: [String: MeshKey] = [
        "sofa": .loungeSofa,
        "loungeChair": .foldingLoungeChair,
        "chairDesk": .diningChair,
        "stool": .barStool,
        "beanbag": .beanbag,
        "table": .coffeeTable,
        "desk": .studyDesk,
        "sideTable": .diningTable,
        "lampRoundFloor": .arcFloorLamp,
        "string_lights": .stringLights,
        "lampSquareTable": .taskDeskLamp,
        "pendant": .pendant,
        "backdrop": .photoBackdrop,
        "pottedPlant": .tallPlant,
        "rugRectangle": .danceRug,
        "projector_screen": .projectorScreen
    ]

    static let productToMeshKey: [String: MeshKey] = [
        "product_sofa_01": .loungeSofa,
        "chair_fold_01": .foldingLoungeChair,
        "chair_dining_02": .diningChair,
        "stool_bar_01": .barStool,
        "beanbag_01": .beanbag,
        "product_table_05": .coffeeTable,
        "desk_study_01": .studyDesk,
        "table_dining_01": .diningTable,
        "product_39": .arcFloorLamp,
        "party_lights_03": .stringLights,
        "lamp_desk_01": .taskDeskLamp,
        "pendant_dinner_01": .pendant,
        "backdrop_12": .photoBackdrop,
        "plant_tall_02": .tallPlant,
        "rug_party_01": .danceRug,
        "projector_screen_01": .projectorScreen,
        "virtual_marker_01": .layoutMarker,
        "virtual_glow_orb": .glowOrb
    ]

    /// Resolve mesh key for a scene object (productId → assetId → modelUrl stem → type heuristics).
    static func meshKey(for object: SceneObjectDTO) -> MeshKey {
        if object.type.lowercased() == "wall" { return .wall }
        if let pid = object.productId, let key = productToMeshKey[pid] { return key }
        if let aid = object.assetId, let stem = assetIdStem[aid], let key = stemToMeshKey[stem] {
            return key
        }
        if let stem = assetStem(fromModelUrl: object.modelUrl), let key = stemToMeshKey[stem] {
            return key
        }
        return meshKeyFromType(object.type)
    }

    /// Preferred USDZ / GLB basename for bundle or `/models/{stem}.usdz`.
    static func assetStem(for object: SceneObjectDTO) -> String? {
        if let pid = object.productId, let stem = productAssetStem[pid] { return stem }
        if let aid = object.assetId, let stem = assetIdStem[aid] { return stem }
        return assetStem(fromModelUrl: object.modelUrl)
    }

    static func assetStem(fromModelUrl url: String?) -> String? {
        guard let url, !url.isEmpty else { return nil }
        let base = (url as NSString).lastPathComponent
        let stem = (base as NSString).deletingPathExtension
        return stem.isEmpty ? nil : stem
    }

    private static func meshKeyFromType(_ type: String) -> MeshKey {
        let t = type.lowercased()
        if t.contains("sofa") || t.contains("couch") { return .loungeSofa }
        if t.contains("bean") { return .beanbag }
        if t.contains("stool") || t.contains("bar") { return .barStool }
        if t.contains("fold") { return .foldingLoungeChair }
        if t.contains("dining") && t.contains("chair") { return .diningChair }
        if t.contains("chair") { return .foldingLoungeChair }
        if t.contains("desk") { return .studyDesk }
        if t.contains("dining") && t.contains("table") { return .diningTable }
        if t.contains("coffee") || (t.contains("table") && !t.contains("side")) { return .coffeeTable }
        if t.contains("table") { return .coffeeTable }
        if t.contains("string") || t.contains("party_light") { return .stringLights }
        if t.contains("pendant") { return .pendant }
        if t.contains("desk") && t.contains("lamp") { return .taskDeskLamp }
        if t.contains("task") { return .taskDeskLamp }
        if t.contains("arc") || t.contains("floor_lamp") || t.contains("floor lamp") {
            return .arcFloorLamp
        }
        if t.contains("lamp") || t.contains("light") { return .arcFloorLamp }
        if t.contains("plant") { return .tallPlant }
        if t.contains("rug") { return .danceRug }
        if t.contains("backdrop") || t.contains("photo") { return .photoBackdrop }
        if t.contains("screen") || t.contains("projector") { return .projectorScreen }
        if t.contains("marker") { return .layoutMarker }
        if t.contains("glow") || t.contains("orb") { return .glowOrb }
        return .generic
    }
}
