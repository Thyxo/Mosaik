// Farveregning: sRGB (0…1, gamma) <-> CIE Lab (D65). Ren Swift, testes uden UIKit.
import Foundation

struct Lab: Equatable {
    var l: Float
    var a: Float
    var b: Float
    init(_ l: Float, _ a: Float, _ b: Float) { self.l = l; self.a = a; self.b = b }
}

enum ColorMath {
    @inline(__always) static func lin(_ c: Float) -> Float { c <= 0.04045 ? c / 12.92 : powf((c + 0.055) / 1.055, 2.4) }
    @inline(__always) static func gam(_ c: Float) -> Float { c <= 0.0031308 ? c * 12.92 : 1.055 * powf(c, 1 / 2.4) - 0.055 }

    /// sRGB 0…1 -> Lab
    static func lab(_ r: Float, _ g: Float, _ b: Float) -> Lab {
        let r = lin(r), g = lin(g), b = lin(b)
        let x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
        let y = 0.2126 * r + 0.7152 * g + 0.0722 * b
        let z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883
        func f(_ t: Float) -> Float { t > 0.008856 ? cbrtf(t) : 7.787 * t + 16 / 116 }
        let fx = f(x), fy = f(y), fz = f(z)
        return Lab(116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))
    }

    /// Lab -> sRGB 0…1 (klippet)
    static func rgb(_ c: Lab) -> SIMD3<Float> {
        let fy = (c.l + 16) / 116
        let fx = fy + c.a / 500
        let fz = fy - c.b / 200
        func fi(_ t: Float) -> Float { let t3 = t * t * t; return t3 > 0.008856 ? t3 : (t - 16 / 116) / 7.787 }
        let x = fi(fx) * 0.95047, y = fi(fy), z = fi(fz) * 1.08883
        let r = 3.2406 * x - 1.5372 * y - 0.4986 * z
        let g = -0.9689 * x + 1.8758 * y + 0.0415 * z
        let b = 0.0557 * x - 0.2040 * y + 1.0570 * z
        func cl(_ v: Float) -> Float { min(1, max(0, gam(max(0, v)))) }
        return SIMD3(cl(r), cl(g), cl(b))
    }

    static func mean(_ q: ArraySlice<Lab>) -> Lab {
        var l: Float = 0, a: Float = 0, b: Float = 0
        for c in q { l += c.l; a += c.a; b += c.b }
        let n = Float(max(1, q.count))
        return Lab(l / n, a / n, b / n)
    }

    /// Farvetone, der lagt over et billede med gennemsnitsfarven `under` giver `target`.
    /// Returnerer (farve, alfa). Alfa er mindst `base` og højst `cap` (alt i sRGB 0…1, som UIKit blander).
    static func tint(target t: SIMD3<Float>, under i: SIMD3<Float>, base: Float, cap: Float) -> (SIMD3<Float>, Float) {
        var need: Float = 0
        for k in 0..<3 {
            let n: Float = t[k] > i[k] ? (t[k] - i[k]) / max(1e-4, 1 - i[k]) : (i[k] - t[k]) / max(1e-4, i[k])
            need = max(need, n)
        }
        let a = min(cap, max(base, need))
        guard a > 0.001 else { return (t, 0) }
        var c = (t - (1 - a) * i) / a
        c = SIMD3(min(1, max(0, c.x)), min(1, max(0, c.y)), min(1, max(0, c.z)))
        return (c, a)
    }
}
