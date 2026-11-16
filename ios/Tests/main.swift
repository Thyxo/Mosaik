// Hurtig test af farveregning og mosaikløser (kører i CI før buildet):
// swiftc ios/Mosaik/Model/*.swift ios/Tests/main.swift -o /tmp/t && /tmp/t
import Foundation

var failures = 0
func check(_ ok: Bool, _ msg: String) { if !ok { failures += 1; print("FEJL:", msg) } else { print("ok:", msg) } }

// 1. Lab tur/retur
for (r, g, b) in [(0.0, 0.0, 0.0), (1.0, 1.0, 1.0), (0.8, 0.2, 0.1), (0.1, 0.5, 0.9)] as [(Float, Float, Float)] {
    let back = ColorMath.rgb(ColorMath.lab(r, g, b))
    check(abs(back.x - r) < 0.01 && abs(back.y - g) < 0.01 && abs(back.z - b) < 0.01, "Lab tur/retur \(r),\(g),\(b)")
}

// 2. Farvetone giver præcis målfarven (når det kan lade sig gøre)
do {
    let t = SIMD3<Float>(0.9, 0.8, 0.1), i = SIMD3<Float>(0.3, 0.4, 0.5)
    let (c, a) = ColorMath.tint(target: t, under: i, base: 0.3, cap: 1)
    let shown = (1 - a) * i + a * c
    check(abs(shown.x - t.x) < 0.01 && abs(shown.y - t.y) < 0.01 && abs(shown.z - t.z) < 0.01, "farvetone rammer målet (alfa \(a))")
}

// 3. Løseren: tilfældig pulje, mål = vandret gradient
var rng = SplitMix64(seed: 42)
let poolSize = 600
let pool: [[Lab]] = (0..<poolSize).map { _ in
    let base = ColorMath.lab(Float.random(in: 0...1, using: &rng), Float.random(in: 0...1, using: &rng), Float.random(in: 0...1, using: &rng))
    return (0..<4).map { _ in Lab(base.l + Float.random(in: -8...8, using: &rng), base.a, base.b) }
}
let cols = 36, rows = 70, count = cols * rows - 10
var cells: [MosaicCell] = []
for r in 0..<rows { for c in 0..<cols {
    let item = r * cols + c
    if item >= count { continue }
    let lab = ColorMath.lab(Float(c) / Float(cols), 0.3, 1 - Float(r) / Float(rows))
    cells.append(MosaicCell(item: item, quads: [lab, lab, lab, lab]))
} }
let t0 = Date()
let res = MosaicSolver.solve(pool: pool, cells: cells, cols: cols, count: count, seed: 7)
let dt = Date().timeIntervalSince(t0)
check(res.pick.count == cells.count, "alle felter fik et billede (\(res.pick.count))")
let meanErr = res.error.values.reduce(0, +) / Float(max(1, res.error.count))
// sammenlign med tilfældig tildeling
var randErr: Float = 0
for cell in cells {
    let p = pool[Int.random(in: 0..<poolSize, using: &rng)]
    var e: Float = 0
    for q in 0..<4 { let d = (p[q].l - cell.quads[q].l, p[q].a - cell.quads[q].a, p[q].b - cell.quads[q].b); e += d.0 * d.0 + d.1 * d.1 + d.2 * d.2 }
    randErr += sqrtf(e / 4)
}
randErr /= Float(cells.count)
check(meanErr < randErr * 0.45, "afvigelse \(meanErr) mod tilfældig \(randErr)")
var uses = [Int](repeating: 0, count: poolSize)
for p in res.pick.values { uses[p] += 1 }
check((uses.max() ?? 0) <= cells.count / poolSize + 2, "højst \(cells.count / poolSize + 2) brug pr. billede (max \(uses.max() ?? 0))")
var clash = 0
for (k, p) in res.pick {
    for o in [1, 2, 3, 5, cols, cols + 1, cols - 1] { if res.pick[k + o] == p { clash += 1 } }
}
check(clash == 0, "ingen ens billeder ved siden af hinanden (\(clash))")
print(String(format: "løser: %.2f s", dt))

// 4. Blanding
let sh = MosaicSolver.shuffled(poolCount: 993, count: 2589, seed: 3)
var close = 0
for i in sh.indices { for o in 1...20 where i + o < sh.count && sh[i + o] == sh[i] { close += 1 } }
check(sh.count == 2589 && close == 0, "blanding uden gentagelser tæt på hinanden (\(close))")

if failures > 0 { print("\(failures) fejl"); exit(1) }
print("alle tests ok")
