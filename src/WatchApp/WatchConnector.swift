// Diapason Watch — receives synced offline files from the paired iPhone.
// Copyright (C) 2026 Arnaud BEUX
// Licensed under the GNU General Public License v3.0.
// See LICENSE file in the project root for full license information.

import Foundation
import WatchConnectivity
import OSLog

private let watchLog = Logger(subsystem: "fr.nytuo.Diapason.watchkitapp", category: "watch-sync")

@MainActor
final class WatchConnector: NSObject, ObservableObject {
    private weak var store: WatchLibraryStore?

    func configure(store: WatchLibraryStore) {
        self.store = store
        activate()
    }

    private func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        watchLog.notice("Watch WCSession activate() called")
    }
}

extension WatchConnector: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
        watchLog.notice("Watch WCSession activated: state=\(activationState.rawValue) error=\(error?.localizedDescription ?? "none", privacy: .public)")
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        watchLog.notice("Watch didReceive file kind=\((file.metadata?["kind"] as? String) ?? "?", privacy: .public)")
        // WatchConnectivity removes the received file as soon as this method
        // returns, so copy it to a stable temp URL synchronously before hopping
        // to the main actor to ingest it.
        let metadata = file.metadata ?? [:]
        let stable = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "-" + file.fileURL.lastPathComponent)
        do {
            try FileManager.default.copyItem(at: file.fileURL, to: stable)
        } catch {
            return
        }
        Task { @MainActor in
            defer { try? FileManager.default.removeItem(at: stable) }
            switch metadata["kind"] as? String {
            case "cover": self.store?.ingestCover(from: stable, metadata: metadata)
            default:      self.store?.ingestTrack(from: stable, metadata: metadata)
            }
        }
    }
}
