import RealityKit
import UIKit
import simd

/// Product-accurate furniture for Live AR + map twin.
/// Prefers bundled / remote USDZ (same stem as web GLB); otherwise builds a
/// distinct RealityKit composite per catalog SKU at catalog dimensions (meters).
enum FurnitureMeshBuilder {
    static func makeEntity(for object: SceneObjectDTO, selected: Bool) -> Entity {
        let w = Float(object.dimensions?.widthMeters ?? 0.5)
        let h = Float(object.dimensions?.heightMeters ?? 0.5)
        let d = Float(object.dimensions?.depthMeters ?? 0.5)
        let meshKey = ProductModelCatalog.meshKey(for: object)
        let scaleSIMD = Coordinates.toSIMD(object.transform.scale ?? Vector3(1, 1, 1))

        // 1) Prefer real USDZ (bundle Models/ or remote .usdz) scaled 1:1 to dimensions.
        if let usdz = tryLoadProductUSDZ(for: object, width: w, height: h, depth: d) {
            usdz.position = Coordinates.toSIMD(object.transform.position)
            usdz.orientation = Coordinates.toSIMDQuat(object.transform.rotation)
            usdz.scale = scaleSIMD
            if selected { addSelectionRing(to: usdz, width: w, height: h, depth: d, name: object.id) }
            enableCollisions(on: usdz)
            return usdz
        }

        // 2) Product-specific composite at exact catalog meters.
        let parent = Entity()
        parent.name = object.id
        parent.position = Coordinates.toSIMD(object.transform.position)
        parent.orientation = Coordinates.toSIMDQuat(object.transform.rotation)
        parent.scale = scaleSIMD

        let baseColor = furnitureColor(for: object, key: meshKey)
        let color = selected
            ? (baseColor.blended(with: .systemYellow) ?? baseColor)
            : baseColor
        let mat = SimpleMaterial(color: color, isMetallic: meshKey == .wall)
        let name = object.id

        switch meshKey {
        case .wall:
            addWall(to: parent, w: w, h: h, d: d, name: name)
        case .loungeSofa:
            addLoungeSofa(to: parent, w: w, h: h, d: d, mat: mat, name: name)
        case .foldingLoungeChair:
            addFoldingLoungeChair(to: parent, w: w, h: h, d: d, mat: mat, name: name)
        case .diningChair:
            addDiningChair(to: parent, w: w, h: h, d: d, mat: mat, name: name)
        case .barStool:
            addBarStool(to: parent, w: w, h: h, d: d, mat: mat, name: name)
        case .beanbag:
            addBeanbag(to: parent, w: w, h: h, d: d, mat: mat, name: name)
        case .coffeeTable:
            addCoffeeTable(to: parent, w: w, h: h, d: d, mat: mat, name: name)
        case .studyDesk:
            addStudyDesk(to: parent, w: w, h: h, d: d, mat: mat, name: name)
        case .diningTable:
            addDiningTable(to: parent, w: w, h: h, d: d, mat: mat, name: name)
        case .arcFloorLamp:
            addArcFloorLamp(to: parent, w: w, h: h, d: d, mat: mat, name: name)
        case .taskDeskLamp:
            addTaskDeskLamp(to: parent, w: w, h: h, d: d, mat: mat, name: name)
        case .pendant:
            addPendant(to: parent, w: w, h: h, d: d, mat: mat, name: name)
        case .stringLights:
            addStringLights(to: parent, w: w, h: h, d: d, name: name)
        case .tallPlant:
            addTallPlant(to: parent, w: w, h: h, d: d, name: name)
        case .danceRug:
            addDanceRug(to: parent, w: w, h: h, d: d, name: name)
        case .photoBackdrop:
            addPhotoBackdrop(to: parent, w: w, h: h, d: d, mat: mat, name: name)
        case .projectorScreen:
            addProjectorScreen(to: parent, w: w, h: h, d: d, mat: mat, name: name)
        case .layoutMarker:
            addLayoutMarker(to: parent, w: w, h: h, d: d, name: name)
        case .glowOrb:
            addGlowOrb(to: parent, w: w, h: h, d: d, name: name)
        case .generic:
            addGenericBox(to: parent, w: w, h: h, d: d, mat: mat, name: name)
        }

        if selected {
            addSelectionRing(to: parent, width: w, height: h, depth: d, name: name)
        }
        enableCollisions(on: parent)
        return parent
    }

