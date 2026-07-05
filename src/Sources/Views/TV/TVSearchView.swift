// Diapason — tvOS search.
// Copyright (C) 2026 Arnaud BEUX
// Licensed under the GNU General Public License v3.0.
// See LICENSE file in the project root for full license information.

#if os(tvOS)
import SwiftUI

/// tvOS search reuses the shared SearchView (List + shared SearchViewModel) and
/// attaches `.searchable`, which on tvOS presents the system remote keyboard.
struct TVSearchView: View {
    @Binding var searchQuery: String
    @Binding var path: NavigationPath

    var body: some View {
        SearchView(searchQuery: $searchQuery, path: $path)
            .navigationTitle("Search")
            .searchable(text: $searchQuery, prompt: "Artists, albums, songs\u{2026}")
    }
}
#endif
