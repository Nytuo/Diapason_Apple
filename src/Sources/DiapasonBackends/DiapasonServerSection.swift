// Diapason — Settings section to switch the active server/backend and add new ones.
// Copyright (C) 2026 Arnaud BEUX
// Licensed under the GNU General Public License v3.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

struct DiapasonServerSection: View {
    @Environment(\.appContainer) private var container
    @State private var showAdd = false
    @State private var editServer: ServerSnapshot?

    private var servers: [ServerSnapshot] { container?.serverState.servers ?? [] }
    private var activeId: UUID? { container?.serverState.activeServer?.id }

    var body: some View {
        Section("Servers") {
            ForEach(servers, id: \.id) { server in
                Button {
                    switchTo(server)
                } label: {
                    HStack {
                        SettingsIcon(systemImage: icon(server.backendKind), color: Color.accent)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(server.displayName)
                                .foregroundStyle(DiapasonColors.textPrimary)
                            Text(label(server.backendKind))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if server.id == activeId {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accent)
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            if let active = container?.serverState.activeServer,
               active.backendKind == "subsonic",
               let serverService = container?.serverService {
                NavigationLink {
                    EditServerDestinationView(server: active, serverService: serverService)
                } label: {
                    Label { Text("Edit Active Server") } icon: {
                        SettingsIcon(systemImage: "slider.horizontal.3", color: .gray)
                    }
                }
            }

            Button {
                showAdd = true
            } label: {
                Label { Text("Add Server") } icon: {
                    SettingsIcon(systemImage: "plus", color: .green)
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            if let serverService = container?.serverService {
                AddServerSheet(serverService: serverService)
            }
        }
    }

    private func switchTo(_ server: ServerSnapshot) {
        guard server.id != activeId, let serverService = container?.serverService else { return }
        Task { try? await serverService.setActiveServer(id: server.id) }
    }

    private func icon(_ kind: String) -> String {
        switch kind { case "plex": return "play.rectangle.on.rectangle"; case "local": return "folder"; default: return "server.rack" }
    }
    private func label(_ kind: String) -> String {
        switch kind { case "plex": return "Plex"; case "local": return "Local Files"; default: return "Subsonic" }
    }
}

private struct AddServerSheet: View {
    let serverService: any ServerServiceProtocol
    @Environment(\.appContainer) private var container
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: OnboardingViewModel
    @State private var startCount: Int = 0

    init(serverService: any ServerServiceProtocol) {
        self.serverService = serverService
        _viewModel = State(initialValue: OnboardingViewModel(serverService: serverService))
    }

    var body: some View {
        NavigationStack {
            ServerFormView(viewModel: viewModel)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
        }
        .onAppear { startCount = container?.serverState.servers.count ?? 0 }
        .onChange(of: container?.serverState.servers.count ?? 0) { _, newCount in
            if newCount > startCount { dismiss() }
        }
    }
}
