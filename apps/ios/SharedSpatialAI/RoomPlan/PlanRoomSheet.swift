import SwiftUI

/// Post-scan / post-demo intent sheet: ask what to make the room into, call `/ai/layout`, apply ops.
struct PlanRoomSheet: View {
    @Environment(SceneSyncStore.self) private var store
    @Environment(\.dismiss) private var dismiss

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
            case .movie: return "Movie night"
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
        let base: String
        if scenario == .custom {
            base = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            let extra = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            base = extra.isEmpty ? scenario.prompt : "\(scenario.prompt) Extra notes: \(extra)"
        }
        return base
    }

    var body: some View {
        NavigationStack {
            Form {
                if phase == .compose {
                    Section {
                        Text("What do you and your friends want to make this space into?")
                            .font(.headline)
                        Text("AI returns recommended ops; Accept places them in the shared scene (web twin + AR).")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Section("Scenario") {
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
                    }

                    Section("Constraints") {
                        Stepper("Guests: \(guestCount)", value: $guestCount, in: 1...100)
                        HStack {
                            Text("Budget $")
                            Spacer()
                            TextField("Budget", value: $budget, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 120)
                        }
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
                } else {
                    Section("Recommendations") {
                        if let preview {
                            LabeledContent("Scenario", value: preview.scenario)
                            if let mode = preview.plannerMode {
                                LabeledContent("Planner", value: mode)
                            }
                            Text(preview.reasoningSummary)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
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
                        Text("Ops are applied via POST /scene/{id}/operations. On device, refresh Viewer / AR to see new anchors in the shared Y-up room frame.")
                    }
                }

                if let err = store.lastError {
                    Section {
                        Text(err).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("Plan this room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
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
