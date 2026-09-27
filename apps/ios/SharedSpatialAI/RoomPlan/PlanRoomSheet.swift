import SwiftUI

/// Post-scan intent sheet: `/ai/layout` preview with recommended products + Open website.
struct PlanRoomSheet: View {
    @Environment(SceneSyncStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var scenario: Scenario = .party
    @State private var notes = ""
    @State private var guestCount = 15
    @State private var budget: Double = 2000
    @State private var preview: LayoutResponseDTO?
    @State private var phase: Phase = .compose

    enum Phase {
        case compose
        case preview
    }

    enum Scenario: String, CaseIterable, Identifiable {
        case party, study, dinner, movie, custom
        var id: String { rawValue }

        var label: String {
            switch self {
            case .party: return "Party"
            case .study: return "Study"
            case .dinner: return "Dinner"
            case .movie: return "Movie"
            case .custom: return "Custom"
            }
        }

        var prompt: String {
            switch self {
            case .party:
                return "Turn this into a lively party space with room for dancing and mingling."
            case .study:
                return "Turn this into a focused study / coworking space with desks and quiet zones."
            case .dinner:
                return "Turn this into a dinner gathering with a clear dining area and seating for guests."
            case .movie:
                return "Turn this into a cozy movie-night lounge with seating facing a screen wall."
            case .custom:
                return ""
            }
        }
    }

    private var composedPrompt: String {
        if scenario == .custom {
            return notes.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let extra = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return extra.isEmpty ? scenario.prompt : "\(scenario.prompt) Extra notes: \(extra)"
    }

    var body: some View {
        NavigationStack {
            Form {
                if phase == .compose {
                    composeSections
                } else {
                    previewSections
                }

                if let err = store.lastError {
                    Section {
                        Text(err).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(red: 0.06, green: 0.07, blue: 0.09))
            .navigationTitle("Plan this room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                await store.loadCatalogIfNeeded()
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var composeSections: some View {
        Section {
            Text("What should this space become?")
                .font(.headline)
            Text("AI returns layout ops and recommended products for Live AR + the web twin.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

        Section {
            Picker("Scenario", selection: $scenario) {
                ForEach(Scenario.allCases) { s in
                    Text(s.label).tag(s)
                }
            }
            .pickerStyle(.segmented)

            TextField(
                scenario == .custom ? "Describe the vibe" : "Optional notes",
                text: $notes,
                axis: .vertical
            )
            .lineLimit(2...4)
        } header: {
            Text("Scenario")
        }

        Section {
            Stepper("Guests: \(guestCount)", value: $guestCount, in: 1...100)
            HStack {
                Text("Budget")
                Spacer()
                TextField("Budget", value: $budget, format: .currency(code: "USD"))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 140)
            }
        } header: {
            Text("Constraints")
        }

        Section {
            Button {
                Task { await generate() }
            } label: {
                if store.isBusy {
                    Label("Thinking…", systemImage: "sparkles")
                } else {
                    Label("Get AI recommendations", systemImage: "wand.and.stars")
                }
            }
            .disabled(store.isBusy || composedPrompt.isEmpty)
        }
    }

    @ViewBuilder
    private var previewSections: some View {
        Section {
            if let preview {
                LabeledContent("Scenario", value: preview.scenario.capitalized)
                if let mode = preview.plannerMode {
                    LabeledContent("Planner", value: mode)
                }
                Text(preview.reasoningSummary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Layout")
        }

        if let picks = preview?.valuePicks, !picks.isEmpty {
            Section {
                ForEach(picks) { pick in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(pick.name ?? pick.productId)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            if let price = pick.price {
                                Text(String(format: "$%.0f", price))
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text(pick.reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let rating = pick.rating {
                            Text(String(format: "★ %.1f · score %.0f", rating, pick.score))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        if let url = store.catalogItem(productId: pick.productId)?.openWebsiteURL {
                            Button {
                                openURL(url)
                            } label: {
                                Label("Open website", systemImage: "safari")
                                    .font(.caption.weight(.semibold))
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("Recommended products")
            }
        }

        Section {
            if let preview {
                ForEach(Array(preview.operations.enumerated()), id: \.offset) { _, op in
                    Text(opSummary(op))
                        .font(.caption.monospaced())
                }
                if let warnings = preview.warnings, !warnings.isEmpty {
                    ForEach(warnings, id: \.self) { w in
                        Text(w).font(.caption).foregroundStyle(.orange)
                    }
                }
            }
        } header: {
            Text("Operations")
        }

        Section {
            Button("Accept into scene") {
                Task { await accept() }
            }
            .disabled(store.isBusy || (preview?.operations.isEmpty ?? true))

            Button("Back") {
                preview = nil
                phase = .compose
            }
            .disabled(store.isBusy)
        } footer: {
            Text("Accept applies ops via POST /scene/{id}/operations. Furniture appears as 3D meshes in Live AR.")
        }
    }

    private func opSummary(_ op: SceneOperationDTO) -> String {
        var parts = [op.type.rawValue]
        if let id = op.objectId { parts.append(id) }
        if let pid = op.productId { parts.append(pid) }
        return parts.joined(separator: " · ")
    }

    private func generate() async {
        store.lastError = nil
        store.isBusy = true
        defer { store.isBusy = false }
        do {
            let layout = try await APIClient.shared.postAiLayout(
                LayoutRequestDTO(
                    sceneId: store.sceneId,
                    prompt: composedPrompt,
                    guestCount: guestCount,
                    budget: budget
                )
            )
            preview = layout
            store.lastLayout = layout
            phase = .preview
            store.statusMessage = "AI ready: \(layout.scenario)"
        } catch {
            store.lastError = error.localizedDescription
            store.statusMessage = "AI layout failed"
        }
    }

    private func accept() async {
        guard let ops = preview?.operations, !ops.isEmpty else { return }
        await store.pushOps(ops)
        if store.lastError == nil {
            dismiss()
        }
    }
}