    // MARK: - USDZ load + 1:1 scale

    /// Load USDZ from bundle `Models/{stem}.usdz`, bundle root, or remote URL ending in `.usdz`.
    /// Fits visual bounds to catalog width/height/depth meters (web GLB parity).
    private static func tryLoadProductUSDZ(
        for object: SceneObjectDTO,
        width: Float,
        height: Float,
        depth: Float
    ) -> Entity? {
        let stem = ProductModelCatalog.assetStem(for: object)
        var candidates: [URL] = []

        if let stem {
            if let u = Bundle.main.url(forResource: stem, withExtension: "usdz", subdirectory: "Models") {
                candidates.append(u)
            }
            if let u = Bundle.main.url(forResource: stem, withExtension: "usdz") {
                candidates.append(u)
            }
        }

        if let raw = object.modelUrl {
            let lower = raw.lowercased()
            if lower.hasSuffix(".usdz") {
                if raw.hasPrefix("http://") || raw.hasPrefix("https://"), let u = URL(string: raw) {
                    candidates.append(u)
                } else if let stem2 = ProductModelCatalog.assetStem(fromModelUrl: raw) {
                    if let u = Bundle.main.url(forResource: stem2, withExtension: "usdz", subdirectory: "Models") {
                        candidates.append(u)
                    }
                }
            } else if lower.hasSuffix(".glb"), let stem2 = ProductModelCatalog.assetStem(fromModelUrl: raw) {
                // Catalog points at web GLB — try matching USDZ in the iOS bundle.
                if let u = Bundle.main.url(forResource: stem2, withExtension: "usdz", subdirectory: "Models") {
                    candidates.append(u)
                }
            }
        }

        for fileURL in candidates {
            guard let model = try? Entity.load(contentsOf: fileURL) else { continue }
            let wrapper = Entity()
            wrapper.name = object.id
            wrapper.addChild(model)
            fitChildToDimensions(model, in: wrapper, width: width, height: height, depth: depth)
            return wrapper
        }
        return nil
    }

    /// Scale + center a loaded model so its AABB matches catalog meters.
    private static func fitChildToDimensions(
        _ model: Entity,
        in parent: Entity,
        width: Float,
        height: Float,
        depth: Float
    ) {
        model.scale = .one
        model.position = .zero
        let bounds = model.visualBounds(relativeTo: parent)
        let size = bounds.extents
        guard size.x > 1e-4, size.y > 1e-4, size.z > 1e-4 else { return }
        model.scale = SIMD3(width / size.x, height / size.y, depth / size.z)
        let scaled = model.visualBounds(relativeTo: parent)
        model.position = -scaled.center
    }

    private static func enableCollisions(on root: Entity) {
        root.visitModels { model in
            model.generateCollisionShapes(recursive: false)
        }
    }

    // MARK: - Product composites (distinct per SKU, built in meters)

    private static func addWall(to parent: Entity, w: Float, h: Float, d: Float, name: String) {
        let wall = ModelEntity(
            mesh: .generateBox(width: w, height: h, depth: max(d, 0.06)),
            materials: [SimpleMaterial(color: UIColor(white: 0.55, alpha: 0.85), isMetallic: false)]
        )
        wall.name = name
        parent.addChild(wall)
    }

    /// Box stand-in for a cylinder (iOS 17–safe; `generateCylinder` needs iOS 18+).
    private static func cylinderBox(height: Float, radius: Float) -> MeshResource {
        .generateBox(width: radius * 2, height: height, depth: radius * 2)
    }

