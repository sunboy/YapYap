#!/usr/bin/env swift
// generate_icon.swift — renders the YapYap creature as app icon PNGs
// Run from repo root: swift scripts/generate_icon.swift
import AppKit
import CoreGraphics

// MARK: - Colors (matches DesignTokens.swift)
let ypLavender  = NSColor(red: 0xC4/255.0, green: 0xB8/255.0, blue: 0xE8/255.0, alpha: 1)
let ypWarm      = NSColor(red: 0xF4/255.0, green: 0xA2/255.0, blue: 0x61/255.0, alpha: 1)
let ypZzz       = NSColor(red: 0x8B/255.0, green: 0x8F/255.0, blue: 0xC7/255.0, alpha: 1)
let ypBlush     = NSColor(red: 0xE8/255.0, green: 0xA0/255.0, blue: 0xB4/255.0, alpha: 1)
let ypEyeDark   = NSColor(red: 0x2A/255.0, green: 0x20/255.0, blue: 0x40/255.0, alpha: 1)
let ypEyeStroke = NSColor(red: 0x6B/255.0, green: 0x5E/255.0, blue: 0x8A/255.0, alpha: 1)
let ypBg        = NSColor(red: 0x1A/255.0, green: 0x17/255.0, blue: 0x26/255.0, alpha: 1)

// MARK: - Icon renderer

func renderIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    // Flip coordinate system (AppKit uses bottom-left origin)
    ctx.translateBy(x: 0, y: size)
    ctx.scaleBy(x: 1, y: -1)

    // --- Background: deep purple rounded square ---
    let bgPath = CGPath(roundedRect: CGRect(x: 0, y: 0, width: size, height: size),
                        cornerWidth: size * 0.22, cornerHeight: size * 0.22, transform: nil)
    ctx.setFillColor(ypBg.cgColor)
    ctx.addPath(bgPath)
    ctx.fillPath()

    // Subtle lavender glow overlay in upper-center
    let glowCenter = CGPoint(x: size * 0.5, y: size * 0.38)
    let glowRadius = size * 0.55
    let glowColors = [ypLavender.withAlphaComponent(0.28).cgColor, NSColor.clear.cgColor] as CFArray
    let glowLocs: [CGFloat] = [0, 1]
    if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: glowColors, locations: glowLocs) {
        ctx.drawRadialGradient(gradient,
                               startCenter: glowCenter, startRadius: 0,
                               endCenter: glowCenter, endRadius: glowRadius,
                               options: [])
    }

    // --- Creature: "processing/waking" state ---
    // Canvas coords map 42pt → size, with padding to center
    let padding = size * 0.12
    let canvasSize = size - padding * 2
    let s = canvasSize / 42.0
    let ox = padding  // x offset to center creature
    let oy = padding  // y offset (creature drawn top-down in 42pt space)

    func fill(_ path: CGPath, color: NSColor) {
        ctx.addPath(path)
        ctx.setFillColor(color.cgColor)
        ctx.fillPath()
    }

    func stroke(_ path: CGPath, color: NSColor, lineWidth: CGFloat) {
        ctx.addPath(path)
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(.round)
        ctx.strokePath()
    }

    // Body ellipse — cx=21 cy=30 rx=11 ry=7
    let bodyRect = CGRect(x: ox + (21-11)*s, y: oy + (30-7)*s, width: 22*s, height: 14*s)
    fill(CGPath(ellipseIn: bodyRect, transform: nil), color: ypLavender)

    // Head circle — cx=19 cy=18 r=9
    let headRect = CGRect(x: ox + (19-9)*s, y: oy + (18-9)*s, width: 18*s, height: 18*s)
    fill(CGPath(ellipseIn: headRect, transform: nil), color: ypLavender)

    // Left ear — cx=13 cy=11 rx=2.2 ry=3
    let leftEar = CGRect(x: ox + (13-2.2)*s, y: oy + (11-3)*s, width: 4.4*s, height: 6*s)
    fill(CGPath(ellipseIn: leftEar, transform: nil), color: ypLavender)

    // Right ear — cx=25 cy=11 rx=2.2 ry=3
    let rightEar = CGRect(x: ox + (25-2.2)*s, y: oy + (11-3)*s, width: 4.4*s, height: 6*s)
    fill(CGPath(ellipseIn: rightEar, transform: nil), color: ypLavender)

    // Eyes (processing/waking: eyeY=17.5, slightly raised)
    let eyeY: CGFloat = 17.5
    let hlY: CGFloat = 16.8

    // Left pupil r=2 at (16, eyeY)
    let leftPupil = CGRect(x: ox+(16-2)*s, y: oy+(eyeY-2)*s, width: 4*s, height: 4*s)
    fill(CGPath(ellipseIn: leftPupil, transform: nil), color: ypEyeDark)

    // Right pupil r=2 at (22.5, eyeY)
    let rightPupil = CGRect(x: ox+(22.5-2)*s, y: oy+(eyeY-2)*s, width: 4*s, height: 4*s)
    fill(CGPath(ellipseIn: rightPupil, transform: nil), color: ypEyeDark)

    // Left highlight r=0.7 at (16.5, hlY)
    let leftHL = CGRect(x: ox+(16.5-0.7)*s, y: oy+(hlY-0.7)*s, width: 1.4*s, height: 1.4*s)
    fill(CGPath(ellipseIn: leftHL, transform: nil), color: .white)

    // Right highlight r=0.7 at (23, hlY)
    let rightHL = CGRect(x: ox+(23-0.7)*s, y: oy+(hlY-0.7)*s, width: 1.4*s, height: 1.4*s)
    fill(CGPath(ellipseIn: rightHL, transform: nil), color: .white)

    // Blush cheeks (processing opacity 0.3)
    let leftBlush = CGRect(x: ox+(12.5-2.2)*s, y: oy+(21-1)*s, width: 4.4*s, height: 2*s)
    fill(CGPath(ellipseIn: leftBlush, transform: nil), color: ypBlush.withAlphaComponent(0.3))

    let rightBlush = CGRect(x: ox+(26-2.2)*s, y: oy+(21-1)*s, width: 4.4*s, height: 2*s)
    fill(CGPath(ellipseIn: rightBlush, transform: nil), color: ypBlush.withAlphaComponent(0.3))

    // Hmm mouth (processing): M17.5,21.5 Q19,22.8 20.5,21.5
    let hmm = CGMutablePath()
    hmm.move(to: CGPoint(x: ox+17.5*s, y: oy+21.5*s))
    hmm.addQuadCurve(to: CGPoint(x: ox+20.5*s, y: oy+21.5*s),
                     control: CGPoint(x: ox+19*s, y: oy+22.8*s))
    stroke(hmm, color: ypEyeStroke.withAlphaComponent(0.5), lineWidth: 0.7*s)

    // Three thinking dots (static, centered above head)
    let dotColor = ypZzz
    // dot1 at (8, -10) offset from creature center ≈ (19,18)
    let d1 = CGRect(x: ox+(19+8-1.5)*s, y: oy+(18-10-1.5)*s, width: 3*s, height: 3*s)
    fill(CGPath(ellipseIn: d1, transform: nil), color: dotColor.withAlphaComponent(0.6))

    let d2 = CGRect(x: ox+(19+12-2.2)*s, y: oy+(18-15-2.2)*s, width: 4.4*s, height: 4.4*s)
    fill(CGPath(ellipseIn: d2, transform: nil), color: dotColor.withAlphaComponent(0.75))

    let d3 = CGRect(x: ox+(19+17-3)*s, y: oy+(18-20-3)*s, width: 6*s, height: 6*s)
    fill(CGPath(ellipseIn: d3, transform: nil), color: dotColor.withAlphaComponent(0.9))

    image.unlockFocus()
    return image
}

// MARK: - Save PNG

func savePNG(_ image: NSImage, to path: String) {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        print("❌ Failed to encode PNG for \(path)")
        return
    }
    do {
        try png.write(to: URL(fileURLWithPath: path))
        print("✅ Wrote \(path)")
    } catch {
        print("❌ \(path): \(error)")
    }
}

// MARK: - Main

let outDir = "YapYap/Resources/Assets.xcassets/AppIcon.appiconset"

let sizes: [(size: Int, scale: Int)] = [
    (16, 1), (16, 2),
    (32, 1), (32, 2),
    (128, 1), (128, 2),
    (256, 1), (256, 2),
    (512, 1), (512, 2)
]

for (size, scale) in sizes {
    let px = size * scale
    let filename = scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@2x.png"
    let image = renderIcon(size: CGFloat(px))
    savePNG(image, to: "\(outDir)/\(filename)")
}

print("Done! Icon PNGs written to \(outDir)/")
