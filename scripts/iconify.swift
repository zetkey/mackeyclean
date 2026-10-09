import CoreGraphics
import Foundation
import ImageIO

// Turns a transparent logo into a macOS app-icon master.
//
//   1. trims to the artwork's opaque content
//   2. scales it to fit the canvas exactly (never cropped)
//   3. fills the remaining canvas by propagating the nearest edge colour outwards, so
//      gradients in the artwork continue into the corners instead of meeting a flat fill
//   4. masks the result to the macOS icon shape (squircle)
//
// Step 4 is what makes macOS draw the icon as-is: an icon whose opaque silhouette is not
// the system icon shape gets composited onto the system's light plate.
//
// usage: iconify <in.png> <out.png> <canvas> <radius-ratio>

let args = CommandLine.arguments
guard args.count == 5 else { print("usage: iconify <in.png> <out.png> <canvas> <radius-ratio>"); exit(2) }
let inPath = args[1], outPath = args[2]
guard let canvas = Int(args[3]), let radiusRatio = Double(args[4]), canvas > 0 else {
    print("bad canvas/radius"); exit(2)
}

guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: inPath) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
    print("cannot read \(inPath)"); exit(1)
}
let W0 = image.width, H0 = image.height, N0 = W0 * H0
var srcPx = [UInt8](repeating: 0, count: N0 * 4)
srcPx.withUnsafeMutableBytes { raw in
    let ctx = CGContext(data: raw.baseAddress, width: W0, height: H0, bitsPerComponent: 8,
                        bytesPerRow: W0 * 4, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    ctx?.draw(image, in: CGRect(x: 0, y: 0, width: W0, height: H0))
}

// 1. content box
var minX = W0, minY = H0, maxX = -1, maxY = -1
for y in 0..<H0 {
    for x in 0..<W0 where srcPx[(y * W0 + x) * 4 + 3] > 8 {
        if x < minX { minX = x }
        if x > maxX { maxX = x }
        if y < minY { minY = y }
        if y > maxY { maxY = y }
    }
}
guard maxX >= minX, maxY >= minY else { print("source is fully transparent"); exit(1) }
let bw = maxX - minX + 1, bh = maxY - minY + 1

// 2. scale to fit the canvas without cropping, then centre
let scale = min(Double(canvas) / Double(bw), Double(canvas) / Double(bh))
let dw = Double(bw) * scale, dh = Double(bh) * scale
let ox = (Double(canvas) - dw) / 2, oy = (Double(canvas) - dh) / 2

let N = canvas * canvas
var px = [UInt8](repeating: 0, count: N * 4)
px.withUnsafeMutableBytes { raw in
    let ctx = CGContext(data: raw.baseAddress, width: canvas, height: canvas, bitsPerComponent: 8,
                        bytesPerRow: canvas * 4, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    ctx?.interpolationQuality = .high
    // cropping uses top-left image coordinates; the target rect is centred, so the
    // bottom-left drawing origin lands on the same place.
    if let content = image.cropping(to: CGRect(x: minX, y: minY, width: bw, height: bh)) {
        ctx?.draw(content, in: CGRect(x: ox, y: oy, width: dw, height: dh))
    }
}

// 3. propagate the nearest edge colour into the transparent remainder.
// Only fully transparent pixels are filled: semi-transparent artwork (soft edges, a
// shadow) keeps its own colour and alpha.
let visible = 8
var queue = [Int32]()
queue.reserveCapacity(N / 8)
for y in 1..<(canvas - 1) {
    for x in 1..<(canvas - 1) {
        let i = y * canvas + x
        guard px[i * 4 + 3] > visible else { continue }
        if px[(i - 1) * 4 + 3] <= visible || px[(i + 1) * 4 + 3] <= visible
            || px[(i - canvas) * 4 + 3] <= visible || px[(i + canvas) * 4 + 3] <= visible {
            queue.append(Int32(i))
        }
    }
}
var head = 0
while head < queue.count {
    let i = Int(queue[head]); head += 1
    let x = i % canvas, y = i / canvas
    let r = px[i * 4], g = px[i * 4 + 1], b = px[i * 4 + 2]
    for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)] {
        guard nx >= 0, ny >= 0, nx < canvas, ny < canvas else { continue }
        let j = ny * canvas + nx
        guard px[j * 4 + 3] <= visible else { continue }
        px[j * 4] = r
        px[j * 4 + 1] = g
        px[j * 4 + 2] = b
        px[j * 4 + 3] = 255
        queue.append(Int32(j))
    }
}

// 4. mask to the icon shape
let radius = radiusRatio * Double(canvas)
let r2 = radius * radius
var shapePixels = 0
for y in 0..<canvas {
    for x in 0..<canvas {
        let i = y * canvas + x
        // distance outside the rounded rectangle
        let cx = min(max(Double(x) + 0.5, radius), Double(canvas) - radius)
        let cy = min(max(Double(y) + 0.5, radius), Double(canvas) - radius)
        let dx = Double(x) + 0.5 - cx, dy = Double(y) + 0.5 - cy
        let dist = (dx * dx + dy * dy).squareRoot()
        // 1 px feather keeps the shape's edge smooth when downscaled
        let cov = max(0, min(1, radius + 0.5 - dist))
        // The icon shape is solid: any alpha inside it would leave a hole for the
        // system plate to show through. Only the shape's own edge is feathered.
        px[i * 4 + 3] = UInt8((255 * cov).rounded())
        if cov > 0.5 { shapePixels += 1 }
    }
}

try? Data(bytes: px, count: px.count).write(to: URL(fileURLWithPath: outPath))
let expected = 1 - (4 - Double.pi) * radiusRatio * radiusRatio
print("source        \(W0)x\(H0)  content \(bw)x\(bh)  scale=\(String(format: "%.4f", scale))")
print(String(format: "placement     x=%.1f y=%.1f  %.1fx%.1f", ox, oy, dw, dh))
print(String(format: "silhouette    %.4f of canvas (icon shape is %.4f)",
             Double(shapePixels) / Double(N), expected))
if abs(Double(shapePixels) / Double(N) - expected) > 0.01 {
    print("WARNING: silhouette is not the icon shape; macOS will add its own plate")
}
print("wrote         \(outPath)")