    /// product_sofa_01 — deep lounge sofa with seat cushions + rolled arms.
    private static func addLoungeSofa(
        to parent: Entity, w: Float, h: Float, d: Float, mat: SimpleMaterial, name: String
    ) {
        let frame = ModelEntity(
            mesh: .generateBox(width: w * 0.98, height: h * 0.28, depth: d * 0.88),
            materials: [mat]
        )
        frame.position.y = -h * 0.28
        frame.name = name
        parent.addChild(frame)

        let seat = ModelEntity(
            mesh: .generateBox(width: w * 0.72, height: h * 0.16, depth: d * 0.7),
            materials: [SimpleMaterial(color: UIColor(red: 0.25, green: 0.55, blue: 0.58, alpha: 1), isMetallic: false)]
        )
        seat.position = SIMD3(0, -h * 0.08, d * 0.02)
        seat.name = name
        parent.addChild(seat)

        // Three seat cushions
        let cushionW = w * 0.22
        for i in -1...1 {
            let c = ModelEntity(
                mesh: .generateBox(width: cushionW, height: h * 0.12, depth: d * 0.55),
                materials: [mat]
            )
            c.position = SIMD3(Float(i) * (cushionW + 0.04), h * 0.02, d * 0.05)
            c.name = name
            parent.addChild(c)
        }

        let back = ModelEntity(
            mesh: .generateBox(width: w * 0.96, height: h * 0.52, depth: d * 0.18),
            materials: [mat]
        )
        back.position = SIMD3(0, h * 0.12, -d * 0.38)
        back.name = name
        parent.addChild(back)

        for side in [-1.0, 1.0] as [Float] {
            let arm = ModelEntity(
                mesh: .generateBox(width: w * 0.12, height: h * 0.38, depth: d * 0.85),
                materials: [mat]
            )
            arm.position = SIMD3(side * w * 0.44, -h * 0.02, 0)
            arm.name = name
            parent.addChild(arm)
        }

        // Short legs
        let legMat = SimpleMaterial(color: UIColor(white: 0.2, alpha: 1), isMetallic: false)
        for (sx, sz) in [(-1, -1), (-1, 1), (1, -1), (1, 1)] as [(Float, Float)] {
            let leg = ModelEntity(
                mesh: .generateBox(width: 0.06, height: h * 0.12, depth: 0.06),
                materials: [legMat]
            )
            leg.position = SIMD3(sx * w * 0.4, -h * 0.44, sz * d * 0.35)
            leg.name = name
            parent.addChild(leg)
        }
    }

    /// chair_fold_01 — slim folding lounge with X-frame.
    private static func addFoldingLoungeChair(
        to parent: Entity, w: Float, h: Float, d: Float, mat: SimpleMaterial, name: String
    ) {
        let seat = ModelEntity(
            mesh: .generateBox(width: w * 0.9, height: max(h * 0.08, 0.04), depth: d * 0.85),
            materials: [mat]
        )
        seat.position.y = -h * 0.05
        seat.name = name
        parent.addChild(seat)

        let back = ModelEntity(
            mesh: .generateBox(width: w * 0.88, height: h * 0.48, depth: d * 0.08),
            materials: [mat]
        )
        back.position = SIMD3(0, h * 0.22, -d * 0.38)
        back.name = name
        parent.addChild(back)

        let frame = SimpleMaterial(color: UIColor(white: 0.35, alpha: 1), isMetallic: true)
        for angle in [-0.55, 0.55] as [Float] {
            let bar = ModelEntity(
                mesh: .generateBox(width: 0.035, height: h * 0.7, depth: 0.035),
                materials: [frame]
            )
            bar.position = SIMD3(angle * w * 0.25, -h * 0.15, 0)
            bar.orientation = simd_quatf(angle: angle * 0.35, axis: SIMD3(0, 0, 1))
            bar.name = name
            parent.addChild(bar)
        }
    }

