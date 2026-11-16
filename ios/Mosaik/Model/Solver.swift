// Mosaik-løseren: vælger et billede fra puljen til hvert felt, så felternes farver (2×2 delfarver i Lab)
// ligner målbilledet. Grådig tildeling, sjældne farver først. Det samme billede må ikke stå tæt på sig selv
// (hverken i gitteret ved maks zoom eller i 3/5-kolonne-visningen), og hvert billede bruges højst `maxUses` gange.
import Foundation

struct MosaicCell {
    var item: Int        // plads i biblioteket (0 = ældste)
    var quads: [Lab]     // 4 delfarver: øverst v, øverst h, nederst v, nederst h
}

struct MosaicResult {
    var pick: [Int: Int]      // plads -> puljeindeks
    var error: [Int: Float]   // plads -> rms-afvigelse (Lab)
}

enum MosaicSolver {
    /// - pool: 4 delfarver pr. billede
    /// - fixed: pladser hvis billede ligger fast (fx ægte fotos eller det man kigger på lige nu): plads -> puljeindeks (eller -1 hvis ikke fra puljen)
    static func solve(pool: [[Lab]], cells: [MosaicCell], cols: Int, count: Int,
                      fixed: [Int: Int] = [:], seed: UInt64 = 1, maxUses: Int? = nil) -> MosaicResult {
        let P = pool.count
        guard P > 0, !cells.isEmpty, cols > 0 else { return MosaicResult(pick: [:], error: [:]) }
        // flad puljetabel
        var pf = [Float](repeating: 0, count: P * 12)
        for p in 0..<P { for q in 0..<4 { let c = pool[p][q]; pf[p * 12 + q * 3] = c.l; pf[p * 12 + q * 3 + 1] = c.a; pf[p * 12 + q * 3 + 2] = c.b } }
        let limit = maxUses ?? (cells.count / P + 2)
        let usePenalty: Float = 60
        let lw: Float = 1.3   // lysstyrke vejer lidt mere (ansigter, tekst)

        var assigned = [Int32](repeating: -1, count: count)
        for (k, v) in fixed where k >= 0 && k < count { assigned[k] = Int32(v) }
        var uses = [Int](repeating: 0, count: P)
        for v in fixed.values where v >= 0 && v < P { uses[v] += 1 }

        // gennemsnit af puljen -> felter langt fra gennemsnittet (sjældne farver) vælges først
        var mean = Lab(0, 0, 0)
        for p in 0..<P { let m = ColorMath.mean(pool[p][0..<4]); mean.l += m.l; mean.a += m.a; mean.b += m.b }
        mean.l /= Float(P); mean.a /= Float(P); mean.b /= Float(P)
        var rng = SplitMix64(seed: seed)
        let order = cells.indices.map { i -> (Int, Float) in
            let m = ColorMath.mean(cells[i].quads[0..<4])
            let d = (m.l - mean.l) * (m.l - mean.l) + (m.a - mean.a) * (m.a - mean.a) + (m.b - mean.b) * (m.b - mean.b)
            return (i, d + Float.random(in: 0..<200, using: &rng))
        }.sorted { $0.1 > $1.1 }.map { $0.0 }

        // naboer: ±2 rækker/kolonner ved maks zoom + de nærmeste pladser i rækkefølgen (3/5 kolonner)
        var offsets: [Int] = []
        for d in 1...10 { offsets.append(d); offsets.append(-d) }
        for dr in [-2, -1, 1, 2] { for dc in -2...2 { offsets.append(dr * cols + dc) } }
        var stamp = [Int](repeating: -1, count: P)

        var pick: [Int: Int] = [:], err: [Int: Float] = [:]
        pick.reserveCapacity(cells.count); err.reserveCapacity(cells.count)
        var t = [Float](repeating: 0, count: 12)
        for ci in order {
            let cell = cells[ci]
            let k = cell.item
            for o in offsets {
                let n = k + o
                if n < 0 || n >= count { continue }
                let v = Int(assigned[n]); if v >= 0 && v < P { stamp[v] = ci }
            }
            for q in 0..<4 { t[q * 3] = cell.quads[q].l; t[q * 3 + 1] = cell.quads[q].a; t[q * 3 + 2] = cell.quads[q].b }
            var best = -1, bestScore = Float.infinity, bestErr: Float = 0
            for p in 0..<P where stamp[p] != ci && uses[p] < limit {
                var e: Float = 0
                let base = p * 12
                for q in 0..<4 {
                    let dl = pf[base + q * 3] - t[q * 3], da = pf[base + q * 3 + 1] - t[q * 3 + 1], db = pf[base + q * 3 + 2] - t[q * 3 + 2]
                    e += lw * dl * dl + da * da + db * db
                }
                let s = e + usePenalty * Float(uses[p])
                if s < bestScore { bestScore = s; best = p; bestErr = e }
            }
            if best < 0 { // alt er brugt op i nærheden: tag den bedste uden begrænsning
                for p in 0..<P {
                    var e: Float = 0
                    for q in 0..<12 { let d = pf[p * 12 + q] - t[q]; e += d * d }
                    if e < bestScore { bestScore = e; best = p; bestErr = e }
                }
            }
            assigned[k] = Int32(best)
            uses[best] += 1
            pick[k] = best
            err[k] = sqrtf(bestErr / 4)
        }
        return MosaicResult(pick: pick, error: err)
    }

    /// Almindelig blanding til resten af biblioteket: puljen i tilfældig rækkefølge, gentaget, så ens billeder står langt fra hinanden.
    static func shuffled(poolCount: Int, count: Int, seed: UInt64) -> [Int] {
        guard poolCount > 0 else { return [] }
        var rng = SplitMix64(seed: seed)
        var out: [Int] = []
        out.reserveCapacity(count)
        while out.count < count {
            var round = Array(0..<poolCount)
            round.shuffle(using: &rng)
            // de første i denne runde må ikke være blandt de sidste i forrige
            if poolCount > 60 {
                let tail = Set(out.suffix(20))
                for i in 0..<20 where tail.contains(round[i]) { round.swapAt(i, Int.random(in: 20..<poolCount, using: &rng)) }
            }
            out.append(contentsOf: round)
        }
        return Array(out.prefix(count))
    }
}
