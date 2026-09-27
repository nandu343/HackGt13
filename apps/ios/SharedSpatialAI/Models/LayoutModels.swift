import Foundation

/// Layout AI DTOs — mirror `packages/schema` LayoutRequest / LayoutResponse / CatalogItem.

struct LayoutRequestDTO: Codable, Sendable {
    var sceneId: String
    var prompt: String
    var guestCount: Int
    var budget: Double
}

struct LayoutConstraintsDTO: Codable, Sendable {
    var budget: Double? = nil
    var guestCount: Int? = nil
    var mustHave: [String]? = nil
    var clearCenter: Bool? = nil
}

/// Bang-for-buck product choice from `/ai/layout` (mirrors schema `valuePicks`).
struct ValuePickDTO: Codable, Equatable, Identifiable, Sendable {
    var productId: String
    var name: String? = nil
    var score: Double
    var reason: String
    var objectId: String? = nil
    var replacedProductId: String? = nil
    var rating: Double? = nil
    var price: Double? = nil

    var id: String { "\(objectId ?? "")-\(productId)" }
}

struct LayoutResponseDTO: Codable, Sendable {
    var scenario: String
    var reasoningSummary: String
    var operations: [SceneOperationDTO]
    var constraints: LayoutConstraintsDTO? = nil
    var warnings: [String]? = nil
    var plannerMode: String? = nil
    var fixedOps: Int? = nil
    var valuePicks: [ValuePickDTO]? = nil
}

/// Catalog product — mirrors `packages/schema` CatalogItem / Product.
struct CatalogItemDTO: Codable, Equatable, Identifiable, Sendable {
    var productId: String
    var name: String
    var price: Double
    var currency: String? = nil
    var dimensions: DimensionsDTO? = nil
    var assetId: String? = nil
    var modelUrl: String? = nil
    /// Short shop blurb (optional).
    var description: String? = nil
    /// Retailer product page — “Open website” in Plan / Shop.
    var productUrl: String? = nil
    /// Alias some feeds use; prefer `productUrl`.
    var websiteUrl: String? = nil
    var tags: [String]? = nil
    var purchasable: Bool? = nil
    var virtualOnly: Bool? = nil
    var rating: Double? = nil
    /// Mirrors schema qualityTier (budget / standard / premium).
    var qualityTier: String? = nil
    var category: String? = nil
    var thumbnailUrl: String? = nil

    var id: String { productId }

    /// Prefer explicit description; otherwise derive a short line from tags + dimensions.
    var descriptionText: String? {
        if let description, !description.isEmpty { return description }
        var parts: [String] = []
        if let tier = qualityTier { parts.append(tier.capitalized) }
        if let tags, !tags.isEmpty {
            parts.append(tags.prefix(3).joined(separator: " · "))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Prefer productUrl, fall back to websiteUrl.
    var openWebsiteURL: URL? {
        let raw = productUrl ?? websiteUrl
        guard let raw, !raw.isEmpty, let url = URL(string: raw) else { return nil }
        return url
    }

    /// Price for UI — never formats an optional.
    var priceDisplay: String {
        virtualOnly == true ? "Free" : String(format: "$%.0f", price)
    }

    var ratingDisplay: String? {
        guard let rating else { return nil }
        return String(format: "★ %.1f", rating)
    }
}