    /// chair_dining_02 — upright dining chair with back slats.
    private static func addDiningChair(
        to parent: Entity, w: Float, h: Float, d: Float, mat: SimpleMaterial, name: String
    ) {
        let seat = ModelEntity(
            mesh: .generateBox(width: w, height: max(h * 0.08, 0.04), depth: d * 0.9),
            materials: [mat]
        )
        seat.position.y = -h * 0.08
        seat.name = name
        parent.addChild(seat)

        let back = ModelEntity(
            mesh: .generateBox(width: w * 0.95, height: h * 0.55, depth: d * 0.08),
            materials: [mat]
        )
        back.position = SIMD3(0, h * 0.22, -d * 0.4)
        back.name = name
        parent.addChild(back)

        // Vertical slats
        for i in -1...1 {
            let slat = ModelEntity(
                mesh: .generateBox(width: w * 0.08, height: h * 0.4, depth: d * 0.05),
                materials: [mat]
            )
            slat.position = SIMD3(Float(i) * w * 0.28, h * 0.18, -d * 0.38)
            slat.name = name
            parent.addChild(slat)
        }

        let legH = h * 0.52
        for (sx, sz) in [(-1, -1), (-1, 1), (1, -1), (1, 1)] as [(Float, Float)] {
            let leg = ModelEntity(
                mesh: .generateBox(width: 0.038, height: legH, depth: 0.038),
                materials: [mat]
            )
            leg.position = SIMD3(sx * w * 0.38, -h * 0.28, sz * d * 0.35)
            leg.name = name
            parent.addChild(leg)
        }
    }

    /// stool_bar_01 — tall round seat on pedestal.
    private static func addBarStool(
        to parent: Entity, w: Float, h: Float, d: Float, mat: SimpleMaterial, name: String
    ) {
        let seatR = min(w, d) * 0.45
        let seat = ModelEntity(
            mesh: Self.cylinderBox(height: max(h * 0.06, 0.04), radius: seatR),
            materials: [mat]
        )
        seat.position.y = h * 0.38
        seat.name = name
        parent.addChild(seat)

        let pole = ModelEntity(
            mesh: Self.cylinderBox(height: h * 0.7, radius: 0.035),
            materials: [SimpleMaterial(color: UIColor(white: 0.45, alpha: 1), isMetallic: true)]
        )
        pole.position.y = -h * 0.05
        pole.name = name
        parent.addChild(pole)

        let base = ModelEntity(
            mesh: Self.cylinderBox(height: 0.04, radius: seatR * 0.85),
            materials: [SimpleMaterial(color: UIColor(white: 0.3, alpha: 1), isMetallic: true)]
        )
        base.position.y = -h * 0.45
        base.name = name
        parent.addChild(base)

        let ring = ModelEntity(
            mesh: Self.cylinderBox(height: 0.02, radius: seatR * 0.55),
            materials: [SimpleMaterial(color: UIColor(white: 0.5, alpha: 1), isMetallic: true)]
        )
        ring.position.y = -h * 0.15
        ring.name = name
        parent.addChild(ring)
    }

    /// beanbag_01 — soft squashed sphere.
    private static func addBeanbag(
        to parent: Entity, w: Float, h: Float, d: Float, mat: SimpleMaterial, name: String
    ) {
        let bag = ModelEntity(
            mesh: .generateSphere(radius: min(w, d) * 0.48),
            materials: [mat]
        )
        bag.scale = SIMD3(1, (h / max(min(w, d), 0.01)) * 0.85, 1)
        bag.name = name
        parent.addChild(bag)
        let top = ModelEntity(
            mesh: .generateSphere(radius: min(w, d) * 0.22),
            materials: [mat]
        )
        top.position.y = h * 0.28
        top.scale = SIMD3(1.2, 0.55, 1.2)
        top.name = name
        parent.addChild(top)
    }

    /// product_table_05 — low coffee table with thick top.
    private static func addCoffeeTable(
        to parent: Entity, w: Float, h: Float, d: Float, mat: SimpleMaterial, name: String
    ) {
        let top = ModelEntity(
            mesh: .generateBox(width: w, height: max(h * 0.1, 0.04), depth: d),
            materials: [mat]
        )
        top.position.y = h * 0.4
        top.name = name
        parent.addChild(top)

        let apron = ModelEntity(
            mesh: .generateBox(width: w * 0.92, height: h * 0.08, depth: d * 0.92),
            materials: [mat]
        )
        apron.position.y = h * 0.28
        apron.name = name
        parent.addChild(apron)

        let legSize: Float = 0.06
        for (sx, sz) in [(-1, -1), (-1, 1), (1, -1), (1, 1)] as [(Float, Float)] {
            let leg = ModelEntity(
                mesh: .generateBox(width: legSize, height: h * 0.72, depth: legSize),
                materials: [mat]
            )
            leg.position = SIMD3(sx * w * 0.4, -h * 0.05, sz * d * 0.38)
            leg.name = name
            parent.addChild(leg)
        }
    }

