// Diapason — Settings section for the Diapason Uploader sidecar.
// Copyright (C) 2026 Arnaud BEUX
// Licensed under the GNU General Public License v3.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

struct ServerUploadSectionView: View {
    @AppStorage(UploaderClient.Keys.enabled) private var enabled = false
    @AppStorage(UploaderClient.Keys.url) private var url = ""
    @AppStorage(UploaderClient.Keys.token) private var token = ""
    @AppStorage(UploaderClient.Keys.networkPolicy) private var networkPolicy = "local"

    var body: some View {
        Section {
            Toggle(isOn: $enabled) {
                Label {
                    Text("Upload to server")
                } icon: {
                    SettingsIcon(systemImage: "square.and.arrow.up.on.square", color: .teal)
                }
            }
            if enabled {
                TextField("http://host:8688", text: $url)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
                SecureField("Token", text: $token)
                Picker("Network", selection: $networkPolicy) {
                    Text("Local network only").tag("local")
                    Text("Local + Internet").tag("internet")
                }
            }
        } header: {
            Text("Server Upload")
        } footer: {
            Text("Push downloaded tracks into your music server's library via a Diapason Uploader compatible sidecar next to Navidrome/Plex. \"Local network only\" uploads on your LAN; use a token and TLS for Internet.")
        }
    }
}
