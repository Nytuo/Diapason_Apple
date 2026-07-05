// Diapason — tvOS settings (trimmed).
// Copyright (C) 2026 Arnaud BEUX
// Licensed under the GNU General Public License v3.0.
// See LICENSE file in the project root for full license information.

#if os(tvOS)
import SwiftUI

/// tvOS settings reuse the shared SettingsView, which already compiles out the
/// blocked sections (iPod, Connect, local import, Last.fm, support links) via
/// `#if !os(tvOS)`.
struct TVSettingsView: View {
    var body: some View {
        SettingsView()
    }
}
#endif
