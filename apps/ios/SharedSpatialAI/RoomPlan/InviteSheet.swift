import SwiftUI
import UIKit

/// Share an API invite link so friends join the same sceneId on the web twin.
struct InviteSheet: View {
    @Environment(SceneSyncStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var link: String?
    @State private var copied = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Friends open this link in the web twin and land on the same room map (`\(store.sceneId)`).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Invite link") {
                    if let link {
                        Text(link)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                        Button(copied ? "Copied" : "Copy link") {
                            UIPasteboard.general.string = link
                            copied = true
                        }
                        ShareLink(item: link) {
                            Label("Share…", systemImage: "square.and.arrow.up")
                        }
                    } else if store.isBusy {
                        ProgressView("Creating invite…")
                    } else {
                        Text("No link yet")
                            .foregroundStyle(.secondary)
                    }
                }

                if let err = store.lastError {
                    Section {
                        Text(err).foregroundStyle(.red).font(.caption)
                    }
                }

                Section {
                    Button("Create / refresh invite") {
                        Task {
                            copied = false
                            link = await store.createInviteLink()
                        }
                    }
                    .disabled(store.isBusy)
                }
            }
            .navigationTitle("Invite friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                if link == nil {
                    link = await store.createInviteLink()
                }
            }
        }
    }
}
