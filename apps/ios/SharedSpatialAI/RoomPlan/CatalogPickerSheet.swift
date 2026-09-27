import SwiftUI

/// Searchable catalog picker — GET /catalog → ADD_OBJECT in Live AR.
struct CatalogPickerSheet: View {
    @Environment(SceneSyncStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var isLoading = false

    private var filtered: [CatalogItemDTO] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return store.catalog }
        return store.catalog.filter { item in
            item.name.lowercased().contains(q)
                || (item.category?.lowercased().contains(q) ?? false)
                || item.productId.lowercased().contains(q)
                || (item.tags?.joined(separator: " ").lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && store.catalog.isEmpty {
                    ProgressView("Loading catalog…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if store.catalog.isEmpty {
                    ContentUnavailableView(
                        "Catalog unavailable",
                        systemImage: "shippingbox",
                        description: Text("Check API connection in Settings, then try again.")
                    )
                } else {
                    List(filtered) { item in
                        Button {
                            Task {
                                await store.placeCatalogItem(item)
                                dismiss()
                            }
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: iconName(for: item))
                                    .font(.title3)
                                    .foregroundStyle(.cyan)
                                    .frame(width: 36)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.name)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(.primary)
                                    HStack(spacing: 6) {
                                        Text(String(format: "$%.0f", item.price))
                                        if let cat = item.category, !cat.isEmpty {
                                            Text("·")
                                            Text(cat.capitalized)
                                        }
                                        if let rating = item.rating {
                                            Text("·")
                                            Text(String(format: "★%.1f", rating))
                                        }
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .disabled(store.isBusy)
                    }
                    .listStyle(.insetGrouped)
                    .searchable(text: $query, prompt: "Search furniture")
                }
            }
            .background(Color(red: 0.06, green: 0.07, blue: 0.09))
            .navigationTitle("Place item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task {
                            isLoading = true
                            await store.loadCatalogIfNeeded(force: true)
                            isLoading = false
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .task {
                isLoading = store.catalog.isEmpty
                await store.loadCatalogIfNeeded()
                isLoading = false
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func iconName(for item: CatalogItemDTO) -> String {
        let t = (item.category ?? item.productId).lowercased()
        if t.contains("sofa") || t.contains("couch") { return "sofa.fill" }
        if t.contains("chair") || t.contains("stool") { return "chair.fill" }
        if t.contains("table") || t.contains("desk") { return "table.furniture.fill" }
        if t.contains("lamp") || t.contains("light") { return "lightbulb.fill" }
        if t.contains("plant") { return "leaf.fill" }
        if t.contains("rug") { return "rectangle.fill" }
        return "cube.fill"
    }
}
