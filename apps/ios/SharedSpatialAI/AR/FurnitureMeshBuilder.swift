import RealityKit
import UIKit

/// Multi-mesh furniture proxies for Live AR + map twin.
/// Web uses GLB under `/models`; iOS prefers these RealityKit compositions
/// (optional USDZ can be loaded when `modelUrl` ends in `.usdz`).
enum FurnitureMeshBuilder {
    static func makeEntity(for object: SceneObjectDTO, selected: Bool) -> Entity {
        if let url = object.modelUrl, url.lowercased().hasSuffix(".usdz"),
           let entity = tryLoadUSDZ(url: url, name: object.id)
        {
            entity.position = Coordinates.toSIMD(object.transform.position)
            entity.orientation = Coordinates.toSIMDQuat(object.transform.rotation)
            if selected { addSelectionRing(to: entity, object: object) }
            return entity
        }

        let w = Float(object.dimensions?.width ?? 0.5)
        let h = Float(object.dimensions?.height ?? 0.5)
        let d = Float(object.dimensions?.depth ?? 0.5)
        let parent = Entity()
        parent.name = object.id
        parent.position = Coordinates.toSIMD(object.transform.position)
        parent.orientation = Coordinates.toSIMDQuat(object.transform.rotation)

        let kind = furnitureKind(for: object)
        let baseColor = furnitureColor(for: object, kind: kind)
        let color = selected
            ? (baseColor.withAlphaComponent(1).blended(with: .systemYellow) ?? baseColor)
            : baseColor
        let mat = SimpleMaterial(color: color, isMetallic: kind == .wall)

        switch kind {
        case .wall:
            let wall = ModelEntity(
                mesh: .generateBox(width: w, height: h, depth: max(d, 0.06)),
                materials: [SimpleMaterial(color: UIColor(white: 0.55, alpha: 0.85), isMetallic: false)]
            )
            wall.name = object.id
            parent.addChild(wall)
        case .sofa:
            addSofa(to: parent, w: w, h: h, d: d, mat: mat, name: object.id)
        case .table, .desk:
            addTable(to: parent, w: w, h: h, d: d, mat: mat, name: object.id)
        case .chair, .stool:
            addChair(to: parent, w: w, h: h, d: d, mat: mat, name: object.id, stool: kind == .stool)
        case .lamp:
            addLamp(to: parent, w: w, h: h, d: d, mat: mat, name: object.id)
        case .plant:
            addPlant(to: parent, w: w, h: h, d: d, name: object.id)
        case .rug:
            let rug = ModelEntity(
                mesh: .generateBox(width: w, height: max(h, 0.02), depth: d),
                materials: [SimpleMaterial(color: UIColor(red: 0.35, green: 0.55, blue: 0.4, alpha: 0.9), isMetallic: false)]
            )
            rug.name = object.id
            parent.addChild(rug)
        case .beanbag:
            let bag = ModelEntity(
                mesh: .generateSphere(radius: min(w, d) * 0.45),
                materials: [mat]
            )
            bag.scale = SIMD3(1, 0.75, 1)
            bag.name = object.id
            parent.addChild(bag)
        case .screen, .backdrop:
            let panel = ModelEntity(
                mesh: .generateBox(width: w, height: h, depth: max(d, 0.04)),
                materials: [mat]
            )
            panel.name = object.id
            parent.addChild(panel)
            let bar = ModelEntity(
                mesh: .generateBox(width: w * 1.02, height: 0.06, depth: 0.06),
                materials: [SimpleMaterial(color: .darkGray, isMetallic: true)]
            )
            bar.position.y = h * 0.5
            bar.name = object.id
            parent.addChild(bar)
        case .lights:
            let cable = ModelEntity(
                mesh: .generateBox(width: max(w, 1.2), height: 0.02, depth: 0.02),
                materials: [SimpleMaterial(color: .darkGray, isMetallic: false)]
            )
            cable.name = object.id
            parent.addChild(cable)
            for i in -3...3 {
                let bulb = ModelEntity(
                    mesh: .generateSphere(radius: 0.04),
                    materials: [SimpleMaterial(color: .systemYellow, isMetallic: false)]
                )
                bulb.position = SIMD3(Float(i) * 0.22, -0.05, 0)
                bulb.name = object.id
                parent.addChild(bulb)
            }
        case .unknown:
            let box = ModelEntity(
                mesh: .generateBox(width: w, height: h, depth: d),
                materials: [mat]
            )
            box.name = object.id
            parent.addChild(box)
        }

        if selected {
            addSelectionRing(to: parent, object: object)
        }
        // Tap targets for Live AR selection.
        for child in parent.children {
            if let model = child as? ModelEntity {
                model.generateCollisionShapes(recursive: true)
            }
        }
        return parent
    }

