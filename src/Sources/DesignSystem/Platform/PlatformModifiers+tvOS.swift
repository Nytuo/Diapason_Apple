// Diapason — cross-platform modifier shims for tvOS.
// Copyright (C) 2026 Arnaud BEUX
// Licensed under the GNU General Public License v3.0.
// See LICENSE file in the project root for full license information.
//
// tvOS lacks several touch-oriented SwiftUI modifiers (pull-to-refresh,
// swipe actions, presentation detents). These helpers apply them on the
// platforms that support them and no-op on tvOS, so shared views compile
// unchanged across iOS / macOS / tvOS.

import SwiftUI

extension View {
    /// `.refreshable` on platforms that support pull-to-refresh; no-op on tvOS.
    @ViewBuilder
    func refreshableCompat(_ action: @escaping @Sendable () async -> Void) -> some View {
        #if os(tvOS)
        self
        #else
        self.refreshable(action: action)
        #endif
    }

    /// `.listRowSeparator` is unavailable on tvOS (which has no row separators); no-op there.
    @ViewBuilder
    func listRowSeparatorCompat(_ visibility: Visibility) -> some View {
        #if os(tvOS)
        self
        #else
        self.listRowSeparator(visibility)
        #endif
    }

    /// `.scrollContentBackground` is unavailable on tvOS; no-op there.
    @ViewBuilder
    func scrollContentBackgroundCompat(_ visibility: Visibility) -> some View {
        #if os(tvOS)
        self
        #else
        self.scrollContentBackground(visibility)
        #endif
    }

    /// `.roundedBorder` text-field style is unavailable on tvOS; use the plain style there.
    @ViewBuilder
    func roundedBorderTextFieldStyleCompat() -> some View {
        #if os(tvOS)
        self.textFieldStyle(.plain)
        #else
        self.textFieldStyle(.roundedBorder)
        #endif
    }
}

/// `DisclosureGroup` is unavailable on tvOS. This wrapper uses it where supported
/// and falls back to an always-expanded label + content stack on tvOS.
struct PlatformDisclosureGroup<Content: View, Label: View>: View {
    @ViewBuilder var content: () -> Content
    @ViewBuilder var label: () -> Label

    var body: some View {
        #if os(tvOS)
        VStack(alignment: .leading, spacing: 8) {
            label()
            content()
        }
        #else
        DisclosureGroup(content: content, label: label)
        #endif
    }
}
