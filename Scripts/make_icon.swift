import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Generates the Pushed app icon: a 5x5 GitHub-style contribution grid with
// intensity building toward the bottom-right square ("today"), which glows.
//
// Usage: swift Scripts/make_icon.swift <light|dark|tinted> <output.png>
//
// - light:  GitHub light-mode palette on white (default home screens)
// - dark:   GitHub dark-mode palette on #0d1117 (dark home screens)
// - tinted: grayscale on transparent — iOS 18 recolors it with the user's tint

let variant = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dark"
let outPath = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "icon-\(variant).png"

let size = 1024

// Only the tinted variant is allowed an alpha channel — iOS composites it over
// its own gradient. The App Store icon must be fully opaque, and a light/dark
// PNG that merely *looks* opaque still trips ITMS-90717 if it carries an alpha
// channel at all, so those two are rendered without one rather than painted
// over a background and left translucent-capable.
let ctx = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: (variant == "tinted"
        ? CGImageAlphaInfo.premultipliedLast
        : CGImageAlphaInfo.noneSkipLast).rawValue
)!

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

// Per-variant styling
let background: UInt32?   // nil = transparent
let palette: [UInt32]     // level 0-4
let glowColor: UInt32
let glowAlpha: CGFloat

switch variant {
case "light":
    background = 0xFFFFFF
    palette = [0xEBEDF0, 0x9BE9A8, 0x40C463, 0x30A14E, 0x216E39]
    glowColor = 0x26A641
    glowAlpha = 0.5
case "tinted":
    // Grayscale only: iOS lays this over its own gradient and applies the
    // user's tint. White = brightest after tinting.
    background = nil
    palette = [0x3D3D3D, 0x6B6B6B, 0x999999, 0xC7C7C7, 0xFFFFFF]
    glowColor = 0xFFFFFF
    glowAlpha = 0.6
default: // dark
    background = 0x0D1117
    palette = [0x161B22, 0x0E4429, 0x006D32, 0x26A641, 0x39D353]
    glowColor = 0x39D353
    glowAlpha = 0.85
}

if let background {
    ctx.setFillColor(color(background))
    ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

    // subtle radial lift toward the "today" corner
    let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        colors: [color(glowColor, alpha: 0.10), color(background, alpha: 0.0)] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawRadialGradient(
        gradient,
        startCenter: CGPoint(x: 760, y: 264), startRadius: 0,
        endCenter: CGPoint(x: 760, y: 264), endRadius: 700,
        options: []
    )
}

// 5x5 levels, row 0 = top. Builds toward bottom-right = today.
let levels: [[Int]] = [
    [0, 1, 0, 2, 1],
    [1, 0, 2, 1, 2],
    [0, 2, 1, 3, 3],
    [2, 1, 3, 4, 3],
    [1, 2, 3, 3, 4],
]

let cell: CGFloat = 148
let gap: CGFloat = 34
let gridSide = 5 * cell + 4 * gap
let origin = (CGFloat(size) - gridSide) / 2
let radius: CGFloat = 30

for (row, cols) in levels.enumerated() {
    for (col, level) in cols.enumerated() {
        let x = origin + CGFloat(col) * (cell + gap)
        // CoreGraphics origin is bottom-left; flip rows so row 0 is on top
        let y = origin + CGFloat(4 - row) * (cell + gap)
        let rect = CGRect(x: x, y: y, width: cell, height: cell)
        let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

        // glow behind the brightest "today" square (bottom-right)
        if row == 4 && col == 4 {
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: 90, color: color(glowColor, alpha: glowAlpha))
            ctx.addPath(path)
            ctx.setFillColor(color(palette[level]))
            ctx.fillPath()
            ctx.restoreGState()
        }

        ctx.addPath(path)
        ctx.setFillColor(color(palette[level]))
        ctx.fillPath()
    }
}

let image = ctx.makeImage()!
let outURL = URL(fileURLWithPath: outPath)
let dest = CGImageDestinationCreateWithURL(outURL as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("wrote \(outURL.path)")
