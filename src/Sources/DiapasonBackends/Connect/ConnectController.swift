// Diapason — bridges Diapason Connect (LAN control/receiver) to Cassette's player.
// Copyright (C) 2026 Arnaud BEUX
// Licensed under the GNU General Public License v3.0.
// See LICENSE file in the project root for full license information.

import SwiftUI
import Combine

@MainActor
final class ConnectController: ObservableObject {
    let manager = ConnectManager()
    private weak var container: AppContainer?
    private var cancellable: AnyCancellable?
    private var started = false

    func start(container: AppContainer) {
        guard !started else { return }
        started = true
        self.container = container

        cancellable = manager.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }

        manager.localStatusProvider = { [weak self] in self?.currentStatus() ?? .stopped }
        manager.onCommandReceived = { [weak self] action, position, _ in self?.apply(action, position) }
        manager.startServer()
        manager.startDiscovery()
    }

    func toggle(_ device: ConnectDevice) {
        if manager.connectedDevice == device { manager.disconnect() }
        else { manager.connect(to: device) }
    }

    func send(_ action: String, position: Double? = nil) {
        manager.sendCommand(action, position: position)
    }

    private func currentStatus() -> ConnectStatus {
        guard let ps = container?.playerState else { return .stopped }
        let song = ps.currentTrack.map {
            ConnectStatus.Song(id: $0.id, title: $0.title, artist: $0.artist ?? "",
                               album: $0.albumName ?? "", duration: $0.duration, art: $0.coverArtId)
        }
        let state = ps.playbackState == .playing ? "playing" : (ps.currentTrack == nil ? "stopped" : "paused")
        return ConnectStatus(song: song, state: state, position: ps.position, volume: 1)
    }

    private func apply(_ action: String, _ position: Double?) {
        guard let player = container?.playerService else { return }
        Task {
            switch action {
            case "play":     await player.resume()
            case "pause":    await player.pause()
            case "next":     try? await player.skipToNext()
            case "previous": try? await player.skipToPrevious()
            case "seek":     if let p = position { await player.seek(to: p) }
            default: break
            }
        }
    }
}

private extension ConnectStatus {
    static var stopped: ConnectStatus { ConnectStatus(song: nil, state: "stopped", position: 0, volume: 1) }
}

struct ConnectSettingsSection: View {
    @Environment(\.appContainer) private var container
    @StateObject private var controller = ConnectController()

    var body: some View {
        Section {
            if controller.manager.discoveredDevices.isEmpty {
                Label("Searching for Diapason on your network…", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(controller.manager.discoveredDevices) { device in
                Button {
                    controller.toggle(device)
                } label: {
                    HStack {
                        Image(systemName: "desktopcomputer")
                        Text(device.name)
                        Spacer()
                        if controller.manager.connectedDevice == device {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.cassetteAccent)
                        }
                    }
                }
            }

            if controller.manager.connectedDevice != nil, let remote = controller.manager.remoteStatus {
                VStack(alignment: .leading, spacing: 6) {
                    if let song = remote.song {
                        Text(song.title).font(.callout).fontWeight(.semibold)
                        Text(song.artist).font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Nothing playing").font(.caption).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 28) {
                        Button { controller.send("previous") } label: { Image(systemName: "backward.fill") }
                        Button { controller.send(remote.state == "playing" ? "pause" : "play") } label: {
                            Image(systemName: remote.state == "playing" ? "pause.fill" : "play.fill")
                        }
                        Button { controller.send("next") } label: { Image(systemName: "forward.fill") }
                    }
                    .font(.title3)
                    .foregroundStyle(Color.cassetteAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Diapason Connect")
        } footer: {
            Text("Control a Diapason desktop on your network, or let it control this device.")
                .font(.footnote)
        }
        .onAppear { if let container { controller.start(container: container) } }
    }
}
