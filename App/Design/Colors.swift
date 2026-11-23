import SwiftUI

/// Orange mit ausreichendem Kontrast (WCAG AA, mindestens 4,5:1), gemessen in `ContrastTests`.
extension Color {
    /// Hinweis- und Warntext: dunkler Ton auf hellem, heller Ton auf dunklem Grund.
    static let warning = Color("Warning")
    /// Fläche mit weißer Schrift (hervorgehobene Knöpfe, Wischaktionen), in beiden Darstellungen gleich.
    static let actionFill = Color("ActionFill")
}
