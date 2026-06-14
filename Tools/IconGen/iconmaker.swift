import AppKit
import CoreGraphics
import Foundation

// medit app-icon generator. Draws a "pencil over lined paper" glyph on a macOS
// squircle, in Core Graphics (no external SVG rasterizer needed). Renders any
// size; a separate driver writes preview PNGs and the full AppIcon set.

struct Palette {
    let name: String
    let bgTop: NSColor
    let bgMid: NSColor?      // optional middle stop for a 3-stop gradient
    let bgBottom: NSColor
    let paper: NSColor
    let paperEdge: NSColor
    let line: NSColor
    let pencilBody: NSColor
    let pencilBodyEdge: NSColor
    let pencilWood: NSColor
    let pencilTip: NSColor
    let ferrule: NSColor
    let eraser: NSColor
}

enum Palettes {
    // 1) gedit green lineage
    static let green = Palette(
        name: "green",
        bgTop: NSColor(srgbRed: 0.36, green: 0.72, blue: 0.42, alpha: 1),
        bgMid: nil,
        bgBottom: NSColor(srgbRed: 0.18, green: 0.52, blue: 0.30, alpha: 1),
        paper: NSColor(srgbRed: 0.98, green: 0.98, blue: 0.96, alpha: 1),
        paperEdge: NSColor(srgbRed: 0.85, green: 0.87, blue: 0.83, alpha: 1),
        line: NSColor(srgbRed: 0.55, green: 0.75, blue: 0.60, alpha: 0.9),
        pencilBody: NSColor(srgbRed: 1.0, green: 0.80, blue: 0.23, alpha: 1),
        pencilBodyEdge: NSColor(srgbRed: 0.90, green: 0.66, blue: 0.12, alpha: 1),
        pencilWood: NSColor(srgbRed: 0.97, green: 0.86, blue: 0.66, alpha: 1),
        pencilTip: NSColor(srgbRed: 0.20, green: 0.20, blue: 0.22, alpha: 1),
        ferrule: NSColor(srgbRed: 0.80, green: 0.83, blue: 0.86, alpha: 1),
        eraser: NSColor(srgbRed: 0.95, green: 0.55, blue: 0.55, alpha: 1)
    )

    // 2) blue — 3-stop: pale #d6e4ef top, vivid #4a9fc8 mid, deep navy #0a2351
    static let blue = Palette(
        name: "blue",
        bgTop: NSColor(srgbRed: 0.839, green: 0.894, blue: 0.937, alpha: 1),   // #d6e4ef
        bgMid: NSColor(srgbRed: 0.290, green: 0.624, blue: 0.784, alpha: 1),   // #4a9fc8
        bgBottom: NSColor(srgbRed: 0.039, green: 0.137, blue: 0.318, alpha: 1),// #0a2351
        paper: NSColor(srgbRed: 0.99, green: 0.99, blue: 1.00, alpha: 1),
        paperEdge: NSColor(srgbRed: 0.82, green: 0.86, blue: 0.92, alpha: 1),
        line: NSColor(srgbRed: 0.62, green: 0.72, blue: 0.92, alpha: 0.9),
        pencilBody: NSColor(srgbRed: 1.0, green: 0.80, blue: 0.23, alpha: 1),
        pencilBodyEdge: NSColor(srgbRed: 0.90, green: 0.66, blue: 0.12, alpha: 1),
        pencilWood: NSColor(srgbRed: 0.97, green: 0.86, blue: 0.66, alpha: 1),
        pencilTip: NSColor(srgbRed: 0.20, green: 0.20, blue: 0.22, alpha: 1),
        ferrule: NSColor(srgbRed: 0.80, green: 0.83, blue: 0.86, alpha: 1),
        eraser: NSColor(srgbRed: 0.95, green: 0.55, blue: 0.55, alpha: 1)
    )

