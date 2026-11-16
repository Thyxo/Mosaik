// Appens tilstand: biblioteket (hvilket billede står hvor + farvetone), mosaikken, relæet og panelet.
import Photos
import SwiftUI
import UIKit

/// Én plads i biblioteket
struct Tile {
    var src: Int32                     // >= 0 puljen, < 0 ægte foto nr. -src-1
    var tint = SIMD3<Float>(0, 0, 0)   // farvetone ved maks zoom
    var alpha: Float = 0               // styrke ved maks zoom
}

@MainActor @Observable
final class AppState {
    var s = Settings.load() { didSet { if s != oldValue { s.save() } } }

    var tiles: [Tile] = []
    var dates: [Date] = []
    var rev = 0                         // tælles op når gitteret skal genindlæses

    var subtitle = ""
    var secretOpen = false
    var viewerIndex: Int?
    var badge = false

    var busy = false
    var status = ""                     // seneste hændelse (vises i panelet)
    var relayStatus = "off"
    var targetLabel = UserDefaults.standard.string(forKey: "mosaik.targetLabel") ?? ""
    var targetPreview: UIImage?
    var mosaicPreview: UIImage?
    var realLoaded = 0

    @ObservationIgnored var visibleItems: () -> [Int] = { [] }
    @ObservationIgnored private var relay: RelayClient?
    @ObservationIgnored private var lastRelayAt = UserDefaults.standard.double(forKey: "mosaik.lastRelayAt")
    @ObservationIgnored private var started = false

    /// Zoom-niveauer (kolonner) som i Fotos; det sidste er mosaikken
    var levels: [Int] { Array(Set([3, 5, 9, 15, 24].filter { $0 < s.maxCols } + [s.maxCols])).sorted() }

    // MARK: Start

    func start() async {
        guard !started else { return }
        started = true
        if s.seed == 0 { s.seed = UInt64.random(in: 1...UInt64.max / 2) }
        ImageStore.shared.preloadSmall()
        if s.realCount > 0 && RealPhotos.shared.authorized { await RealPhotos.shared.load(count: s.realCount) }
        realLoaded = RealPhotos.shared.assets.count
        buildBase()
        await restoreTarget()
        connectRelay()
    }

    /// Biblioteket uden mosaik: puljen blandet + de ægte fotos nederst
    func buildBase() {
        let n = max(1, s.itemCount)
        let real = RealPhotos.shared
        let k = min(real.assets.count, min(s.realCount, n))
        let seq = MosaicSolver.shuffled(poolCount: Pool.shared.count, count: n - k, seed: s.seed)
        var t = seq.map { Tile(src: Int32($0)) }
        for j in stride(from: k - 1, through: 0, by: -1) { t.append(Tile(src: Int32(-j - 1))) }  // nyeste (j = 0) sidst
        tiles = t
        dates = Dates.make(count: n, real: real.assets.prefix(k).map { $0.creationDate ?? Date() }, seed: s.seed)
        rev += 1
    }

    /// Genopbyg alt (efter ændrede indstillinger)
    func rebuild() async {
        if s.realCount > 0 && RealPhotos.shared.authorized { await RealPhotos.shared.load(count: s.realCount) }
        else if s.realCount == 0 { await RealPhotos.shared.load(count: 0) }
        realLoaded = RealPhotos.shared.assets.count
        buildBase()
        await restoreTarget()
    }

    func requestPhotos() async {
        _ = await RealPhotos.shared.requestAccess()
        await rebuild()
    }

    // MARK: Mosaik

    private var docs: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    private var targetFile: URL { docs.appendingPathComponent("target.jpg") }

    private func restoreTarget() async {
        let d = UserDefaults.standard
        if let text = d.string(forKey: "mosaik.targetText"), !text.isEmpty {
            await apply(text: text, label: targetLabel, save: false)
        } else if let data = try? Data(contentsOf: targetFile), let img = ImageStore.downsample(data: data, px: 1400) {
            await apply(image: img, label: targetLabel, save: false)
        }
    }

    /// Gitterets mål ved maks zoom: (kolonner, synlige rækker)
    private func region() -> (cols: Int, rows: Int, firstRow: Int) {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let win = scene?.windows.first
        let size = win?.bounds.size ?? UIScreen.main.bounds.size
        let bottom = win?.safeAreaInsets.bottom ?? 34
        let cols = s.maxCols
        let pitch = (size.width + 1) / CGFloat(cols)
        let visible = Int(ceil((size.height - bottom) / pitch))
        let total = (tiles.count + cols - 1) / cols
        let rows = max(1, min(total, visible))
        return (cols, rows, total - rows)
    }

