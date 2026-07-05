// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

struct ServerFormView: View {
    @Bindable var viewModel: OnboardingViewModel

    /// The Local backend imports on-device audio files via a document picker, which
    /// tvOS has no equivalent for — so it is not offered there.
    private var availableBackends: [OnboardingViewModel.Backend] {
        #if os(tvOS)
        OnboardingViewModel.Backend.allCases.filter { $0 != .local }
        #else
        OnboardingViewModel.Backend.allCases
        #endif
    }

    var body: some View {
        Form {
            Section("Backend") {
                Picker("Backend", selection: $viewModel.backend) {
                    ForEach(availableBackends) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
            }

            if viewModel.backend == .local {
                Section {
                    Label("Add a local library, then import audio files from the Files app.", systemImage: "folder")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Server") {
                    TextField(viewModel.backend == .plex ? "https://plex.example.com:32400" : "https://music.example.com", text: $viewModel.serverURL)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        #endif
                    invalidURLHint
                    httpWarning
                }

                if viewModel.backend == .plex {
                    Section("Plex Token") {
                        SecureField("X-Plex-Token", text: $viewModel.password)
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                    }
                } else {
                    Section("Credentials") {
                        TextField("Username", text: $viewModel.username)
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                        SecureField("Password", text: $viewModel.password)
                    }
                }
            }

            errorSection

            if viewModel.backend == .subsonic {
                customHeadersSection
            }

            Section {
                Button {
                    Task { await viewModel.addServer() }
                } label: {
                    if viewModel.isLoading {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Connecting…")
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        Text(viewModel.backend == .local ? "Add Local Library" : "Connect & Save")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(viewModel.isLoading || !viewModel.canSubmit)
            }
        }
        .navigationTitle("Add Server")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Error / warning helpers

    @ViewBuilder
    private var httpWarning: some View {
        if viewModel.isHTTP {
            Label("Unencrypted connection — make sure you are on a trusted network.", systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var invalidURLHint: some View {
        if case .invalidURL = viewModel.connectionError {
            Text("Enter a valid URL, including http:// or https://")
                .font(.footnote)
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var errorSection: some View {
        if let error = viewModel.connectionError, error != .invalidURL {
            Section {
                ConnectionErrorView(error: error)
                    .padding(.vertical, CassetteSpacing.xs)
            }
        }
    }

    private var customHeadersSection: some View {
        Section {
            PlatformDisclosureGroup {
                ForEach($viewModel.customHeaders) { $header in
                    CustomHeaderRowView(
                        key: $header.key,
                        value: $header.value,
                        onRemove: { viewModel.removeCustomHeader(id: header.id) }
                    )
                }
                Button(action: viewModel.addCustomHeader) {
                    Label("Add Header", systemImage: "plus")
                }
            } label: {
                Text("Custom Headers")
            }
        } footer: {
            Text("Optional headers sent with every request — useful for Cloudflare Access or other reverse-proxy authentication.")
                .font(.footnote)
        }
    }

}

// MARK: - CustomHeaderRowView

struct CustomHeaderRowView: View {
    @Binding var key: String
    @Binding var value: String
    let onRemove: () -> Void

    @State private var isRevealed: Bool = false
    @State private var justCopied: Bool = false
    @State private var copyFeedbackTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Header name")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("e.g. CF-Access-Client-Id", text: $key)
                .roundedBorderTextFieldStyleCompat()
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif

            Text("Value")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, CassetteSpacing.xs)
            HStack(spacing: 0) {
                valueField
                    .roundedBorderTextFieldStyleCompat()
                    .autocorrectionDisabled()
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    isRevealed.toggle()
                } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                        .foregroundStyle(isRevealed ? CassetteColors.accent : CassetteColors.textTertiary)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.15), value: isRevealed)

                Button {
                    copyValueToClipboard()
                } label: {
                    Image(systemName: justCopied ? "checkmark" : "doc.on.doc")
                        .foregroundStyle(value.isEmpty ? CassetteColors.textTertiary : CassetteColors.accent)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .disabled(value.isEmpty)
                .animation(.easeInOut(duration: 0.15), value: justCopied)

                Button(role: .destructive) {
                    onRemove()
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.red)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
            }

            if !key.isEmpty && !HeaderValidator.isValidName(key) {
                Text("Name '\(key)' contains characters not allowed by RFC 7230.")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            if !value.isEmpty && !HeaderValidator.isValidValue(value) {
                Text("Value contains CR, LF, or NUL — not allowed in HTTP headers.")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .labelsHidden()
        .padding(.vertical, CassetteSpacing.xs)
        .onDisappear {
            isRevealed = false
            copyFeedbackTask?.cancel()
        }
    }

    @ViewBuilder
    private var valueField: some View {
        if isRevealed {
            TextField("Value", text: $value)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
        } else {
            SecureField("Value", text: $value)
        }
    }

    private func copyValueToClipboard() {
        PlatformPasteboard.copy(value)
        copyFeedbackTask?.cancel()
        justCopied = true
        copyFeedbackTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            justCopied = false
        }
    }
}
