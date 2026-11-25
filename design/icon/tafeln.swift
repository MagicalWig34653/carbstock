// Baut aus den Renderings die Vorschau-Tafel je Entwurf und die Übersicht.
// Aufruf: swift design/icon/tafeln.swift  (nach erzeugen.py)
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let designs = [
    ("a-beutel", "A  Beutel mit Gels"),
    ("b-musette", "B  Musette"),
    ("c-trikottasche", "C  Trikottasche v2"),
    ("d-einzelgel", "D  Einzelnes Gel"),
]

func rgb(_ hex: Int) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: 1)
}

func image(_ path: String) -> NSImage {
    guard let image = NSImage(contentsOf: root.appendingPathComponent(path)) else { fatalError("fehlt: \(path)") }
    return image
}

/// Zeichnet in eine Bitmap, Ursprung oben links.
func sheet(_ width: Int, _ height: Int, to path: String, _ draw: () -> Void) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    context.cgContext.translateBy(x: 0, y: CGFloat(height))
    context.cgContext.scaleBy(x: 1, y: -1)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context.cgContext, flipped: true)
    NSGraphicsContext.current?.imageInterpolation = .high
    draw()
    NSGraphicsContext.current = nil
    try! rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])!.write(to: root.appendingPathComponent(path))
}

func box(_ rect: NSRect, _ color: NSColor, radius: CGFloat = 0) {
    color.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}

func put(_ img: NSImage, _ rect: NSRect) {
    img.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
}

func text(_ string: String, _ x: CGFloat, _ y: CGFloat, size: CGFloat = 22, color: NSColor = rgb(0x1C1C1E),
          bold: Bool = false, center: Bool = false) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular), .foregroundColor: color]
    let s = NSAttributedString(string: string, attributes: attributes)
    s.draw(at: NSPoint(x: center ? x - s.size().width / 2 : x, y: y))
}

/// Homescreen-Ausschnitt mit neutralen Platzhalter-Symbolen (keine fremden Marken).
func homescreen(_ origin: NSPoint, design: String, look: String, wallpaper: (Int, Int), dim: Bool) {
    let frame = NSRect(x: origin.x, y: origin.y, width: 480, height: 600)
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: frame, xRadius: 48, yRadius: 48).addClip()
    NSGradient(starting: rgb(wallpaper.0), ending: rgb(wallpaper.1))!.draw(in: frame, angle: 90)
    let tints = look == "getoent-dunkel"
        ? [0x1D2A3A, 0x1D2A3A, 0x1D2A3A, 0x1D2A3A]
        : dim ? [0x24465C, 0x3A3354, 0x264A38, 0x4A3A2A] : [0x5AA9D6, 0x9C8CD9, 0x6FBF8B, 0xD9B46F]
    for row in 0..<4 {
        for column in 0..<4 {
            let rect = NSRect(x: origin.x + 36 + CGFloat(column) * 108, y: origin.y + 44 + CGFloat(row) * 136,
                              width: 84, height: 84)
            if row == 1 && column == 1 {
                put(image("\(design)/klein/\(look)-180.png"), rect)
                text("CarbStock", rect.midX, rect.maxY + 8, size: 16, color: .white, center: true)
            } else {
                box(rect, rgb(tints[(row + column) % 4]), radius: 20)
                let glyph = NSColor.white.withAlphaComponent(look == "getoent-dunkel" ? 0.25 : 0.7)
                if (row + column) % 2 == 0 { box(rect.insetBy(dx: 24, dy: 24), glyph, radius: 18) }
                else { box(rect.insetBy(dx: 20, dy: 32), glyph, radius: 6) }
                box(NSRect(x: rect.minX + 14, y: rect.maxY + 14, width: 56, height: 7),
                    NSColor.white.withAlphaComponent(0.6), radius: 3.5)
            }
        }
    }
    NSGraphicsContext.restoreGraphicsState()
}

let large = [("hell", "Hell"), ("dunkel", "Dunkel"), ("getoent-hell", "Getönt hell"),
             ("getoent-dunkel", "Getönt dunkel"), ("klar-hell", "Klar")]

