import CoreGraphics
import Foundation
import ImageIO

// Cuts a flat white background out of a logo.
//
// The source is a dark mark on white with soft edges and a soft neutral shadow,
// plus light *tinted* blue details that are part of the artwork. So whiteness alone
// cannot decide: neutral light pixels are white blends (edges/shadow) and become
// semi-transparent, while tinted pixels are artwork and stay fully opaque.
//
// Soft pixels are un-premultiplied against white, so the mark keeps its true colour
// instead of carrying a white fringe onto dark backgrounds.

let args = CommandLine.arguments
guard args.count == 3 else { print("usage: matte <in> <out.rgba>"); exit(2) }
let inPath = args[1], outPath = args[2]

guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: inPath) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    print("cannot read \(inPath)"); exit(1)
}
let W = image.width, H = image.height, N = W * H
var px = [UInt8](repeating: 0, count: N * 4)
px.withUnsafeMutableBytes { raw in
    let ctx = CGContext(data: raw.baseAddress, width: W, height: H, bitsPerComponent: 8,
                        bytesPerRow: W * 4, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    ctx?.draw(image, in: CGRect(x: 0, y: 0, width: W, height: H))
}

let bgCut: Double = 0.96      // whiteness at/above this is background
let blackPoint: Double = 0.10 // whiteness at/below this is a fully opaque neutral
let tintCut = 10              // channel spread above this counts as coloured artwork

var background = 0, artwork = 0, blend = 0
var minX = W, minY = H, maxX = -1, maxY = -1

for i in 0..<N {
    let r = Double(px[i * 4]), g = Double(px[i * 4 + 1]), b = Double(px[i * 4 + 2])
    let lo = min(r, min(g, b)), hi = max(r, max(g, b))
    let w = lo / 255
    let spread = hi - lo

    var alpha: Double
    if spread > Double(tintCut) {
        // Coloured artwork: opaque, unless it is essentially white.
        alpha = w >= bgCut ? 0 : 1
        if alpha == 0 { background += 1 } else { artwork += 1 }
    } else if w >= bgCut {
        alpha = 0
        background += 1
    } else {
        // Neutral: a blend of white with the mark or its shadow.
        alpha = max(0, min(1, (bgCut - w) / (bgCut - blackPoint)))
        if alpha >= 0.999 { artwork += 1 } else { blend += 1 }
    }

    var or_ = r, og = g, ob = b
    if alpha > 0 && alpha < 0.999 {
        // Un-premultiply the white backdrop: C = a·F + (1-a)·255
        let inv = (1 - alpha) * 255
        or_ = max(0, min(255, (r - inv) / alpha))
        og = max(0, min(255, (g - inv) / alpha))
        ob = max(0, min(255, (b - inv) / alpha))
    }
    px[i * 4] = UInt8(or_.rounded())
    px[i * 4 + 1] = UInt8(og.rounded())
    px[i * 4 + 2] = UInt8(ob.rounded())
    px[i * 4 + 3] = UInt8((alpha * 255).rounded())

    if alpha > 0.02 {
        let x = i % W, y = i / W
        if x < minX { minX = x }
        if x > maxX { maxX = x }
        if y < minY { minY = y }
        if y > maxY { maxY = y }
    }
}

try? Data(bytes: px, count: px.count).write(to: URL(fileURLWithPath: outPath))
let pct = { (n: Int) in String(format: "%.3f%%", Double(n) / Double(N) * 100) }
print("background removed \(background) px (\(pct(background)))")
print("artwork opaque     \(artwork) px (\(pct(artwork)))")
print("soft blend         \(blend) px (\(pct(blend)))")
print("content bbox       x=\(minX)…\(maxX) y=\(minY)…\(maxY)  \(maxX - minX + 1)x\(maxY - minY + 1)")
print("bbox=\(minX),\(minY),\(maxX - minX + 1),\(maxY - minY + 1)")
print("wrote              \(outPath)")