    /// desk_study_01 — work desk with shallow drawer rail.
    private static func addStudyDesk(
        to parent: Entity, w: Float, h: Float, d: Float, mat: SimpleMaterial, name: String
    ) {
        let top = ModelEntity(
            mesh: .generateBox(width: w, height: max(h * 0.06, 0.035), depth: d),
            materials: [mat]
        )
        top.position.y = h * 0.42
        top.name = name
        parent.addChild(top)

        let drawer = ModelEntity(
            mesh: .generateBox(width: w * 0.35, height: h * 0.12, depth: d * 0.7),
            materials: [SimpleMaterial(color: UIColor(red: 0.4, green: 0.28, blue: 0.18, alpha: 1), isMetallic: false)]
        )
        drawer.position = SIMD3(-w * 0.25, h * 0.28, 0)
        drawer.name = name
        parent.addChild(drawer)

        for (sx, sz) in [(-1, -1), (-1, 1), (1, -1), (1, 1)] as [(Float, Float)] {
            let leg = ModelEntity(
                mesh: .generateBox(width: 0.05, height: h * 0.82, depth: 0.05),
                materials: [mat]
            )
            leg.position = SIMD3(sx * w * 0.42, -h * 0.05, sz * d * 0.38)
            leg.name = name
            parent.addChild(leg)
        }
    }

    /// table_dining_01 — long rectangular dining table.
    private static func addDiningTable(
        to parent: Entity, w: Float, h: Float, d: Float, mat: SimpleMaterial, name: String
    ) {
        let top = ModelEntity(
            mesh: .generateBox(width: w, height: max(h * 0.07, 0.04), depth: d),
            materials: [mat]
        )
        top.position.y = h * 0.42
        top.name = name
        parent.addChild(top)

        // Trestle stretchers
        let stretcher = ModelEntity(
            mesh: .generateBox(width: w * 0.7, height: 0.04, depth: 0.05),
            materials: [mat]
        )
        stretcher.position.y = -h * 0.15
        stretcher.name = name
        parent.addChild(stretcher)

        for sx in [-1.0, 1.0] as [Float] {
            let leg = ModelEntity(
                mesh: .generateBox(width: 0.08, height: h * 0.8, depth: d * 0.55),
                materials: [mat]
            )
            leg.position = SIMD3(sx * w * 0.38, -h * 0.05, 0)
            leg.name = name
            parent.addChild(leg)
        }
    }

    /// product_39 — tall arc / round floor lamp.
    private static func addArcFloorLamp(
        to parent: Entity, w: Float, h: Float, d: Float, mat: SimpleMaterial, name: String
    ) {
        let baseR = min(w, d) * 0.4
        let base = ModelEntity(
            mesh: Self.cylinderBox(height: 0.04, radius: baseR),
            materials: [mat]
        )
        base.position.y = -h * 0.48
        base.name = name
        parent.addChild(base)

        let pole = ModelEntity(
            mesh: Self.cylinderBox(height: h * 0.78, radius: 0.022),
            materials: [mat]
        )
        pole.position = SIMD3(-w * 0.08, 0, 0)
        pole.name = name
        parent.addChild(pole)

        // Arc arm
        let arm = ModelEntity(
            mesh: .generateBox(width: w * 0.55, height: 0.03, depth: 0.03),
            materials: [mat]
        )
        arm.position = SIMD3(w * 0.12, h * 0.35, 0)
        arm.orientation = simd_quatf(angle: -0.35, axis: SIMD3(0, 0, 1))
        arm.name = name
        parent.addChild(arm)

        let shade = ModelEntity(
            mesh: .generateSphere(radius: min(w, d) * 0.28),
            materials: [SimpleMaterial(color: .systemYellow.withAlphaComponent(0.9), isMetallic: false)]
        )
        shade.position = SIMD3(w * 0.28, h * 0.32, 0)
        shade.scale = SIMD3(1, 0.75, 1)
        shade.name = name
        parent.addChild(shade)
    }

