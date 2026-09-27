import Foundation

/// Layout AI DTOs — mirror `packages/schema` LayoutRequest / LayoutResponse / CatalogItem.

struct LayoutRequestDTO: Codable, Sendable {
    var sceneId: String
    var prompt: String
    var guestCount: Int
    var budget: Double
}

struct LayoutConstraintsDTO: Codable, Sendable {
    var budget: Double?
    var guestCount: Int?
    var mustHave: [String]?
    var clearCenter: Bool?
}

/// Bang-for-buck product choice from `/ai/layout` (mirrors schema `valuePicks`).
struct ValuePickDTO: Codable, Equatable, Identifiable, Sendable {
    var productId: String
    var name: String?
    var score: Double
    var reason: String
    var objectId: String?
    var replacedProductId: String?
    var rating: Double?
    var price: Double?

    var id: String { "\(objectId ?? "")-\(productId)" }
}

struct LayoutResponseDTO: Codable, Sendable {
    var scenario: String
    var reasoningSummary: String
    var operations: [SceneOperationDTO]
    var constraints: LayoutConstraintsDTO
    var warnings: [String]?
    var plannerMode: String?
    var fixedOps: Int?
    var valuePicks: [ValuePickDTO]?
}

/// Catalog product — mirrors `packages/schema` CatalogItem / Product.
struct CatalogItemDTO: Codable, Equatable, Identifiable, Sendable {
    var productId: String
    var name: String
    var price: Double
    var currency: String?
    var dimensions: DimensionsDTO?
    var assetId: String?
    var modelUrl: String?
    /// Retailer product page — “Open website” in Plan / Shop.
    var productUrl: String?
    /// Alias some feeds use; prefer `productUrl`.
    var websiteUrl: String?
    var tags: [String]?
    var purchasable: Bool?
    var virtualOnly: Bool?
    var rating: Double?
    /// Mirrors schema qualityTier (budget / standard / premium).
    var qualityTier: String?
    var category: String?
    var thumbnailUrl: String?

    var id: String { productId }

    /// Prefer productUrl, fall back to websiteUrl.
    var openWebsiteURL: URL? {
        let raw = productUrl ?? websiteUrl
        guard let raw, !raw.isEmpty, let url = URL(string: raw) else { return nil }
        return url
    }
}
