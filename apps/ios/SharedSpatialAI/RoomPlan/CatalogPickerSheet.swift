import SwiftUI

/// Searchable catalog picker — GET /catalog → ADD_OBJECT with product model + 1:1 dimensions.
struct CatalogPickerSheet: View {
    @Environment(SceneSyncStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var isLoading = false
    @State private var categoryFilter: String = "All"

    private var categories: [String] {
        let cats = Set(store.catalog.compactMap(\.category).filter { !$0.isEmpty })
        return ["All"] + cats.sorted()
    }

    private var filtered: [CatalogItemDTO] {
        var items = store.catalog
        if categoryFilter != "All" {
            items = items.filter { $0.category == categoryFilter }
        }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return items }
        return items.filter { item in
            item.name.lowercased().contains(q)
                || (item.category?.lowercased().contains(q) ?? false)
                || item.productId.lowercased().contains(q)
                || (item.tags?.joined(separator: " ").lowercased().contains(q) ?? false)
                || (item.descriptionText?.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && store.catalog.isEmpty {
                    ProgressView("Loading catalog…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if store.catalog.isEmpty {
                    ContentUnavailableView {
                        Label("Catalog unavailable", systemImage: "shippingbox")
                    } description: {
                        Text(store.lastError ?? "Check API connection in Settings, then reload.")
                    } actions: {
                        Button("Reload") {
                            Task {
                                isLoading = true
                                await store.loadCatalogIfNeeded(force: true)
                                isLoading = false
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        if categories.count > 2 {
                            Section {
                                Picker("Category", selection: $categoryFilter) {
                                    ForEach(categories, id: \.self) { Text($0).tag($0) }
                                }
                                .pickerStyle(.menu)
                            }
                        }
                        Section {
                            Text("\(filtered.count) of \(store.catalog.count) items · 1:1 m scale in AR")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(filtered) { item in
                            Button {
                                Task {
                                    await store.placeCatalogItem(item)
                                    dismiss()
                                }
                            } label: {
                                catalogRow(item)
                            }
                            .disabled(store.isBusy)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .searchable(text: $query, prompt: "Search all furniture")
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
        .preferredColorScheme(.dark)
    }

    private func catalogRow(_ item: CatalogItemDTO) -> some View {
        HStack(spacing: 14) {
            Image(systemName: iconName(for: item))
                .font(.title3)
                .foregroundStyle(.cyan)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(item.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    if item.virtualOnly == true {
                        Text("VIRTUAL")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.purple.opacity(0.35), in: Capsule())
                    }
                }
                if let desc = item.descriptionText, !desc.isEmpty {
                    Text(desc)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
                HStack(spacing: 6) {
                    Text(item.priceDisplay)
                    if let cat = item.category, !cat.isEmpty {
                        Text("·")
                        Text(cat.capitalized)
                    }
                    if let dims = item.dimensions {
                        Text("·")
                        Text(dims.displayMetersCompact)
                    }
                    if let rating = item.ratingDisplay {
                        Text("·")
                        Text(rating)
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

    private func iconName(for item: CatalogItemDTO) -> String {
        let pid = item.productId.lowercased()
        let t = (item.category ?? "").lowercased() + " " + item.name.lowercased() + " " + pid
        if t.contains("sofa") || t.contains("couch") { return "sofa.fill" }
        if t.contains("bean") { return "oval.fill" }
        if t.contains("stool") { return "chair.fill" }
        if t.contains("chair") { return "chair.fill" }
        if t.contains("desk") { return "table.furniture.fill" }
        if t.contains("table") { return "table.furniture.fill" }
        if t.contains("pendant") || t.contains("string") || t.contains("light") { return "lightbulb.fill" }
        if t.contains("lamp") { return "lamp.floor.fill" }
        if t.contains("plant") { return "leaf.fill" }
        if t.contains("rug") { return "rectangle.fill" }
        if t.contains("screen") || t.contains("projector") { return "tv.fill" }
        if t.contains("backdrop") { return "photo.fill" }
        if t.contains("virtual") || t.contains("glow") || t.contains("marker") { return "sparkles" }
        return "cube.fill"
    }
}