    // MARK: - Parts

    private static func addSofa(to parent: Entity, w: Float, h: Float, d: Float, mat: SimpleMaterial, name: String) {
        let seat = ModelEntity(
            mesh: .generateBox(width: w, height: h * 0.4, depth: d * 0.92),
            materials: [mat]
        )
        seat.position.y = -h * 0.12
        seat.name = name
        let back = ModelEntity(
            mesh: .generateBox(width: w, height: h * 0.55, depth: d * 0.2),
            materials: [mat]
        )
        back.position = SIMD3(0, h * 0.08, -d * 0.36)
        back.name = name
        let armL = ModelEntity(
            mesh: .generateBox(width: w * 0.1, height: h * 0.35, depth: d * 0.9),
            materials: [mat]
        )
        armL.position = SIMD3(-w * 0.45, 0, 0)
        armL.name = name
        let armR = ModelEntity(
            mesh: .generateBox(width: w * 0.1, height: h * 0.35, depth: d * 0.9),
            materials: [mat]
        )
        armR.position = SIMD3(w * 0.45, 0, 0)
        armR.name = name
        parent.addChild(seat)
        parent.addChild(back)
        parent.addChild(armL)
        parent.addChild(armR)
    }

    private static func addTable(to parent: Entity, w: Float, h: Float, d: Float, mat: SimpleMaterial, name: String) {
        let top = ModelEntity(
            mesh: .generateBox(width: w, height: max(h * 0.08, 0.04), depth: d),
            materials: [mat]
        )
        top.position.y = h * 0.42
        top.name = name
        parent.addChild(top)
        let legSize: Float = 0.05
        let insetX = w * 0.4
        let insetZ = d * 0.4
        for (sx, sz) in [(-1, -1), (-1, 1), (1, -1), (1, 1)] as [(Float, Float)] {
            let leg = ModelEntity(
                mesh: .generateBox(width: legSize, height: h * 0.85, depth: legSize),
                materials: [mat]
            )
            leg.position = SIMD3(sx * insetX, 0, sz * insetZ)
            leg.name = name
            parent.addChild(leg)
        }
    }

    private static func addChair(
        to parent: Entity,
        w: Float,
        h: Float,
        d: Float,
        mat: SimpleMaterial,
        name: String,
        stool: Bool
    ) {
        let seat = ModelEntity(
            mesh: .generateBox(width: w, height: max(h * 0.1, 0.05), depth: d),
            materials: [mat]
        )
        seat.position.y = stool ? h * 0.35 : -h * 0.1
        seat.name = name
        parent.addChild(seat)
        if !stool {
            let back = ModelEntity(
                mesh: .generateBox(width: w, height: h * 0.5, depth: d * 0.12),
                materials: [mat]
            )
            back.position = SIMD3(0, h * 0.2, -d * 0.4)
            back.name = name
            parent.addChild(back)
        }
        let legH = stool ? h * 0.85 : h * 0.55
        let legSize: Float = 0.04
        for (sx, sz) in [(-1, -1), (-1, 1), (1, -1), (1, 1)] as [(Float, Float)] {
            let leg = ModelEntity(
                mesh: .generateBox(width: legSize, height: legH, depth: legSize),
                materials: [mat]
            )
            leg.position = SIMD3(sx * w * 0.35, stool ? 0 : -h * 0.25, sz * d * 0.35)
            leg.name = name
            parent.addChild(leg)
        }
    }

    private static func addLamp(to parent: Entity, w: Float, h: Float, d: Float, mat: SimpleMaterial, name: String) {
        let pole = ModelEntity(
            mesh: .generateBox(width: 0.06, height: h * 0.85, depth: 0.06),
            materials: [mat]
        )
        pole.name = name
        let shadeR = max(w, d) * 0.35
        let shade = ModelEntity(
            mesh: .generateBox(width: shadeR * 2, height: h * 0.18, depth: shadeR * 2),
            materials: [SimpleMaterial(color: .systemYellow, isMetallic: false)]
        )
        shade.position.y = h * 0.4
        shade.name = name
        let base = ModelEntity(
            mesh: .generateBox(width: w * 0.55, height: 0.04, depth: d * 0.55),
            materials: [mat]
        )
        base.position.y = -h * 0.45
        base.name = name
        parent.addChild(base)
        parent.addChild(pole)
        parent.addChild(shade)
    }