    /// lamp_desk_01 — compact square task lamp.
    private static func addTaskDeskLamp(
        to parent: Entity, w: Float, h: Float, d: Float, mat: SimpleMaterial, name: String
    ) {
        let base = ModelEntity(
            mesh: .generateBox(width: w * 0.9, height: 0.03, depth: d * 0.9),
            materials: [mat]
        )
        base.position.y = -h * 0.45
        base.name = name
        parent.addChild(base)

        let arm1 = ModelEntity(
            mesh: .generateBox(width: 0.03, height: h * 0.45, depth: 0.03),
            materials: [mat]
        )
        arm1.position = SIMD3(0, -h * 0.1, 0)
        arm1.name = name
        parent.addChild(arm1)

        let arm2 = ModelEntity(
            mesh: .generateBox(width: w * 0.55, height: 0.03, depth: 0.03),
            materials: [mat]
        )
        arm2.position = SIMD3(w * 0.2, h * 0.15, 0)
        arm2.name = name
        parent.addChild(arm2)

        let head = ModelEntity(
            mesh: .generateBox(width: w * 0.55, height: h * 0.18, depth: d * 0.45),
            materials: [SimpleMaterial(color: .systemYellow, isMetallic: false)]
        )
        head.position = SIMD3(w * 0.22, h * 0.28, 0)
        head.name = name
        parent.addChild(head)
    }

    /// pendant_dinner_01 — hanging dome shade.
    private static func addPendant(
        to parent: Entity, w: Float, h: Float, d: Float, mat: SimpleMaterial, name: String
    ) {
        let cord = ModelEntity(
            mesh: Self.cylinderBox(height: h * 0.35, radius: 0.012),
            materials: [SimpleMaterial(color: .darkGray, isMetallic: false)]
        )
        cord.position.y = h * 0.3
        cord.name = name
        parent.addChild(cord)

        let shade = ModelEntity(
            mesh: .generateSphere(radius: min(w, d) * 0.45),
            materials: [mat]
        )
        shade.scale = SIMD3(1, 0.55, 1)
        shade.position.y = -h * 0.05
        shade.name = name
        parent.addChild(shade)

        let bulb = ModelEntity(
            mesh: .generateSphere(radius: min(w, d) * 0.12),
            materials: [SimpleMaterial(color: .systemYellow, isMetallic: false)]
        )
        bulb.position.y = -h * 0.15
        bulb.name = name
        parent.addChild(bulb)
    }

    /// party_lights_03 — string of bulbs.
    private static func addStringLights(to parent: Entity, w: Float, h: Float, d: Float, name: String) {
        let span = max(w, 1.2)
        let cable = ModelEntity(
            mesh: .generateBox(width: span, height: 0.015, depth: 0.015),
            materials: [SimpleMaterial(color: .darkGray, isMetallic: false)]
        )
        cable.name = name
        parent.addChild(cable)
        let count = 7
        for i in 0..<count {
            let t = Float(i) / Float(count - 1)
            let x = -span * 0.5 + t * span
            let bulb = ModelEntity(
                mesh: .generateSphere(radius: 0.04),
                materials: [SimpleMaterial(color: .systemYellow, isMetallic: false)]
            )
            bulb.position = SIMD3(x, -0.06 - abs(t - 0.5) * 0.04, 0)
            bulb.name = name
            parent.addChild(bulb)
        }
    }

