// Diapason Watch — Diapason Connect client.
// Copyright (C) 2026 Arnaud BEUX
// Licensed under the GNU General Public License v3.0.
// See LICENSE file in the project root for full license information.

import Foundation
import Network
import os

private let connectLog = Logger(subsystem: "fr.nytuo.diapason.watch", category: "Connect")

/// The Diapason phone (or desktop) app, as seen on the network.
struct WatchPeer: Identifiable, Hashable {
    let id = UUID()
    let name: String

    /// `http://<host>:<port>/<token>/connect` — the token is in the path, so the
    /// URL itself is the permission.
    let baseUrl: String

    func endpoint(_ path: String) -> URL? { URL(string: "\(baseUrl)/\(path)") }
}

/// Talks to the Diapason app over Diapason Connect.
///
/// This replaces the old WatchConnectivity link, which could only ever reach the
/// iOS app that embedded this watch app — and that app is gone: phones are served
/// by the Flutter app now. WatchConnectivity cannot reach it, so the watch speaks
/// the same LAN protocol every other Diapason device speaks.
///
/// The phone is needed to *fetch* the catalogue and to remote-control playback.
/// It is not needed to play: downloads live on the watch, and stream URLs point
/// at the music server directly.
@MainActor
final class WatchConnect: ObservableObject {
    @Published private(set) var peers: [WatchPeer] = []
    @Published private(set) var isScanning = false
    @Published var connectedPeer: WatchPeer?

    /// The phone's playback state, when we are acting as its remote.
    @Published private(set) var remoteStatus: RemoteStatus?

    struct RemoteStatus: Decodable {
        struct Song: Decodable {
            let title: String
            let artist: String
        }
        let song: Song?
        let state: String
        let position: Double

        var isPlaying: Bool { state == "playing" }
    }

    private var browser: NWBrowser?
    private var pollTask: Task<Void, Never>?

    // MARK: - Discovery

    /// Finds Diapason instances advertising `_diapason-connect._tcp`.
    ///
    /// Built on Network.framework rather than NetService: NetService does not
    /// exist on watchOS. NWBrowser hands us the TXT record (and therefore the
    /// token) directly, and NWConnection resolves the service to a host and port.
    func startDiscovery() {
        stopDiscovery()
        isScanning = true
        peers = []

        let parameters = NWParameters()
        parameters.includePeerToPeer = false
        let browser = NWBrowser(for: .bonjour(type: "_diapason-connect._tcp", domain: nil), using: parameters)

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            for result in results {
                // The token lives in the TXT record. An advertisement without one
                // cannot be addressed, so it is ignored.
                guard case let .bonjour(txt) = result.metadata,
                      let token = txt["token"], !token.isEmpty
                else { continue }

                Task { @MainActor [weak self] in
                    self?.resolve(result.endpoint, token: token)
                }
            }
        }
        browser.start(queue: .main)
        self.browser = browser

        // Browsing never ends on its own; the spinner should.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            self?.isScanning = false
        }
    }

    func stopDiscovery() {
        browser?.cancel()
        browser = nil
        isScanning = false
    }

    /// Turns a Bonjour endpoint into an address we can send HTTP to.
    ///
    /// A browse result names the service but does not carry its address, so a
    /// connection is opened purely to read the resolved host and port back off it,
    /// then cancelled.
    private func resolve(_ endpoint: NWEndpoint, token: String) {
        let name: String
        if case let .service(serviceName, _, _, _) = endpoint {
            name = serviceName
        } else {
            name = "Diapason"
        }

        let connection = NWConnection(to: endpoint, using: .tcp)
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard case .ready = state,
                  let remote = connection?.currentPath?.remoteEndpoint,
                  case let .hostPort(host, port) = remote
            else {
                if case .failed = state { connection?.cancel() }
                return
            }

            // Strip the IPv6 zone ("fe80::1%en0") and the interface suffix that
            // NWEndpoint.Host prints, or the URL will not parse.
            var address = "\(host)"
            if let percent = address.firstIndex(of: "%") {
                address = String(address[..<percent])
            }
            let literal = address.contains(":") ? "[\(address)]" : address

            let peer = WatchPeer(name: name, baseUrl: "http://\(literal):\(port.rawValue)/\(token)/connect")
            connection?.cancel()

            Task { @MainActor [weak self] in
                guard let self else { return }
                if !self.peers.contains(where: { $0.baseUrl == peer.baseUrl }) {
                    self.peers.append(peer)
                    connectLog.notice("Found \(peer.name)")
                }
            }
        }
        connection.start(queue: .main)
    }

    // MARK: - Catalogue

    /// Fetches the library the phone is willing to share.
    ///
    /// Only needed when the catalogue is stale — the watch keeps it, so this is a
    /// sync, not a dependency.
    func fetchLibrary(from peer: WatchPeer) async -> [WatchTrack] {
        guard let url = peer.endpoint("library") else { return [] }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }

            struct Payload: Decodable {
                struct Track: Decodable {
                    let id: String
                    let title: String
                    let artist: String
                    let album: String
                    let duration: Int
                    let streamUrl: String
                    let art: String?
                }
                let tracks: [Track]
            }

            let payload = try JSONDecoder().decode(Payload.self, from: data)
            connectLog.notice("Fetched \(payload.tracks.count) track(s) from \(peer.name)")

            return payload.tracks.map {
                WatchTrack(
                    id: $0.id,
                    title: $0.title,
                    artist: $0.artist,
                    album: $0.album,
                    duration: $0.duration,
                    streamUrl: $0.streamUrl,
                    artUrl: $0.art,
                    filename: nil
                )
            }
        } catch {
            connectLog.error("Could not fetch the library: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Remote control

    func connect(to peer: WatchPeer) {
        connectedPeer = peer
        startPolling()
    }

    func disconnect() {
        pollTask?.cancel()
        pollTask = nil
        connectedPeer = nil
        remoteStatus = nil
    }

    func sendCommand(_ action: String) {
        guard let peer = connectedPeer, let url = peer.endpoint("command") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["action": action])

        Task {
            _ = try? await URLSession.shared.data(for: request)
            await pollOnce()
        }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollOnce()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func pollOnce() async {
        guard let peer = connectedPeer, let url = peer.endpoint("status") else { return }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let status = try? JSONDecoder().decode(RemoteStatus.self, from: data)
        else { return }
        remoteStatus = status
    }
}
