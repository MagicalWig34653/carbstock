import Testing
import UIKit
@testable import CarbStock

/// WCAG 2.x: Text braucht mindestens 4,5:1 (AA). Gemessen wird mit den echten Farben des Asset-Katalogs,
/// aufgelöst für hell und dunkel, gegen die Hintergründe, auf denen die App Text zeigt.
@Suite struct ContrastTests {
    private static let aa = 4.5

    private func color(_ name: String, _ style: UIUserInterfaceStyle) throws -> UIColor {
        let c = try #require(UIColor(named: name, in: Bundle(for: TrainingService.self), compatibleWith: nil), "Farbe \(name) fehlt")
        return c.resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
    }

    private func luminance(_ c: UIColor) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        func lin(_ v: CGFloat) -> Double { let v = Double(v); return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    func ratio(_ a: UIColor, _ b: UIColor) -> Double {
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    private func rgb(_ r: Int, _ g: Int, _ b: Int) -> UIColor { UIColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1) }

    // Hintergründe der Systemlisten: Zelle weiß bzw. Gruppenfläche F2F2F7 (hell); schwarz, Zelle 1C1C1E, erhöht 2C2C2E (dunkel).
    private let lightBackgrounds = [("weiß", UIColor.white), ("Gruppenfläche", UIColor(red: 242 / 255, green: 242 / 255, blue: 247 / 255, alpha: 1))]
    private var darkBackgrounds: [(String, UIColor)] {
        [("schwarz", .black), ("Zelle", rgb(28, 28, 30)), ("erhöht", rgb(44, 44, 46))]
    }

    @Test(arguments: ["AccentColor", "Warning"])
    func orangeTextMeetsAAOnLightBackgrounds(name: String) throws {
        let c = try color(name, .light)
        for (n, bg) in lightBackgrounds { #expect(ratio(c, bg) >= Self.aa, "\(name) hell auf \(n): \(ratio(c, bg))") }
    }

    @Test(arguments: ["AccentColor", "Warning"])
    func orangeTextMeetsAAOnDarkBackgrounds(name: String) throws {
        let c = try color(name, .dark)
        for (n, bg) in darkBackgrounds { #expect(ratio(c, bg) >= Self.aa, "\(name) dunkel auf \(n): \(ratio(c, bg))") }
    }

    /// Weiße Schrift auf orangener Fläche (hervorgehobene Knöpfe, Wischaktionen) in beiden Darstellungen.
    @Test func whiteLabelOnOrangeFillMeetsAA() throws {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let c = try color("ActionFill", style)
            #expect(ratio(.white, c) >= Self.aa, "ActionFill \(style.rawValue): \(ratio(.white, c))")
        }
    }
}