    func apply(image: CGImage, label: String, save: Bool = true) async {
        if save {
            if let d = UIImage(cgImage: image).jpegData(compressionQuality: 0.9) { try? d.write(to: targetFile) }
            UserDefaults.standard.removeObject(forKey: "mosaik.targetText")
        }
        await build(label: label, isText: false, save: save) { cols, rows, s in
            TargetMaker.grid(from: image, cols: cols, rows: rows, faceCrop: s.faceCrop, contrast: Float(s.contrast))
        }
        targetPreview = UIImage(cgImage: image)
    }

    func apply(text: String, label: String? = nil, save: Bool = true) async {
        if save {
            UserDefaults.standard.set(text, forKey: "mosaik.targetText")
            try? FileManager.default.removeItem(at: targetFile)
        }
        let invert = s.textInvert
        var img: CGImage?
        await build(label: label ?? text, isText: true, save: save) { cols, rows, _ in
            guard let t = TargetMaker.textImage(text, cols: cols, rows: rows, invert: invert) else { return [] }
            img = t
            return TargetMaker.grid(from: t, cols: cols, rows: rows, faceCrop: false, contrast: 1)
        }
        targetPreview = img.map { UIImage(cgImage: $0) }
    }

    private func build(label: String, isText: Bool, save: Bool, grid: @escaping (Int, Int, Settings) -> [Lab]) async {
        busy = true
        defer { busy = false }
        let (cols, rows, firstRow) = region()
        let settings = s
        let n = tiles.count
        let current = tiles
        let realRGB = RealPhotos.shared.rgb
        let locked = Set(visibleItems())
        let seed = s.seed

        let result: [Tile]? = await Task.detached(priority: .userInitiated) { () -> [Tile]? in
            let g = grid(cols, rows, settings)
            guard g.count == cols * rows * 4 else { return nil }
            let pool = Pool.shared
            var cells: [MosaicCell] = []
            var fixed: [Int: Int] = [:]
            for r in 0..<rows {
                for c in 0..<cols {
                    let item = (firstRow + r) * cols + c
                    guard item < n else { continue }
                    if current[item].src < 0 || locked.contains(item) { fixed[item] = Int(current[item].src); continue }
                    let o = (r * cols + c) * 4
                    cells.append(MosaicCell(item: item, quads: Array(g[o..<o + 4])))
                }
            }
            let res = MosaicSolver.solve(pool: pool.quads, cells: cells, cols: cols, count: n, fixed: fixed, seed: seed)
            var out = current
            for i in out.indices { out[i].alpha = 0 }
            for (item, p) in res.pick { out[item].src = Int32(p) }
            let base = Float(isText ? max(settings.tintBase, settings.textTint) : settings.tintBase)
            let cap = Float(settings.tintCap)
            for r in 0..<rows {
                for c in 0..<cols {
                    let item = (firstRow + r) * cols + c
                    guard item < n else { continue }
                    let o = (r * cols + c) * 4
                    let target = ColorMath.rgb(ColorMath.mean(g[o..<o + 4]))
                    let src = out[item].src
                    let under: SIMD3<Float> = src >= 0 ? pool.rgb[Int(src)]
                        : (Int(-src - 1) < realRGB.count ? realRGB[Int(-src - 1)] : SIMD3(0.5, 0.5, 0.5))
                    let (tint, a) = ColorMath.tint(target: target, under: under, base: base, cap: cap)
                    out[item].tint = tint
                    out[item].alpha = a
                }
            }
            return out
        }.value

        guard let result else { status = "Kunne ikke lave mosaikken"; return }
        tiles = result
        rev += 1
        targetLabel = label
        UserDefaults.standard.set(label, forKey: "mosaik.targetLabel")
        mosaicPreview = renderPreview(cols: cols, rows: rows, firstRow: firstRow)
        if save {
            status = "Klar: \(label)"
            if s.badge { badge = true }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    /// Ryd mosaikken (almindeligt bibliotek igen)
    func clearTarget() {
        UserDefaults.standard.removeObject(forKey: "mosaik.targetText")
        UserDefaults.standard.removeObject(forKey: "mosaik.targetLabel")
        try? FileManager.default.removeItem(at: targetFile)
        targetLabel = ""
        targetPreview = nil
        mosaicPreview = nil
        badge = false
        buildBase()
        status = "Mosaik ryddet"
    }

    /// Sådan ser mosaikken ud ved maks zoom (gennemsnitsfarver + farvetone)
    private func renderPreview(cols: Int, rows: Int, firstRow: Int) -> UIImage? {
        let pool = Pool.shared
        let real = RealPhotos.shared.rgb
        let f = UIGraphicsImageRendererFormat.default()
        f.scale = 1
        let px: CGFloat = 4
        return UIGraphicsImageRenderer(size: CGSize(width: CGFloat(cols) * px, height: CGFloat(rows) * px), format: f).image { ctx in
            UIColor.black.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: CGFloat(cols) * px, height: CGFloat(rows) * px))
            for r in 0..<rows {
                for c in 0..<cols {
                    let item = (firstRow + r) * cols + c
                    guard item < tiles.count else { continue }
                    let t = tiles[item]
                    let u: SIMD3<Float> = t.src >= 0 ? pool.rgb[Int(t.src)] : (Int(-t.src - 1) < real.count ? real[Int(-t.src - 1)] : SIMD3(0.5, 0.5, 0.5))
                    let m = (1 - t.alpha) * u + t.alpha * t.tint
                    UIColor(red: CGFloat(m.x), green: CGFloat(m.y), blue: CGFloat(m.z), alpha: 1).setFill()
                    ctx.fill(CGRect(x: CGFloat(c) * px, y: CGFloat(r) * px, width: px - 0.5, height: px - 0.5))
                }
            }
        }
    }

