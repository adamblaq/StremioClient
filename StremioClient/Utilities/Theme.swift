import SwiftUI

enum Theme {
    static let background = Color(red: 0.07, green: 0.07, blue: 0.09)
    static let surface = Color(red: 0.13, green: 0.13, blue: 0.16)
    static let accent = Color(red: 0.54, green: 0.37, blue: 0.75)   // Stremio purple
    static let textPrimary = Color.white
    static let textSecondary = Color(white: 0.65)
    static let cardWidth: CGFloat = 130
    static let cardHeight: CGFloat = 195
}

extension View {
    func stremioBackground() -> some View {
        self.background(Theme.background.ignoresSafeArea())
    }
}
