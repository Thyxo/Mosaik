// Målbilledet (forudsigelsen) -> farver til mosaikkens felter.
import UIKit
import Vision

enum TargetMaker {
    /// Farver for et gitter på cols × rows felter, 4 delfarver pr. felt (række for række).
    static func grid(from image: CGImage, cols: Int, rows: Int, faceCrop: Bool, contrast: Float) -> [Lab] {
        let W = CGFloat(image.width), H = CGFloat(image.height)
        let aspect = CGFloat(cols) / CGFloat(rows)
        let face = faceCrop ? faceRect(image) : nil
        let crop = cropRect(size: CGSize(width: W, height: H), face: face, aspect: aspect)
        let src = image.cropping(to: crop.integral) ?? image

        let w = cols * 2, h = rows * 2
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
        ctx.setFillColor(UIColor.black.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.interpolationQuality = .high
        ctx.draw(src, in: CGRect(x: 0, y: 0, width: w, height: h))

        var out: [Lab] = []
        out.reserveCapacity(cols * rows * 4)
        for r in 0..<rows {
            for c in 0..<cols {
                for (dy, dx) in [(0, 0), (0, 1), (1, 0), (1, 1)] {
                    let i = ((r * 2 + dy) * w + (c * 2 + dx)) * 4
                    var lab = ColorMath.lab(Float(px[i]) / 255, Float(px[i + 1]) / 255, Float(px[i + 2]) / 255)
                    if contrast != 1 {
                        lab.l = min(100, max(0, 50 + (lab.l - 50) * contrast))
                        lab.a *= contrast; lab.b *= contrast
                    }
                    out.append(lab)
                }
            }
        }
        return out
    }

    /// Udsnit med gitterets format. Med et ansigt: ansigtet fylder ca. 62 % af bredden og står lidt over midten.
    static func cropRect(size: CGSize, face: CGRect?, aspect: CGFloat) -> CGRect {
        let W = size.width, H = size.height
        var cw: CGFloat, ch: CGFloat
        if let f = face { cw = f.width / 0.62 } else { cw = W }
        ch = cw / aspect
        if ch > H { ch = H; cw = ch * aspect }
        if cw > W { cw = W; ch = cw / aspect }
        let cx = face?.midX ?? W / 2
        let top = face.map { $0.midY - ch * 0.42 } ?? (H - ch) * 0.4
        let x = min(max(0, cx - cw / 2), W - cw)
        let y = min(max(0, top), H - ch)
        return CGRect(x: x, y: y, width: cw, height: ch)
    }

    /// Største ansigt i pixel-koordinater (origo øverst til venstre)
    static func faceRect(_ image: CGImage) -> CGRect? {
        let req = VNDetectFaceRectanglesRequest()
        let h = VNImageRequestHandler(cgImage: image, options: [:])
        try? h.perform([req])
        guard let best = (req.results ?? []).max(by: { $0.boundingBox.width < $1.boundingBox.width }) else { return nil }
        let b = best.boundingBox
        let W = CGFloat(image.width), H = CGFloat(image.height)
        return CGRect(x: b.minX * W, y: (1 - b.maxY) * H, width: b.width * W, height: b.height * H)
    }

    /// Tekst (navn, tal, ord) som billede i gitterets format: ét ord pr. linje, så stort som muligt.
    static func textImage(_ text: String, cols: Int, rows: Int, invert: Bool) -> CGImage? {
        let size = CGSize(width: cols * 24, height: rows * 24)
        let lines = text.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init).filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }
        let probe = UIFont.systemFont(ofSize: 100, weight: .black)
        let widths = lines.map { ($0 as NSString).size(withAttributes: [.font: probe]).width }
        let lineH = probe.lineHeight * 0.92
        let scale = min(size.width * 0.92 / (widths.max() ?? 1), size.height * 0.62 / (lineH * CGFloat(lines.count)))
        let font = UIFont.systemFont(ofSize: 100 * scale, weight: .black)
        let fg: UIColor = invert ? .black : .white
        let bg: UIColor = invert ? .white : .black
        let f = UIGraphicsImageRendererFormat.default()
        f.scale = 1
        return UIGraphicsImageRenderer(size: size, format: f).image { ctx in
            bg.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            let total = lineH * scale * CGFloat(lines.count)
            var y = size.height * 0.46 - total / 2
            for l in lines {
                let s = (l as NSString).size(withAttributes: [.font: font])
                (l as NSString).draw(at: CGPoint(x: (size.width - s.width) / 2, y: y - (font.lineHeight - lineH * scale) / 2),
                                     withAttributes: [.font: font, .foregroundColor: fg])
                y += lineH * scale
            }
        }.cgImage
    }

    /// Lille forhåndsvisning af gitterets farver
    static func preview(_ grid: [Lab], cols: Int, rows: Int) -> UIImage? {
        guard grid.count == cols * rows * 4 else { return nil }
        let w = cols * 2, h = rows * 2
        var px = [UInt8](repeating: 255, count: w * h * 4)
        for r in 0..<rows { for c in 0..<cols { for q in 0..<4 {
            let rgb = ColorMath.rgb(grid[(r * cols + c) * 4 + q])
            let i = ((r * 2 + q / 2) * w + c * 2 + q % 2) * 4
            px[i] = UInt8(rgb.x * 255); px[i + 1] = UInt8(rgb.y * 255); px[i + 2] = UInt8(rgb.z * 255)
        } } }
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), let cg = ctx.makeImage() else { return nil }
        return UIImage(cgImage: cg)
    }
}