    // MARK: Forespørgsler (relæ, panel)

    /// kind: q (find billede, ellers tekst) · text · url · img (base64)
    func run(kind: String, value: String) async {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty else { return }
        switch kind {
        case "text":
            await apply(text: v)
        case "url":
            status = "Henter billede …"
            if let u = URL(string: v), let img = await Lookup.download(u) { await apply(image: img, label: u.lastPathComponent) }
            else { status = "Kunne ikke hente billedet" }
        case "img":
            if let img = Lookup.decodeBase64(v) { await apply(image: img, label: "Billede") } else { status = "Ugyldigt billede" }
        default:
            status = "Søger: \(v) …"
            busy = true
            if let (img, title) = await Lookup.image(for: v, lang: s.wikiLang) {
                await apply(image: img, label: title)
            } else {
                status = "Intet billede – bruger tekst"
                await apply(text: v)
            }
        }
    }

    // MARK: Relæ

    func connectRelay() {
        relay?.stop()
        relay = nil
        guard s.source == "relay", RelayClient.clean(s.room).count >= 3 else { relayStatus = "off"; return }
        let r = RelayClient(room: s.room, onState: { [weak self] st in self?.relayState(st) },
                            onStatus: { [weak self] st in self?.relayStatus = st })
        relay = r
        r.start()
    }

    func pauseRelay() { relay?.stop() }
    func resumeRelay() { if let r = relay { r.start() } else { connectRelay() } }

    private func relayState(_ st: [String: Any]) {
        var best: (at: Double, kind: String, value: String)?
        func consider(_ at: Double?, _ kind: String, _ value: String?) {
            guard let at, let value, !value.isEmpty else { return }
            if best == nil || at > best!.at { best = (at, kind, value) }
        }
        if s.listenMosaik, let m = st["mosaik"] as? [String: Any] {
            let at = (m["at"] as? NSNumber)?.doubleValue
            if let q = m["q"] as? String { consider(at, "q", q) }
            else if let t = m["text"] as? String { consider(at, "text", t) }
            else if let u = m["url"] as? String { consider(at, "url", u) }
            else if let i = m["img"] as? String { consider(at, "img", i) }
        }
        if s.listenGoogle, let g = st["google"] as? [String: Any] {
            consider((g["at"] as? NSNumber)?.doubleValue, "q", g["q"] as? String)
        }
        if s.listenForce, let f = st["force"] as? [String: Any] {
            consider((f["at"] as? NSNumber)?.doubleValue, "q", f["name"] as? String)
        }
        guard let b = best, b.at > lastRelayAt else { return }
        lastRelayAt = b.at
        UserDefaults.standard.set(b.at, forKey: "mosaik.lastRelayAt")
        // gamle beskeder (over 6 timer) ignoreres
        if Date().timeIntervalSince1970 * 1000 - b.at > 6 * 3600 * 1000 { return }
        Task { await run(kind: b.kind, value: b.value) }
    }

    /// Send en test-besked gennem relæet (som en anden app ville gøre)
    func relayTest(_ q: String) async {
        let r = relay ?? RelayClient(room: s.room, onState: { _ in }, onStatus: { _ in })
        await r.publish(["mosaik": ["q": q, "at": Int(Date().timeIntervalSince1970 * 1000)]])
    }

    // MARK: Undertitel

    @ObservationIgnored private var lastInfo = (-1, false, -1)
    func gridInfo(topIndex: Int, atBottom: Bool, cols: Int) {
        guard (topIndex, atBottom, cols) != lastInfo else { return }
        lastInfo = (topIndex, atBottom, cols)
        if atBottom || dates.isEmpty {
            subtitle = "\(Dates.number(tiles.count)) \(s.itemsWord)"
        } else {
            subtitle = Dates.header(dates[min(max(0, topIndex), dates.count - 1)], fine: cols <= 5)
        }
    }
}
