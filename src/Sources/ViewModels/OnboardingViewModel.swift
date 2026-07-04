// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import Observation

@Observable
@MainActor
final class OnboardingViewModel {
    /// Diapason: which backend the user is adding.
    enum Backend: String, CaseIterable, Identifiable {
        case subsonic, plex, local
        var id: String { rawValue }
        var label: String {
            switch self { case .subsonic: return "Subsonic"; case .plex: return "Plex"; case .local: return "Local Files" }
        }
    }
    var backend: Backend = .subsonic

    var serverURL: String = ""
    var username: String = ""
    var password: String = ""
    var customHeaders: [CustomHeaderEntry] = []
    var isLoading: Bool = false
    var connectionError: ConnectionTestError?

    /// Display name derived from the URL host, falling back to the raw URL string.
    var derivedDisplayName: String {
        URL(string: serverURL.trimmingCharacters(in: .whitespaces))?.host ?? serverURL
    }

    var canSubmit: Bool {
        switch backend {
        case .subsonic:
            return !serverURL.trimmingCharacters(in: .whitespaces).isEmpty && !username.isEmpty && !password.isEmpty
        case .plex:
            // Plex: server URL + token (token entered in the password field).
            return !serverURL.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
        case .local:
            return true
        }
    }

    var isHTTP: Bool {
        serverURL.lowercased().hasPrefix("http://")
    }

    private let serverService: any ServerServiceProtocol

    init(serverService: any ServerServiceProtocol) {
        self.serverService = serverService
    }

    func testConnection() async {
        guard !isLoading else { return }
        connectionError = nil
        isLoading = true
        defer { isLoading = false }

        do {
            try await serverService.testConnection(
                url: serverURL,
                username: username,
                password: password,
                customHeaders: headersDict()
            )
        } catch let error as ConnectionTestError {
            connectionError = error
        } catch {
            let e = error as NSError
            connectionError = .unknown(domain: e.domain, code: e.code)
        }
    }

    /// Validates, tests, and persists the server in a single flow.
    /// On success state.activeServer becomes non-nil and RootView transitions automatically.
    func addServer() async {
        guard !isLoading else { return }
        connectionError = nil
        isLoading = true
        defer { isLoading = false }

        switch backend {
        case .subsonic: await addSubsonic()
        case .plex:     await addPlex()
        case .local:    await addLocal()
        }
    }

    private func addSubsonic() async {
        let trimmedURL = serverURL.trimmingCharacters(in: .whitespaces)
        let headers = headersDict()
        do {
            try await serverService.testConnection(url: trimmedURL, username: username, password: password, customHeaders: headers)
        } catch let error as ConnectionTestError {
            connectionError = error; return
        } catch {
            let e = error as NSError; connectionError = .unknown(domain: e.domain, code: e.code); return
        }
        do {
            try await serverService.addServer(displayName: derivedDisplayName, baseURL: trimmedURL,
                                              username: username, password: password, customHeaders: headers, backendKind: "subsonic")
        } catch {
            let e = error as NSError; connectionError = .unknown(domain: e.domain, code: e.code)
        }
    }

    /// Plex: token is entered in the password field; ping /library/sections to validate.
    private func addPlex() async {
        let trimmedURL = serverURL.trimmingCharacters(in: .whitespaces)
        let base = trimmedURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/library/sections?X-Plex-Token=\(password)") else {
            connectionError = .invalidURL; return
        }
        do {
            var req = URLRequest(url: url)
            req.addValue("application/json", forHTTPHeaderField: "Accept")
            let (_, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                connectionError = .unauthorized; return
            }
        } catch {
            let e = error as NSError; connectionError = .unknown(domain: e.domain, code: e.code); return
        }
        do {
            try await serverService.addServer(displayName: derivedDisplayName, baseURL: trimmedURL,
                                              username: "plex", password: password, customHeaders: [:], backendKind: "plex")
        } catch {
            let e = error as NSError; connectionError = .unknown(domain: e.domain, code: e.code)
        }
    }

    /// Local: no server — create a local library entry. Files are imported afterwards.
    private func addLocal() async {
        do {
            try await serverService.addServer(displayName: "Local Library", baseURL: "",
                                              username: "local", password: "", customHeaders: [:], backendKind: "local")
        } catch {
            let e = error as NSError; connectionError = .unknown(domain: e.domain, code: e.code)
        }
    }

    func addCustomHeader() {
        customHeaders.append(CustomHeaderEntry())
    }

    func removeCustomHeader(id: UUID) {
        customHeaders.removeAll { $0.id == id }
    }

    // MARK: - Private

    var redactedDescription: String {
        "OnboardingViewModel(username: \(username), password: [REDACTED], customHeaders: [REDACTED])"
    }

    private func headersDict() -> [String: String] {
        var dict: [String: String] = [:]
        for pair in customHeaders where !pair.key.isEmpty {
            dict[pair.key] = pair.value
        }
        return dict
    }
}