    /// plant_tall_02 — pot + layered foliage.
    private static func addTallPlant(to parent: Entity, w: Float, h: Float, d: Float, name: String) {
        let pot = ModelEntity(
            mesh: Self.cylinderBox(height: h * 0.22, radius: min(w, d) * 0.28),
            materials: [SimpleMaterial(color: .systemBrown, isMetallic: false)]
        )
        pot.position.y = -h * 0.38
        pot.name = name
        parent.addChild(pot)

        let soil = ModelEntity(
            mesh: Self.cylinderBox(height: 0.02, radius: min(w, d) * 0.26),
            materials: [SimpleMaterial(color: UIColor(red: 0.25, green: 0.18, blue: 0.12, alpha: 1), isMetallic: false)]
        )
        soil.position.y = -h * 0.26
        soil.name = name
        parent.addChild(soil)

        let green = SimpleMaterial(color: .systemGreen, isMetallic: false)
        for (dy, scale) in [(0.05, 0.9), (0.28, 1.1), (0.48, 0.75)] as [(Float, Float)] {
            let leaf = ModelEntity(
                mesh: .generateSphere(radius: min(w, d) * 0.32 * scale),
                materials: [green]
            )
            leaf.position.y = h * dy
            leaf.scale = SIMD3(1, 1.25, 1)
            leaf.name = name
            parent.addChild(leaf)
        }
    }

    /// rug_party_01 — flat patterned rug.
    private static func addDanceRug(to parent: Entity, w: Float, h: Float, d: Float, name: String) {
        let rug = ModelEntity(
            mesh: .generateBox(width: w, height: max(h, 0.02), depth: d),
            materials: [SimpleMaterial(color: UIColor(red: 0.28, green: 0.48, blue: 0.38, alpha: 0.95), isMetallic: false)]
        )
        rug.name = name
        parent.addChild(rug)
        let border = ModelEntity(
            mesh: .generateBox(width: w * 0.92, height: max(h, 0.02) + 0.002, depth: d * 0.92),
            materials: [SimpleMaterial(color: UIColor(red: 0.85, green: 0.75, blue: 0.35, alpha: 0.7), isMetallic: false)]
        )
        border.position.y = 0.002
        border.name = name
        parent.addChild(border)
    }

    /// backdrop_12 — tall photo panel with stand feet.
    private static func addPhotoBackdrop(
        to parent: Entity, w: Float, h: Float, d: Float, mat: SimpleMaterial, name: String
    ) {
        let panel = ModelEntity(
            mesh: .generateBox(width: w, height: h, depth: max(d, 0.04)),
            materials: [mat]
        )
        panel.name = name
        parent.addChild(panel)
        let bar = ModelEntity(
            mesh: .generateBox(width: w * 1.02, height: 0.05, depth: 0.05),
            materials: [SimpleMaterial(color: .darkGray, isMetallic: true)]
        )
        bar.position.y = h * 0.48
        bar.name = name
        parent.addChild(bar)
        for sx in [-1.0, 1.0] as [Float] {
            let foot = ModelEntity(
                mesh: .generateBox(width: 0.08, height: 0.04, depth: max(d, 0.25)),
                materials: [SimpleMaterial(color: .darkGray, isMetallic: true)]
            )
            foot.position = SIMD3(sx * w * 0.4, -h * 0.48, 0)
            foot.name = name
            parent.addChild(foot)
        }
    }

    /// projector_screen_01 — wide screen with top bar.
    private static func addProjectorScreen(
        to parent: Entity, w: Float, h: Float, d: Float, mat: SimpleMaterial, name: String
    ) {
        let screen = ModelEntity(
            mesh: .generateBox(width: w, height: h, depth: max(d, 0.04)),
            materials: [SimpleMaterial(color: UIColor(white: 0.92, alpha: 1), isMetallic: false)]
        )
        screen.name = name
        parent.addChild(screen)
        let frame = ModelEntity(
            mesh: .generateBox(width: w * 1.02, height: 0.06, depth: 0.06),
            materials: [SimpleMaterial(color: .darkGray, isMetallic: true)]
        )
        frame.position.y = h * 0.5
        frame.name = name
        parent.addChild(frame)
        let stand = ModelEntity(
            mesh: .generateBox(width: 0.06, height: h * 0.15, depth: 0.06),
            materials: [SimpleMaterial(color: .darkGray, isMetallic: true)]
        )
        stand.position.y = -h * 0.55
        stand.name = name
        parent.addChild(stand)
    }