for (design, title) in designs {
    sheet(1640, 1500, to: "\(design)/tafel.jpg") {
        box(NSRect(x: 0, y: 0, width: 1640, height: 1500), rgb(0xF2F2F7))
        text(title, 40, 28, size: 40, bold: true)
        for (i, (file, label)) in large.enumerated() {
            let x = 40 + CGFloat(i) * 316
            box(NSRect(x: x, y: 104, width: 296, height: 296),
                file.contains("dunkel") ? rgb(0x101014) : file == "klar-hell" ? rgb(0x8FA3B8) : .white, radius: 24)
            put(image("\(design)/render/\(file).png"), NSRect(x: x + 18, y: 122, width: 260, height: 260))
            text(label, x + 148, 412, center: true)
        }
        text("Kleingrößen in echten Pixeln: 180 · 120 · 87 · 60 · 40", 40, 466, bold: true)
        for (i, (look, label)) in [("hell", "Hell"), ("dunkel", "Dunkel"), ("getoent-dunkel", "Getönt")].enumerated() {
            let x = 40 + CGFloat(i) * 532
            box(NSRect(x: x, y: 508, width: 512, height: 220), look == "hell" ? .white : rgb(0x101014), radius: 24)
            var cursor = x + 16
            for size in [180, 120, 87, 60, 40] {
                put(image("\(design)/klein/\(look)-\(size).png"),
                    NSRect(x: cursor, y: 528 + CGFloat(180 - size), width: CGFloat(size), height: CGFloat(size)))
                cursor += CGFloat(size) + 2
            }
            text(label, x + 256, 736, size: 18, center: true)
        }
        text("Homescreen (Platzhalter-Symbole)", 40, 790, bold: true)
        homescreen(NSPoint(x: 40, y: 834), design: design, look: "hell", wallpaper: (0x7DB7E8, 0x3D6FA5), dim: false)
        homescreen(NSPoint(x: 580, y: 834), design: design, look: "dunkel", wallpaper: (0x1B2233, 0x05070C), dim: true)
        homescreen(NSPoint(x: 1120, y: 834), design: design, look: "getoent-dunkel", wallpaper: (0x101722, 0x030507),
                   dim: true)
        for (i, label) in ["Hell", "Dunkel", "Getönt"].enumerated() {
            text(label, 280 + CGFloat(i) * 540, 1448, size: 18, center: true)
        }
    }
}

sheet(1340, 1420, to: "uebersicht.jpg") {
    box(NSRect(x: 0, y: 0, width: 1340, height: 1420), rgb(0xF2F2F7))
    for (i, label) in ["Hell", "Dunkel", "Getönt dunkel"].enumerated() {
        text(label, 170 + CGFloat(i) * 300, 24, bold: true, center: true)
    }
    text("60 / 40 px", 1120, 24, bold: true, center: true)
    for (row, (design, title)) in designs.enumerated() {
        let y = 70 + CGFloat(row) * 336
        text(title, 40, y, size: 24, bold: true)
        for (i, file) in ["hell", "dunkel", "getoent-dunkel"].enumerated() {
            let x = 40 + CGFloat(i) * 300
            box(NSRect(x: x, y: y + 40, width: 260, height: 260), file == "hell" ? .white : rgb(0x101014), radius: 24)
            put(image("\(design)/render/\(file).png"), NSRect(x: x + 14, y: y + 54, width: 232, height: 232))
        }
        box(NSRect(x: 960, y: y + 40, width: 340, height: 260), .white, radius: 24)
        for (line, look) in ["hell", "dunkel"].enumerated() {
            let top = y + 70 + CGFloat(line) * 120
            put(image("\(design)/klein/\(look)-60.png"), NSRect(x: 1040, y: top, width: 60, height: 60))
            put(image("\(design)/klein/\(look)-40.png"), NSRect(x: 1150, y: top + 20, width: 40, height: 40))
        }
    }
}
print("Tafeln gebaut")
