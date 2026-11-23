import SwiftUI
import UIKit

/// Zahlenfelder (`.numberPad`, `.decimalPad`) haben keine Eingabetaste. Einmal zentral: „Fertig“ über der Tastatur
/// und Schließen beim Scrollen, damit die Tastatur nie Knöpfe darunter unerreichbar macht.
/// An Formulare und Listen mit Zahlenfeldern hängen: `.keyboardDoneToolbar()`.
struct KeyboardDoneToolbar: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Fertig") { KeyboardDismiss.now() }.accessibilityIdentifier("keyboardDone")
                }
            }
    }
}

enum KeyboardDismiss {
    @MainActor static func now() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

extension View {
    func keyboardDoneToolbar() -> some View { modifier(KeyboardDoneToolbar()) }
}
