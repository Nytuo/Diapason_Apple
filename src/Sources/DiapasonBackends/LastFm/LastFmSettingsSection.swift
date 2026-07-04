// Diapason — Last.fm scrobbling settings.
// Copyright (C) 2026 Arnaud BEUX
// Licensed under the GNU General Public License v3.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

struct LastFmSettingsSection: View {
    @State private var apiKey = LastFmScrobbler.shared.apiKey
    @State private var secret = LastFmScrobbler.shared.apiSecret
    @State private var enabled = LastFmScrobbler.shared.isEnabled
    @State private var username = LastFmScrobbler.shared.username
    @State private var connected = LastFmScrobbler.shared.isConnected
    @State private var pendingToken: String?
    @State private var status: String?
    @Environment(\.openURL) private var openURL

    var body: some View {
        Section {
            if connected {
                HStack {
                    SettingsIcon(systemImage: "waveform.circle.fill", color: .red)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Connected").foregroundStyle(CassetteColors.textPrimary)
                        if let username { Text(username).font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                }
                Toggle(isOn: $enabled) {
                    Label { Text("Scrobble to Last.fm") } icon: {
                        SettingsIcon(systemImage: "dot.radiowaves.left.and.right", color: .red)
                    }
                }
                .onChange(of: enabled) { _, on in LastFmScrobbler.shared.setEnabled(on) }
                Button("Disconnect", role: .destructive) {
                    LastFmScrobbler.shared.disconnect()
                    connected = false; username = nil; enabled = false
                }
            } else {
                SecureField("Last.fm API key", text: $apiKey)
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                SecureField("Last.fm shared secret", text: $secret)
                    .autocorrectionDisabled().textInputAutocapitalization(.never)

                if pendingToken == nil {
                    Button("Authorize in Browser") { Task { await authorize() } }
                        .disabled(apiKey.isEmpty || secret.isEmpty)
                } else {
                    Button("Finish Connecting") { Task { await finish() } }
                    Text("Approve access in the browser, then tap Finish Connecting.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let status {
                    Text(status).font(.footnote).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Last.fm")
        } footer: {
            Text("Create an API account at last.fm/api to get a key and secret, then authorize to scrobble your plays.")
                .font(.footnote)
        }
    }

    private func authorize() async {
        LastFmScrobbler.shared.setCredentials(apiKey: apiKey, secret: secret)
        guard let token = await LastFmScrobbler.shared.getToken() else {
            status = "Could not reach Last.fm. Check your API key."
            return
        }
        pendingToken = token
        if let url = LastFmScrobbler.shared.authURL(token: token) { openURL(url) }
    }

    private func finish() async {
        guard let token = pendingToken else { return }
        if await LastFmScrobbler.shared.completeAuth(token: token) {
            connected = true
            username = LastFmScrobbler.shared.username
            enabled = true
            pendingToken = nil
            status = nil
        } else {
            status = "Authorization not completed yet — approve in the browser and retry."
        }
    }
}