    // 3) warm paper + graphite
    static let graphite = Palette(
        name: "graphite",
        bgTop: NSColor(srgbRed: 0.96, green: 0.93, blue: 0.86, alpha: 1),
        bgMid: nil,
        bgBottom: NSColor(srgbRed: 0.86, green: 0.80, blue: 0.70, alpha: 1),
        paper: NSColor(srgbRed: 0.99, green: 0.98, blue: 0.95, alpha: 1),
        paperEdge: NSColor(srgbRed: 0.80, green: 0.76, blue: 0.69, alpha: 1),
        line: NSColor(srgbRed: 0.70, green: 0.66, blue: 0.58, alpha: 0.9),
        pencilBody: NSColor(srgbRed: 0.36, green: 0.38, blue: 0.42, alpha: 1),
        pencilBodyEdge: NSColor(srgbRed: 0.26, green: 0.28, blue: 0.32, alpha: 1),
        pencilWood: NSColor(srgbRed: 0.90, green: 0.84, blue: 0.74, alpha: 1),
        pencilTip: NSColor(srgbRed: 0.15, green: 0.15, blue: 0.17, alpha: 1),
        ferrule: NSColor(srgbRed: 0.78, green: 0.80, blue: 0.83, alpha: 1),
        eraser: NSColor(srgbRed: 0.88, green: 0.62, blue: 0.55, alpha: 1)
    )

    static func named(_ n: String) -> Palette {
        switch n {
        case "blue": return blue
        case "graphite": return graphite
        default: return green
        }
    }
}

/// A macOS-style squircle (superellipse) path inset into `rect`.
func squirclePath(in rect: CGRect) -> CGPath {
    // Apple's icon shape is close to a superellipse with corner radius ~22.37%
    // of the side. A rounded rect with that ratio is a faithful approximation.
    let radius = rect.width * 0.2237
    return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func drawIcon(size: CGFloat, palette p: Palette, context ctx: CGContext) {
    let full = CGRect(x: 0, y: 0, width: size, height: size)
    ctx.clear(full)

    // macOS icons sit on a ~80% canvas with transparent margin.
    let inset = size * 0.10
    let iconRect = full.insetBy(dx: inset, dy: inset)
    let squircle = squirclePath(in: iconRect)

    // --- Background gradient fill of the squircle ---
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()
    let space = CGColorSpaceCreateDeviceRGB()
    let colorList: [CGColor]
    let locations: [CGFloat]
    if let mid = p.bgMid {
        colorList = [p.bgTop.cgColor, mid.cgColor, p.bgBottom.cgColor]
        locations = [0, 0.5, 1]   // force the mid tone through the exact center
    } else {
        colorList = [p.bgTop.cgColor, p.bgBottom.cgColor]
        locations = [0, 1]
    }
    if let grad = CGGradient(colorsSpace: space, colors: colorList as CFArray, locations: locations) {
        ctx.drawLinearGradient(grad,
                               start: CGPoint(x: iconRect.midX, y: iconRect.maxY),
                               end: CGPoint(x: iconRect.midX, y: iconRect.minY),
                               options: [])
    }
    // Subtle top sheen — only for 2-stop palettes; the 3-stop blue already has
    // a pale top and would wash out.
    if p.bgMid == nil {
        ctx.setFillColor(NSColor(white: 1, alpha: 0.10).cgColor)
        ctx.fill(CGRect(x: iconRect.minX, y: iconRect.midY, width: iconRect.width, height: iconRect.height/2))
    }
    ctx.restoreGState()

    // --- Paper sheet (slightly rotated for life) ---
    let s = iconRect.width
    let paperW = s * 0.52
    let paperH = s * 0.64
    let paperRect = CGRect(x: iconRect.midX - paperW/2 - s*0.03,
                           y: iconRect.midY - paperH/2,
                           width: paperW, height: paperH)

    ctx.saveGState()
    // Rotate around paper center by a few degrees.
    ctx.translateBy(x: paperRect.midX, y: paperRect.midY)
    ctx.rotate(by: -6 * .pi / 180)
    ctx.translateBy(x: -paperRect.midX, y: -paperRect.midY)

    // Drop shadow under the paper.
    ctx.setShadow(offset: CGSize(width: 0, height: -s*0.012), blur: s*0.03,
                  color: NSColor(white: 0, alpha: 0.25).cgColor)
    let paperPath = CGPath(roundedRect: paperRect, cornerWidth: s*0.02, cornerHeight: s*0.02, transform: nil)
    ctx.addPath(paperPath)
    ctx.setFillColor(p.paper.cgColor)
    ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)

    // Paper edge stroke.
    ctx.addPath(paperPath)
    ctx.setStrokeColor(p.paperEdge.cgColor)
    ctx.setLineWidth(max(1, s*0.004))
    ctx.strokePath()

    // Text lines on the paper.
    ctx.saveGState()
    ctx.addPath(paperPath)
    ctx.clip()
    ctx.setStrokeColor(p.line.cgColor)
    let lineCount = 7
    let marginX = paperW * 0.14
    let topPad = paperH * 0.16
    let usableH = paperH * 0.68
    let lineW = max(1.5, s*0.018)
    ctx.setLineWidth(lineW)
    ctx.setLineCap(.round)
    for i in 0..<lineCount {
        let y = paperRect.maxY - topPad - (usableH / CGFloat(lineCount-1)) * CGFloat(i)
        // Last couple of lines shorter, like a paragraph end.
        let shorten: CGFloat = (i == 0) ? 0.42 : (i == lineCount-1 ? 0.25 : 0)
        let x0 = paperRect.minX + marginX
        let x1 = paperRect.maxX - marginX - paperW*shorten
        ctx.move(to: CGPoint(x: x0, y: y))
        ctx.addLine(to: CGPoint(x: x1, y: y))
        ctx.strokePath()
    }
    ctx.restoreGState() // unclip lines
    ctx.restoreGState() // unrotate paper

    // --- Pencil across the sheet (bottom-left to top-right) ---
    drawPencil(in: iconRect, palette: p, context: ctx)

    // --- Final inner rim highlight on the squircle ---
    ctx.addPath(squircle)
    ctx.setStrokeColor(NSColor(white: 1, alpha: 0.18).cgColor)
    ctx.setLineWidth(max(1, size*0.006))
    ctx.strokePath()
}

