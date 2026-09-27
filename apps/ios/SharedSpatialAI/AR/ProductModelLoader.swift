import Foundation
import RealityKit
import UIKit
import simd

/// Resolves catalog `modelUrl` / product stems to USDZ for RealityKit.
///
/// Why models previously failed:
/// 1. Sync `Entity.load(contentsOf:)` cannot load remote HTTP URLs.
/// 2. Catalog paths are often relative (`/models/sofa.glb`) — not absolute, and GLB is not RealityKit-native.
/// 3. Bundle usually has no matching `.usdz` under `Models/`.
///
/// This loader: resolves absolute API URLs → prefers `.usdz` (bundle, `/media/meshes`, or Meshy cache)
/// → downloads to disk cache → `Entity.load` → fits AABB to catalog meters.
enum ProductModelLoader {
    private static let cacheDir: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("ssa_usdz", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func shouldAttemptUSDZ(for object: SceneObjectDTO) -> Bool {
        !candidateUSDZURLs(for: object).isEmpty
    }

    /// Async load + scale wrapper named `object.id`. Returns nil if nothing loads.
    static func loadUSDZEntity(for object: SceneObjectDTO, selected: Bool) async -> Entity? {
        let w = Float(object.dimensions?.widthMeters ?? 0.5)
        let h = Float(object.dimensions?.heightMeters ?? 0.5)
        let d = Float(object.dimensions?.depthMeters ?? 0.5)
        let scaleSIMD = Coordinates.toSIMD(object.transform.scale ?? Vector3(1, 1, 1))

        for url in candidateUSDZURLs(for: object) {
            guard let fileURL = await materializeFileURL(url) else { continue }
            do {
                let model = try Entity.load(contentsOf: fileURL)
                let wrapper = Entity()
                wrapper.name = object.id
                wrapper.addChild(model)
                fitChildToDimensions(model, in: wrapper, width: w, height: h, depth: d)
                // Center pivot + floor seating (Y = height/2 when object sits on floor).
                wrapper.position = Coordinates.toSIMD(Coordinates.renderPosition(for: object))
                wrapper.orientation = Coordinates.toSIMDQuat(object.transform.rotation)
                wrapper.scale = scaleSIMD
                if selected {
                    FurnitureMeshBuilder.addSelectionRingPublic(
                        to: wrapper, width: w, height: h, depth: d, name: object.id
                    )
                }
                enableCollisions(on: wrapper)
                return wrapper
            } catch {
                continue
            }
        }
        return nil
    }

    // MARK: - Candidates

    static func candidateUSDZURLs(for object: SceneObjectDTO) -> [URL] {
        var out: [URL] = []
        var seen = Set<String>()

        func append(_ url: URL?) {
            guard let url else { return }
            let key = url.absoluteString
            guard !seen.contains(key) else { return }
            seen.insert(key)
            out.append(url)
        }

        let stem = ProductModelCatalog.assetStem(for: object)
        if let stem {
            append(Bundle.main.url(forResource: stem, withExtension: "usdz", subdirectory: "Models"))
            append(Bundle.main.url(forResource: stem, withExtension: "usdz"))
        }

        // Generated lookalike from API: /media/meshes/{productId}.usdz
        if let pid = object.productId {
            append(APIConfig.absoluteMediaURL(path: "/media/meshes/\(pid).usdz"))
        }

        if let raw = object.modelUrl, !raw.isEmpty {
            let lower = raw.lowercased()
            if lower.hasSuffix(".usdz") {
                append(resolveModelURL(raw))
            } else if lower.hasSuffix(".glb") {
                // Same stem under media meshes (Meshy / local generator USDZ sibling).
                if let stem2 = ProductModelCatalog.assetStem(fromModelUrl: raw) {
                    append(Bundle.main.url(forResource: stem2, withExtension: "usdz", subdirectory: "Models"))
                    append(APIConfig.absoluteMediaURL(path: "/media/meshes/\(stem2).usdz"))
                }
                if let pid = object.productId {
                    append(APIConfig.absoluteMediaURL(path: "/media/meshes/\(pid).usdz"))
                }
            } else if lower.contains("/media/meshes/") {
                // Path without extension → try .usdz
                if let base = resolveModelURL(raw) {
                    if base.pathExtension.isEmpty {
                        append(base.appendingPathExtension("usdz"))
                    } else if base.pathExtension.lowercased() == "glb" {
                        append(base.deletingPathExtension().appendingPathExtension("usdz"))
                    } else {
                        append(base)
                    }
                }
            }
        }

        return out
    }

    static func resolveModelURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return URL(string: trimmed)
        }
        if trimmed.hasPrefix("/") {
            return APIConfig.baseURL.appendingPathComponent(String(trimmed.dropFirst()))
        }
        return APIConfig.baseURL.appendingPathComponent(trimmed)
    }

    // MARK: - Disk cache

    private static func materializeFileURL(_ url: URL) async -> URL? {
        if url.isFileURL { return url }
        let name = url.lastPathComponent
        guard name.lowercased().hasSuffix(".usdz") else { return nil }
        let dest = cacheDir.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: dest.path) {
            return dest
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return nil
            }
            try data.write(to: dest, options: .atomic)
            return dest
        } catch {
            return nil
        }
    }

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
        // Large parent box so drag hit-tests remain reliable.
        if let bounds = Optional(root.visualBounds(relativeTo: nil)) {
            let size = bounds.extents
            if size.x > 0.01, size.y > 0.01, size.z > 0.01 {
                // CollisionComponent on non-ModelEntity via children already; OK.
            }
        }
    }
}

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
