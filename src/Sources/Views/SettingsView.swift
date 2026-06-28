import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var backendManager: BackendManager
    @EnvironmentObject var subsonic: SubsonicClient
    @EnvironmentObject var plex: PlexClient

    @StateObject private var discoveryManager = DiscoveryManager()
    @StateObject private var desktopBrowser = DesktopDiapasonBrowser()

    @State private var isTesting = false
    @State private var testResult: String? = nil
    
    @State private var isImporting = false
    @State private var importProgress: String? = nil

    @ObservedObject private var cacheManager = PlaybackCacheManager.shared
    @State private var selectedCacheLimit: Int = PlaybackCacheManager.shared.maxTracks

    var body: some View {
        Form {
            Section(header: Text("Active Backend")) {
                Picker("Source", selection: $backendManager.activeType) {
                    ForEach(BackendType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: backendManager.activeType) { _ in
                    testResult = nil
                }
            }

            // Bonjour Discovery Section
            Section(header: Text("Local Network Discovery")) {
                if discoveryManager.isScanning {
                    HStack {
                        ProgressView().padding(.trailing, 8)
                        Text("Searching for local servers...")
                            .foregroundColor(.secondary)
                    }
                } else {
                    Button(action: {
                        discoveryManager.startDiscovery()
                    }) {
                        Label("Scan Local Network", systemImage: "magnifyingglass")
                            .foregroundColor(.red)
                    }
                }

                if !discoveryManager.discoveredServers.isEmpty {
                    ForEach(discoveryManager.discoveredServers) { server in
                        Button(action: {
                            selectDiscoveredServer(server)
                        }) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(server.name)
                                    .font(.body)
                                    .foregroundColor(.primary)
                                Text("\(server.type.rawValue) · \(server.url)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            
            // mDNS Desktop File Sharing Section
            Section(header: Text("mDNS File Sharing (Desktop Diapason)")) {
                if isImporting {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            ProgressView().padding(.trailing, 8)
                            Text(importProgress ?? "Importing...")
                        }
                        Text("Please keep the app open and connected to the same Wi-Fi.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    if desktopBrowser.isScanning {
                        HStack {
                            ProgressView().padding(.trailing, 8)
                            Text("Scanning for desktop Diapason...")
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Button(action: {
                            desktopBrowser.start()
                        }) {
                            Label("Scan for Desktop Diapason", systemImage: "wifi")
                                .foregroundColor(.red)
                        }
                    }
                    
                    if !desktopBrowser.discoveredPeers.isEmpty {
                        ForEach(desktopBrowser.discoveredPeers) { peer in
                            Button(action: {
                                importFromDesktop(peer: peer)
                            }) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(peer.name)
                                        .font(.body)
                                        .foregroundColor(.primary)
                                    Text("Tap to receive files · \(peer.url)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }

            if backendManager.activeType == .subsonic {
                subsonicSection
            } else {
                plexSection
            }

            // Playback Cache Settings
            Section(header: Text("Playback Cache")) {
                HStack {
                    Text("Cached Tracks")
                    Spacer()
                    Text("\(cacheManager.getCachedTracksCount()) tracks (\(formatBytes(cacheManager.getCacheSizeInBytes())))")
                        .foregroundColor(.secondary)
                }
                
                Picker("Cache Limit", selection: $selectedCacheLimit) {
                    Text("10 tracks").tag(10)
                    Text("50 tracks").tag(50)
                    Text("100 tracks").tag(100)
                    Text("200 tracks").tag(200)
                    Text("500 tracks").tag(500)
                    Text("Unlimited").tag(999999)
                }
                .onChange(of: selectedCacheLimit) { _, newValue in
                    cacheManager.maxTracks = newValue
                }
                
                Button(role: .destructive, action: {
                    cacheManager.clearCache()
                }) {
                    Label("Clear Playback Cache", systemImage: "trash")
                }
            }

            if let result = testResult {
                Section {
                    HStack {
                        Image(systemName: backendManager.client.isConnected
                              ? "checkmark.circle.fill"
                              : "exclamationmark.triangle.fill")
                            .foregroundColor(backendManager.client.isConnected ? .green : .red)
                        Text(result)
                            .font(.body)
                            .fontWeight(.medium)
                    }
                }
            }
        }
        .navigationTitle("Settings")
        .tint(.red)
        .onAppear {
            discoveryManager.startDiscovery()
            desktopBrowser.start()
        }
        .onDisappear {
            discoveryManager.stopDiscovery()
            desktopBrowser.stop()
        }
    }

    var subsonicSection: some View {
        Section(header: Text("Navidrome / Subsonic Settings")) {
            TextField("Server URL", text: $subsonic.serverURL)
                .keyboardType(.URL)
                .autocapitalization(.none)
                .disableAutocorrection(true)
            
            TextField("Username", text: $subsonic.username)
                .autocapitalization(.none)
                .disableAutocorrection(true)
            
            SecureField("Password", text: $subsonic.password)

            Button(action: {
                subsonic.saveCredentials()
                testConnection()
            }) {
                HStack {
                    Text("Save and Connect")
                        .fontWeight(.semibold)
                    if isTesting {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .foregroundColor(.red)
        }
    }

    var plexSection: some View {
        Section(header: Text("Plex Settings")) {
            TextField("Server URL", text: $plex.serverURL)
                .keyboardType(.URL)
                .autocapitalization(.none)
                .disableAutocorrection(true)
            
            SecureField("Plex Token", text: $plex.token)

            Button(action: {
                plex.saveCredentials()
                testConnection()
            }) {
                HStack {
                    Text("Save and Connect")
                        .fontWeight(.semibold)
                    if isTesting {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .foregroundColor(.red)
        }
    }

    private func selectDiscoveredServer(_ server: DiscoveredServer) {
        backendManager.activeType = server.type
        if server.type == .subsonic {
            subsonic.serverURL = server.url
        } else {
            plex.serverURL = server.url
        }
        testResult = "Selected \(server.name). Fill in credentials and connect."
    }

    private func testConnection() {
        Task {
            await MainActor.run { isTesting = true; testResult = nil }
            do {
                let success = try await backendManager.client.ping()
                await MainActor.run {
                    testResult = success
                        ? "Successfully connected to server!"
                        : "Connection failed. Please check credentials."
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    testResult = "Error: \(error.localizedDescription)"
                    isTesting = false
                }
            }
        }
    }

    private func importFromDesktop(peer: DesktopDiapasonBrowser.DiscoveredPeer) {
        isImporting = true
        importProgress = "Connecting to \(peer.name)..."
        
        Task {
            do {
                guard let url = URL(string: "\(peer.url)/list") else {
                    throw URLError(.badURL)
                }
                
                let (data, _) = try await URLSession.shared.data(from: url)
                
                struct SharedFilesResponse: Codable {
                    struct FileMeta: Codable {
                        let name: String
                        let size: Int64
                    }
                    let files: [FileMeta]
                }
                
                let response = try JSONDecoder().decode(SharedFilesResponse.self, from: data)
                let files = response.files
                
                if files.isEmpty {
                    await MainActor.run {
                        importProgress = "No files found on desktop."
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            self.isImporting = false
                        }
                    }
                    return
                }
                
                for (index, file) in files.enumerated() {
                    await MainActor.run {
                        importProgress = "Downloading \(index + 1) of \(files.count):\n\(file.name)"
                    }
                    
                    guard let fileURL = URL(string: "\(peer.url)/file/\(index)") else { continue }
                    let (tempURL, _) = try await URLSession.shared.download(from: fileURL)
                    
                    _ = await LocalMusicManager.shared.importFile(from: tempURL, filename: file.name)
                }
                
                await MainActor.run {
                    importProgress = "Import complete! \(files.count) files added."
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        self.isImporting = false
                    }
                }
            } catch {
                await MainActor.run {
                    importProgress = "Failed: \(error.localizedDescription)"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        self.isImporting = false
                    }
                }
            }
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