    private static func addLayoutMarker(to parent: Entity, w: Float, h: Float, d: Float, name: String) {
        let disc = ModelEntity(
            mesh: Self.cylinderBox(height: max(h, 0.04), radius: min(w, d) * 0.45),
            materials: [SimpleMaterial(color: .systemCyan.withAlphaComponent(0.7), isMetallic: false)]
        )
        disc.name = name
        parent.addChild(disc)
    }

    private static func addGlowOrb(to parent: Entity, w: Float, h: Float, d: Float, name: String) {
        let orb = ModelEntity(
            mesh: .generateSphere(radius: min(w, h, d) * 0.48),
            materials: [SimpleMaterial(color: .systemPurple.withAlphaComponent(0.75), isMetallic: false)]
        )
        orb.name = name
        parent.addChild(orb)
    }

    private static func addGenericBox(
        to parent: Entity, w: Float, h: Float, d: Float, mat: SimpleMaterial, name: String
    ) {
        let box = ModelEntity(
            mesh: .generateBox(width: w, height: h, depth: d),
            materials: [mat]
        )
        box.name = name
        parent.addChild(box)
    }

    private static func addSelectionRing(
        to parent: Entity, width w: Float, height h: Float, depth d: Float, name: String
    ) {
        let ring = ModelEntity(
            mesh: .generateBox(width: w * 1.12, height: 0.02, depth: d * 1.12),
            materials: [SimpleMaterial(color: .systemYellow.withAlphaComponent(0.7), isMetallic: false)]
        )
        ring.position.y = -h * 0.48
        ring.name = name
        parent.addChild(ring)
    }

    // MARK: - Color

    static func furnitureColor(for object: SceneObjectDTO, key: ProductModelCatalog.MeshKey) -> UIColor {
        if object.source == "existing" {
            switch key {
            case .loungeSofa: return UIColor(red: 0.55, green: 0.42, blue: 0.32, alpha: 1)
            case .coffeeTable, .studyDesk, .diningTable:
                return UIColor(red: 0.45, green: 0.32, blue: 0.22, alpha: 1)
            case .foldingLoungeChair, .diningChair, .barStool:
                return UIColor(red: 0.5, green: 0.38, blue: 0.28, alpha: 1)
            default: return UIColor(white: 0.42, alpha: 1)
            }
        }
        switch key {
        case .loungeSofa: return UIColor(red: 0.2, green: 0.55, blue: 0.58, alpha: 1)
        case .foldingLoungeChair: return UIColor(red: 0.85, green: 0.55, blue: 0.25, alpha: 1)
        case .diningChair: return UIColor(red: 0.55, green: 0.38, blue: 0.22, alpha: 1)
        case .barStool: return UIColor(red: 0.35, green: 0.35, blue: 0.4, alpha: 1)
        case .beanbag: return .systemPurple
        case .coffeeTable: return UIColor(red: 0.55, green: 0.4, blue: 0.25, alpha: 1)
        case .studyDesk: return UIColor(red: 0.48, green: 0.35, blue: 0.22, alpha: 1)
        case .diningTable: return UIColor(red: 0.42, green: 0.28, blue: 0.16, alpha: 1)
        case .arcFloorLamp, .taskDeskLamp, .pendant, .stringLights: return .systemYellow
        case .tallPlant: return .systemGreen
        case .danceRug: return UIColor(red: 0.3, green: 0.5, blue: 0.35, alpha: 1)
        case .photoBackdrop, .projectorScreen: return .systemGray
        case .layoutMarker: return .systemCyan
        case .glowOrb: return .systemPurple
        case .wall: return UIColor(white: 0.55, alpha: 1)
        case .generic: return .systemIndigo
        }
    }
}

// MARK: - Helpers

private extension Entity {
    func visitModels(_ body: (ModelEntity) -> Void) {
        if let model = self as? ModelEntity {
            body(model)
        }
        for child in children {
            child.visitModels(body)
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
