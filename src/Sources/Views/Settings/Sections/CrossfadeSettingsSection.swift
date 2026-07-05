// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

struct CrossfadeSettingsSection: View {
    @Environment(\.appContainer) private var container

    var body: some View {
        let cf = container?.crossfadeSettings
        let duration = cf?.duration ?? 0

        Section("Crossfade") {
            let durationBinding = Binding(
                get: { cf?.duration ?? 0 },
                set: { newVal in
                    cf?.duration = newVal
                    Task { await container?.playerService.crossfadeSettingsDidChange() }
                }
            )
            #if os(tvOS)
            // tvOS has no Stepper; use a focusable Picker over the same 0…5 range.
            Picker(selection: durationBinding) {
                ForEach(Array(stride(from: 0.0, through: 5.0, by: 0.5)), id: \.self) { value in
                    Text(crossfadeDurationLabel(value)).tag(value)
                }
            } label: {
                Label("Duration", systemImage: "waveform.and.magnifyingglass")
            }
            #else
            Stepper(
                value: durationBinding,
                in: 0...5,
                step: 0.5
            ) {
                HStack {
                    Label {
                        Text("Duration")
                    } icon: {
                        SettingsIcon(systemImage: "waveform.and.magnifyingglass", color: .teal)
                    }
                    Spacer()
                    Text(crossfadeDurationLabel(duration))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .font(.body.weight(.medium))
                }
            }
            #endif

            if duration > 0 {
                Toggle(isOn: Binding(
                    get: { cf?.disableForGapless ?? true },
                    set: { newVal in
                        cf?.disableForGapless = newVal
                        Task { await container?.playerService.crossfadeSettingsDidChange() }
                    }
                )) {
                    Label {
                        Text("Disable for gapless albums")
                    } icon: {
                        SettingsIcon(systemImage: "music.note.list", color: .teal)
                    }
                }
            }
        }
    }

    private func crossfadeDurationLabel(_ seconds: Double) -> String {
        seconds == 0 ? "Off" : "\(String(format: "%.1f", seconds)) s"
    }
}