func drawPencil(in iconRect: CGRect, palette p: Palette, context ctx: CGContext) {
    let s = iconRect.width
    ctx.saveGState()

    // Pencil geometry defined horizontally, then rotated ~ -38 deg and centered.
    let pencilLen = s * 0.82
    let pencilThick = s * 0.135
    let tipLen = pencilThick * 1.15
    let ferruleLen = pencilLen * 0.10
    let eraserLen = pencilLen * 0.07

    ctx.translateBy(x: iconRect.midX + s*0.04, y: iconRect.midY - s*0.02)
    ctx.rotate(by: 40 * .pi / 180)
    ctx.translateBy(x: -pencilLen/2, y: -pencilThick/2)

    // Body (hex barrel as a rounded rect).
    let bodyX = tipLen
    let bodyW = pencilLen - tipLen - ferruleLen - eraserLen
    let bodyRect = CGRect(x: bodyX, y: 0, width: bodyW, height: pencilThick)

    // Pencil drop shadow.
    ctx.setShadow(offset: CGSize(width: s*0.006, height: -s*0.01), blur: s*0.02,
                  color: NSColor(white: 0, alpha: 0.30).cgColor)

    // Barrel gradient (body color, darker at bottom edge for a facet look).
    let barrelPath = CGPath(rect: bodyRect, transform: nil)
    ctx.addPath(barrelPath)
    ctx.setFillColor(p.pencilBody.cgColor)
    ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)

    // Facet shading: darker stripe along the lower third.
    ctx.setFillColor(p.pencilBodyEdge.cgColor)
    ctx.fill(CGRect(x: bodyRect.minX, y: bodyRect.minY, width: bodyRect.width, height: pencilThick*0.32))
    // Light stripe along the top.
    ctx.setFillColor(NSColor(white: 1, alpha: 0.22).cgColor)
    ctx.fill(CGRect(x: bodyRect.minX, y: bodyRect.maxY - pencilThick*0.22, width: bodyRect.width, height: pencilThick*0.22))

    // Wood cone (the sharpened end), pointing left (-x).
    ctx.setFillColor(p.pencilWood.cgColor)
    ctx.beginPath()
    ctx.move(to: CGPoint(x: 0, y: pencilThick/2))                 // tip apex
    ctx.addLine(to: CGPoint(x: tipLen, y: 0))                     // bottom of cone base
    ctx.addLine(to: CGPoint(x: tipLen, y: pencilThick))          // top of cone base
    ctx.closePath()
    ctx.fillPath()

    // Graphite tip — a smaller triangle sharing the wood cone's apex AND slope,
    // so its edges sit flush along the taper. On the cone, the half-height at
    // horizontal position x is (pencilThick/2) * (x / tipLen). We draw the
    // graphite out to x = tipLen*tipFrac using that same ratio.
    let tipFrac: CGFloat = 0.42
    let graphiteBaseX = tipLen * tipFrac
    let graphiteHalf = (pencilThick / 2) * tipFrac   // matches cone slope exactly
    ctx.setFillColor(p.pencilTip.cgColor)
    ctx.beginPath()
    ctx.move(to: CGPoint(x: 0, y: pencilThick/2))
    ctx.addLine(to: CGPoint(x: graphiteBaseX, y: pencilThick/2 - graphiteHalf))
    ctx.addLine(to: CGPoint(x: graphiteBaseX, y: pencilThick/2 + graphiteHalf))
    ctx.closePath()
    ctx.fillPath()

    // Ferrule (metal band).
    let ferruleX = bodyRect.maxX
    ctx.setFillColor(p.ferrule.cgColor)
    ctx.fill(CGRect(x: ferruleX, y: 0, width: ferruleLen, height: pencilThick))
    // Ferrule ridges.
    ctx.setFillColor(NSColor(white: 1, alpha: 0.25).cgColor)
    ctx.fill(CGRect(x: ferruleX + ferruleLen*0.3, y: 0, width: ferruleLen*0.08, height: pencilThick))
    ctx.fill(CGRect(x: ferruleX + ferruleLen*0.6, y: 0, width: ferruleLen*0.08, height: pencilThick))

    // Eraser (rounded cap).
    let eraserX = ferruleX + ferruleLen
    let eraserRect = CGRect(x: eraserX, y: 0, width: eraserLen, height: pencilThick)
    let eraserPath = CGMutablePath()
    eraserPath.move(to: CGPoint(x: eraserRect.minX, y: 0))
    eraserPath.addLine(to: CGPoint(x: eraserRect.minX, y: pencilThick))
    eraserPath.addArc(tangent1End: CGPoint(x: eraserRect.maxX, y: pencilThick),
                      tangent2End: CGPoint(x: eraserRect.maxX, y: pencilThick/2),
                      radius: pencilThick/2)
    eraserPath.addArc(tangent1End: CGPoint(x: eraserRect.maxX, y: 0),
                      tangent2End: CGPoint(x: eraserRect.minX, y: 0),
                      radius: pencilThick/2)
    eraserPath.closeSubpath()
    ctx.addPath(eraserPath)
    ctx.setFillColor(p.eraser.cgColor)
    ctx.fillPath()

    ctx.restoreGState()
}

