// Diapason — Settings section for importing audio into the Local backend.
// Copyright (C) 2026 Arnaud BEUX
// Licensed under the GNU General Public License v3.0.
// See LICENSE file in the project root for full license information.

import SwiftUI
import UniformTypeIdentifiers

struct LocalImportSectionView: View {
    @Environment(\.appContainer) private var container
    @State private var isPicking = false
    @State private var isImporting = false
    @State private var lastResult: String?

    private var isLocalActive: Bool {
        container?.serverState.activeServer?.backendKind == "local"
    }

    var body: some View {
        if isLocalActive {
            Section("Local Library") {
                Button {
                    isPicking = true
                } label: {
                    Label(isImporting ? "Importing…" : "Import Music Files", systemImage: "square.and.arrow.down")
                }
                .disabled(isImporting)

                if let lastResult {
                    Text(lastResult)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .fileImporter(
                isPresented: $isPicking,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: true
            ) { result in
                handle(result)
            }
        }
    }

    private func handle(_ result: Result<[URL], Error>) {
        guard let container else { return }
        switch result {
        case .failure(let error):
            lastResult = "Import failed: \(error.localizedDescription)"
        case .success(let urls):
            isImporting = true
            lastResult = nil
            Task {
                var imported = 0
                for url in urls {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    if await container.localLibrary.importFile(from: url, filename: url.lastPathComponent) != nil {
                        imported += 1
                    }
                }
                await MainActor.run {
                    isImporting = false
                    lastResult = "Imported \(imported) file\(imported == 1 ? "" : "s"). Pull to refresh your library."
                }
            }
        }
    }
}