    private static func addPlant(to parent: Entity, w: Float, h: Float, d: Float, name: String) {
        let pot = ModelEntity(
            mesh: .generateBox(width: w * 0.45, height: h * 0.18, depth: d * 0.45),
            materials: [SimpleMaterial(color: .systemBrown, isMetallic: false)]
        )
        pot.position.y = -h * 0.4
        pot.name = name
        let foliage = ModelEntity(
            mesh: .generateSphere(radius: min(w, d) * 0.4),
            materials: [SimpleMaterial(color: .systemGreen, isMetallic: false)]
        )
        foliage.position.y = h * 0.15
        foliage.scale = SIMD3(1, 1.3, 1)
        foliage.name = name
        parent.addChild(pot)
        parent.addChild(foliage)
    }

    private static func addSelectionRing(to parent: Entity, object: SceneObjectDTO) {
        let w = Float(object.dimensions?.width ?? 0.5)
        let h = Float(object.dimensions?.height ?? 0.5)
        let d = Float(object.dimensions?.depth ?? 0.5)
        let ring = ModelEntity(
            mesh: .generateBox(width: w * 1.12, height: 0.02, depth: d * 1.12),
            materials: [SimpleMaterial(color: .systemYellow.withAlphaComponent(0.7), isMetallic: false)]
        )
        ring.position.y = -h * 0.48
        ring.name = object.id
        parent.addChild(ring)
    }

    private static func tryLoadUSDZ(url: String, name: String) -> Entity? {
        let resolved: URL?
        if url.hasPrefix("http://") || url.hasPrefix("https://") {
            resolved = URL(string: url)
        } else {
            let base = (url as NSString).lastPathComponent
            let stem = (base as NSString).deletingPathExtension
            resolved = Bundle.main.url(forResource: stem, withExtension: "usdz", subdirectory: "Models")
                ?? Bundle.main.url(forResource: stem, withExtension: "usdz")
        }
        guard let fileURL = resolved else { return nil }
        guard let model = try? Entity.load(contentsOf: fileURL) else { return nil }
        model.name = name
        return model
    }

    // MARK: - Classification

    enum Kind {
        case wall, sofa, table, desk, chair, stool, lamp, plant, rug, beanbag, screen, backdrop, lights, unknown
    }

    static func furnitureKind(for object: SceneObjectDTO) -> Kind {
        let t = object.type.lowercased()
        let asset = (object.assetId ?? "").lowercased()
        if t == "wall" { return .wall }
        if t.contains("sofa") || t.contains("couch") || asset.contains("sofa") { return .sofa }
        if t.contains("bean") || asset.contains("bean") { return .beanbag }
        if t.contains("stool") || asset.contains("stool") { return .stool }
        if t.contains("chair") || asset.contains("chair") { return .chair }
        if t.contains("desk") || asset.contains("desk") { return .desk }
        if t.contains("table") || asset.contains("table") { return .table }
        if t.contains("plant") || asset.contains("plant") { return .plant }
        if t.contains("rug") || asset.contains("rug") { return .rug }
        if t.contains("string") || t.contains("party_light") || asset.contains("lights") { return .lights }
        if t.contains("pendant") || t.contains("lamp") || t.contains("light") || asset.contains("lamp") {
            return .lamp
        }
        if t.contains("screen") || t.contains("projector") || asset.contains("projector") { return .screen }
        if t.contains("backdrop") || asset.contains("backdrop") { return .backdrop }
        return .unknown
    }

    static func furnitureColor(for object: SceneObjectDTO, kind: Kind) -> UIColor {
        if object.source == "existing" {
            switch kind {
            case .sofa: return UIColor(red: 0.55, green: 0.42, blue: 0.32, alpha: 1)
            case .table, .desk: return UIColor(red: 0.45, green: 0.32, blue: 0.22, alpha: 1)
            case .chair, .stool: return UIColor(red: 0.5, green: 0.38, blue: 0.28, alpha: 1)
            default: return UIColor(white: 0.42, alpha: 1)
            }
        }
        switch kind {
        case .sofa: return .systemTeal
        case .table, .desk: return .systemBrown
        case .chair, .stool: return .systemOrange
        case .lamp, .lights: return .systemYellow
        case .plant: return .systemGreen
        case .rug: return UIColor(red: 0.3, green: 0.5, blue: 0.35, alpha: 1)
        case .beanbag: return .systemPurple
        case .screen, .backdrop: return .systemGray
        default: return .systemIndigo
        }
    }
}

private extension UIColor {
    func blended(with other: UIColor) -> UIColor? {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        guard getRed(&r1, green: &g1, blue: &b1, alpha: &a1),
              other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2) else { return nil }
        return UIColor(
            red: (r1 + r2) / 2,
            green: (g1 + g2) / 2,
            blue: (b1 + b2) / 2,
            alpha: max(a1, a2)
        )
    }
}