/// Render a single PNG at `size` for `palette` to `url`.
func renderPNG(size: Int, palette: Palette, to url: URL) {
    let dim = CGFloat(size)
    guard let ctx = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fatalError("no context") }

    // Flip to a top-left origin feels natural, but Core Graphics is bottom-left;
    // our math already uses bottom-left consistently, so no flip needed.
    let nsctx = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = nsctx
    drawIcon(size: dim, palette: palette, context: ctx)
    NSGraphicsContext.restoreGraphicsState()

    guard let image = ctx.makeImage() else { fatalError("no image") }
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: size, height: size)
    guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("no png") }
    try? data.write(to: url)
}

// MARK: - Driver

let args = CommandLine.arguments
// Usage:
//   iconmaker preview <outDir>                 -> 256px PNG per palette
//   iconmaker iconset <paletteName> <outDir>   -> full AppIcon sizes
let mode = args.count > 1 ? args[1] : "preview"

if mode == "preview" {
    let outDir = args.count > 2 ? args[2] : "."
    for pal in [Palettes.green, Palettes.blue, Palettes.graphite] {
        let url = URL(fileURLWithPath: outDir).appendingPathComponent("preview-\(pal.name).png")
        renderPNG(size: 256, palette: pal, to: url)
        print("wrote \(url.path)")
    }
} else if mode == "iconset" {
    let palName = args.count > 2 ? args[2] : "green"
    let outDir = args.count > 3 ? args[3] : "AppIcon.appiconset"
    let pal = Palettes.named(palName)
    try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
    // macOS icon sizes (pt @1x/@2x) -> pixel sizes.
    let sizes = [16, 32, 64, 128, 256, 512, 1024]
    for px in sizes {
        let url = URL(fileURLWithPath: outDir).appendingPathComponent("icon_\(px).png")
        renderPNG(size: px, palette: pal, to: url)
        print("wrote \(url.path)")
    }
} else {
    print("unknown mode \(mode)")
}
