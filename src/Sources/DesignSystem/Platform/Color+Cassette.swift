// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

extension Color {
    nonisolated static var diapasonSystemBackground: Color {
        #if os(tvOS)
        Color.black
        #elseif canImport(UIKit)
        Color(.systemBackground)
        #else
        Color(.windowBackgroundColor)
        #endif
    }

    /// White — text/icons placed on an accent-filled surface (play button label, picker selection).
    nonisolated static let diapasonAccentText = Color.white

    /// Neutral drop shadow for cover art in light mode; transparent in dark mode (see cassetteCoverStyle).
    nonisolated static let diapasonCoverShadow = Color(red: 0, green: 0, blue: 0, opacity: 0.15)

    /// Thin 1pt border on cover art in dark mode, replacing the invisible shadow.
    nonisolated static let diapasonCoverBorder = Color.white.opacity(0.08)
}
