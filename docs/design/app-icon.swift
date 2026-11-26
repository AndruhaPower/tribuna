// Генератор иконки Tribuna (D42): swift docs/design/app-icon.swift Tribuna/Resources/Fonts/Unbounded.ttf Tribuna/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
import AppKit
import CoreText

// Иконка Tribuna: «Т» Unbounded на тёмно-синем и оранжевый мяч (акцент и точка логотипа).
let size: CGFloat = 1024
let args = CommandLine.arguments
let fontURL = URL(fileURLWithPath: args[1]), out = URL(fileURLWithPath: args[2])
func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
// Фон: сверху surfaceRaised, снизу background приложения.
let gradient = CGGradient(colorsSpace: nil, colors: [color(0x22305A), color(0x0B1020)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: [])

// «Т» — Unbounded, ось wght 800.
let descriptors = CTFontManagerCreateFontDescriptorsFromURL(fontURL as CFURL) as! [CTFontDescriptor]
let wght: UInt32 = 0x77676874
let variation = CTFontDescriptorCreateCopyWithAttributes(descriptors[0], [kCTFontVariationAttribute: [wght: 800]] as CFDictionary)
let font = CTFontCreateWithFontDescriptor(variation, 700, nil)
var glyph: CGGlyph = 0
var char: UniChar = 0x0422 // Т
CTFontGetGlyphsForCharacters(font, &char, &glyph, 1)
let path = CTFontCreatePathForGlyph(font, glyph, nil)!
let box = path.boundingBox
let tX = (size - box.width) / 2 - box.minX - 40, tY: CGFloat = 230 - box.minY
ctx.saveGState()
ctx.translateBy(x: tX, y: tY)
ctx.addPath(path)
ctx.setFillColor(color(0xEEF1F8))
ctx.fillPath()
ctx.restoreGState()

// Мяч справа у ножки «Т».
let center = CGPoint(x: 690, y: 330), R: CGFloat = 150
func pentagon(_ c: CGPoint, _ r: CGFloat, _ rotation: CGFloat) -> CGPath {
    let p = CGMutablePath()
    for i in 0..<5 {
        let a = rotation + CGFloat(i) * 2 * .pi / 5
        let pt = CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
    }
    p.closeSubpath()
    return p
}
// Тень мяча.
ctx.setFillColor(color(0x000000, 0.35))
ctx.fillEllipse(in: CGRect(x: center.x - R * 0.9, y: center.y - R - 34, width: R * 1.8, height: 36))
ctx.setFillColor(color(0x0B1020))
ctx.fillEllipse(in: CGRect(x: center.x - R - 14, y: center.y - R - 14, width: 2 * R + 28, height: 2 * R + 28))
ctx.setFillColor(color(0xFFB020))
ctx.fillEllipse(in: CGRect(x: center.x - R, y: center.y - R, width: 2 * R, height: 2 * R))
ctx.saveGState()
ctx.addEllipse(in: CGRect(x: center.x - R, y: center.y - R, width: 2 * R, height: 2 * R))
ctx.clip()
let up = CGFloat.pi / 2
let r = R * 0.36
ctx.setFillColor(color(0x0B1020))
ctx.addPath(pentagon(center, r, up)); ctx.fillPath()
ctx.setStrokeColor(color(0x0B1020))
ctx.setLineWidth(R * 0.07)
ctx.setLineCap(.round)
for i in 0..<5 {
    let a = up + CGFloat(i) * 2 * .pi / 5
    let from = CGPoint(x: center.x + r * cos(a), y: center.y + r * sin(a))
    let outer = CGPoint(x: center.x + R * 1.08 * cos(a), y: center.y + R * 1.08 * sin(a))
    ctx.move(to: from); ctx.addLine(to: CGPoint(x: center.x + R * 0.72 * cos(a), y: center.y + R * 0.72 * sin(a))); ctx.strokePath()
    ctx.addPath(pentagon(outer, r * 0.95, a + .pi)); ctx.fillPath()
}
ctx.restoreGState()

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: out)
