import SwiftUI
import UIKit

extension Color {
    static var customSystemGroupedBackground: Color {
        #if os(iOS)
        return Color(uiColor: .systemGroupedBackground)
        #else
        return Color.black
        #endif
    }
    
    static var customSecondarySystemGroupedBackground: Color {
        #if os(iOS)
        return Color(uiColor: .secondarySystemGroupedBackground)
        #else
        return Color.white.opacity(0.08)
        #endif
    }
    
    static var customTertiarySystemGroupedBackground: Color {
        #if os(iOS)
        return Color(uiColor: .tertiarySystemGroupedBackground)
        #else
        return Color.white.opacity(0.15)
        #endif
    }
}

extension View {
    @ViewBuilder
    func customNavigationBarTitleDisplayMode() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
    
    @ViewBuilder
    func customListStyle() -> some View {
        #if os(iOS)
        self.listStyle(.insetGrouped)
        #else
        self.listStyle(.grouped)
        #endif
    }
}

