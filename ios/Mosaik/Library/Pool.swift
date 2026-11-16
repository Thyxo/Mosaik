// Billedpuljen: 993 fotos (Picsum/Unsplash-licens) i Resources/Pool + farver i pool.json (scripts/fetch-pool.py).
import Foundation

struct PoolEntry: Decodable {
    let f: String        // filnavn uden .jpg (p0123 = Picsum-id 123)
    let q: [[Float]]     // 4 delfarver (Lab)
    let rgb: [Float]     // gennemsnit sRGB 0…255
    let a: Float         // originalens bredde/højde
}

final class Pool {
    static let shared = Pool()

    let entries: [PoolEntry]
    let quads: [[Lab]]
    let rgb: [SIMD3<Float>]
    private let dir: URL

    private init() {
        let res = Bundle.main.resourceURL ?? URL(fileURLWithPath: "/")
        dir = res.appendingPathComponent("Pool", isDirectory: true)
        if let u = Bundle.main.url(forResource: "pool", withExtension: "json"),
           let d = try? Data(contentsOf: u),
           let e = try? JSONDecoder().decode([PoolEntry].self, from: d) {
            entries = e
        } else {
            entries = []
        }
        quads = entries.map { $0.q.map { Lab($0[0], $0[1], $0[2]) } }
        rgb = entries.map { SIMD3($0.rgb[0] / 255, $0.rgb[1] / 255, $0.rgb[2] / 255) }
    }

    var count: Int { entries.count }
    func url(_ i: Int) -> URL { dir.appendingPathComponent(entries[i].f + ".jpg") }
    func picsumID(_ i: Int) -> Int { Int(entries[i].f.dropFirst()) ?? 0 }
    func aspect(_ i: Int) -> CGFloat { CGFloat(max(0.2, entries[i].a)) }
}
