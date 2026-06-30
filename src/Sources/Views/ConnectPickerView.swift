import SwiftUI

struct ConnectPickerView: View {
    @ObservedObject var connectManager: ConnectManager
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            List {
                // Device I'm controlling
                if let connected = connectManager.connectedDevice {
                    Section(NSLocalizedString("connect.connected", comment: "")) {
                        VStack(alignment: .leading, spacing: 6) {
                            Label(connected.name, systemImage: deviceSystemImage(connected.name))
                                .font(.headline)
                            if let status = connectManager.remoteStatus {
                                if let song = status.song {
                                    Text("\(song.title) — \(song.artist)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Text(status.state.capitalized)
                                    .font(.caption2)
                                    .foregroundColor(status.state == "playing" ? .accentColor : .secondary)
                            }
                        }
                        .padding(.vertical, 4)

                        if connectManager.remoteStatus != nil {
                            HStack(spacing: 24) {
                                Spacer()
                                Button { connectManager.sendCommand("prev") } label: {
                                    Image(systemName: "backward.fill").font(.title2)
                                }
                                Button {
                                    let action = connectManager.remoteStatus?.state == "playing" ? "pause" : "play"
                                    connectManager.sendCommand(action)
                                } label: {
                                    Image(systemName: connectManager.remoteStatus?.state == "playing" ? "pause.fill" : "play.fill")
                                        .font(.title)
                                }
                                Button { connectManager.sendCommand("next") } label: {
                                    Image(systemName: "forward.fill").font(.title2)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 8)
                        }

                        Button(role: .destructive) {
                            connectManager.disconnect()
                        } label: {
                            Label(NSLocalizedString("connect.disconnect", comment: ""), systemImage: "xmark.circle")
                        }
                    }
                }

                // Devices controlling me (they registered with us)
                if !connectManager.registeredDevices.isEmpty {
                    Section(NSLocalizedString("connect.controllingFrom", comment: "")) {
                        ForEach(connectManager.registeredDevices) { device in
                            let status = connectManager.registeredStatuses[device.baseURL]
                            VStack(alignment: .leading, spacing: 4) {
                                Label(device.name, systemImage: deviceSystemImage(device.name))
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                if let s = status {
                                    if let song = s.song {
                                        Text("\(song.title) — \(song.artist)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Text(s.state.capitalized)
                                        .font(.caption2)
                                        .foregroundColor(s.state == "playing" ? .accentColor : .secondary)
                                }
                            }
                            .padding(.vertical, 2)

                            if status != nil {
                                HStack(spacing: 20) {
                                    Spacer()
                                    Button {
                                        connectManager.sendCommandTo(device, action: "prev")
                                    } label: {
                                        Image(systemName: "backward.fill").font(.title3)
                                    }
                                    Button {
                                        let action = status?.state == "playing" ? "pause" : "play"
                                        connectManager.sendCommandTo(device, action: action)
                                    } label: {
                                        Image(systemName: status?.state == "playing" ? "pause.fill" : "play.fill")
                                            .font(.title2)
                                    }
                                    Button {
                                        connectManager.sendCommandTo(device, action: "next")
                                    } label: {
                                        Image(systemName: "forward.fill").font(.title3)
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }

                // Available devices to connect to
                Section(NSLocalizedString("connect.availableDevices", comment: "")) {
                    if connectManager.isScanning {
                        HStack {
                            ProgressView().padding(.trailing, 8)
                            Text(NSLocalizedString("connect.searching", comment: ""))
                                .foregroundColor(.secondary)
                        }
                    } else if connectManager.discoveredDevices.isEmpty {
                        Text(NSLocalizedString("connect.noDevices", comment: ""))
                            .foregroundColor(.secondary)
                            .font(.callout)
                    } else {
                        ForEach(connectManager.discoveredDevices) { device in
                            HStack {
                                Label(device.name, systemImage: deviceSystemImage(device.name))
                                Spacer()
                                if connectManager.connectedDevice == device {
                                    Image(systemName: "checkmark.circle.fill").foregroundColor(.accentColor)
                                } else {
                                    Button(NSLocalizedString("connect.connect", comment: "")) {
                                        connectManager.connect(to: device)
                                        dismiss()
                                    }
                                    .buttonStyle(.borderless)
                                    .foregroundColor(.accentColor)
                                }
                            }
                        }
                    }

                    Button {
                        connectManager.startDiscovery()
                    } label: {
                        Label(
                            connectManager.isScanning
                                ? NSLocalizedString("connect.scanning", comment: "")
                                : NSLocalizedString("connect.scanNetwork", comment: ""),
                            systemImage: "arrow.clockwise"
                        )
                        .foregroundColor(.accentColor)
                    }
                    .disabled(connectManager.isScanning)
                }
            }
            .navigationTitle(NSLocalizedString("connect.title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("connect.done", comment: "")) { dismiss() }
                }
            }
        }
        .onAppear { connectManager.startDiscovery() }
    }

    private func deviceSystemImage(_ name: String) -> String {
        if name.localizedCaseInsensitiveContains("android") || name.localizedCaseInsensitiveContains("ios") {
            return "iphone"
        }
        return "laptopcomputer"
    }
}
