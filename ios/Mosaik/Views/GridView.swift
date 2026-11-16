// Fotogitteret (UIKit for at kunne vise ~3.000 felter): zoom-niveauer med knib, animeret skift med
// fingeren som anker (som i Fotos), og farvetonen, der kun ses de yderste niveauer.
import SwiftUI
import UIKit

final class TileView: UIView {
    var index = -1
    var src: Int32 = .min
    var isBig = false
    let tintView = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        isUserInteractionEnabled = false
        layer.contentsGravity = .resizeAspectFill
        backgroundColor = UIColor(white: 0.5, alpha: 0.15)
        tintView.frame = bounds
        tintView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tintView.isUserInteractionEnabled = false
        addSubview(tintView)
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// Fælles mål (bruges også af AppState til mosaikkens område)
enum GridGeo {
    static func gap(_ c: Int, scale: CGFloat) -> CGFloat { c <= 5 ? 2 : (c <= 15 ? 1 : 1 / max(1, scale)) }
    static func pitch(width: CGFloat, cols c: Int, scale: CGFloat) -> CGFloat { (width + gap(c, scale: scale)) / CGFloat(c) }
    /// plads til fanebjælken under sidste række (målt på iPhone: 94 pt fra bunden)
    static let barSpace: CGFloat = 60
}

/// Ét zoom-niveau: felterne lagt ud i `cols` kolonner. Origo i øverste venstre hjørne (anchorPoint 0,0),
/// så `center` er hjørnets plads og `transform` en ren skalering.
final class GridLayer: UIView {
    let cols: Int
    var tiles: [Int: TileView] = [:]
    init(cols: Int) {
        self.cols = cols
        super.init(frame: .zero)
        layer.anchorPoint = .zero
        isUserInteractionEnabled = false
    }
    required init?(coder: NSCoder) { fatalError() }
    func place(scale s: CGFloat, origin o: CGPoint) {
        transform = CGAffineTransform(scaleX: s, y: s)
        center = o
    }
}

final class GridView: UIScrollView {
    var count: () -> Int = { 0 }
    var tileAt: (Int) -> Tile = { _ in Tile(src: 0) }
    var onTap: (Int) -> Void = { _ in }
    var onInfo: (Int, Bool, Int) -> Void = { _, _, _ in }
    var dateAt: (Int) -> Date? = { _ in nil }

    private(set) var levels = [3, 5, 15, 30]
    private(set) var cols = 5
    var rev = -1
    /// feltet der lige nu vises i fremviseren (skjules i gitteret, som i Fotos)
    var hiddenIndex: Int? { didSet { if hiddenIndex != oldValue { refreshHidden(oldValue) } } }

    private var layers: [Int: GridLayer] = [:]
    private var main: GridLayer { layer(cols) }
    private var spare: [TileView] = []
    private var animating = false
    private var lastWidth: CGFloat = 0
    private var didScrollToBottom = false

    // datomærker ("Okt. 2026" / "2026")
    private var pills: [DatePill] = []
    private var sectionCache: [Int: (starts: [Int], labels: [NSAttributedString])] = [:]

    // knib: effektivt antal kolonner `e` og fingerpunkt `p`; feltet under fingeren følger med
    private var pinching = false
    private var pinchStartCols = 5
    private var anchorIndex = 0
    private var anchorX: CGFloat = 0
    private var anchorFY: CGFloat = 0
    private var pinchE: CGFloat = 5
    private var pinchP = CGPoint.zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .systemBackground
        contentInsetAdjustmentBehavior = .never
        alwaysBounceVertical = true
        showsHorizontalScrollIndicator = false
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(onPinch(_:)))
        addGestureRecognizer(pinch)
        let tap = UITapGestureRecognizer(target: self, action: #selector(onTapGesture(_:)))
        addGestureRecognizer(tap)
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: Geometri

    private var safe: UIEdgeInsets { window?.safeAreaInsets ?? UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0) }
    private var scale: CGFloat { max(1, traitCollection.displayScale) }

    func gap(_ c: Int) -> CGFloat { GridGeo.gap(c, scale: scale) }
    func pitch(_ c: Int) -> CGFloat { GridGeo.pitch(width: bounds.width, cols: c, scale: scale) }
    func frameFor(_ i: Int, cols c: Int) -> CGRect {
        let p = pitch(c), g = gap(c)
        return CGRect(x: CGFloat(i % c) * p, y: CGFloat(i / c) * p, width: p - g, height: p - g)
    }
    func contentHeight(_ c: Int) -> CGFloat {
        let rows = (count() + c - 1) / c
        return max(0, CGFloat(rows) * pitch(c) - gap(c))
    }
    private var bottomInset: CGFloat { safe.bottom + GridGeo.barSpace }
    private func topInset(_ c: Int) -> CGFloat { max(safe.top + 58, bounds.height - bottomInset - contentHeight(c)) }
    private func maxOffset(_ c: Int) -> CGFloat { max(-topInset(c), contentHeight(c) + bottomInset - bounds.height) }
    private var maxOffsetY: CGFloat { maxOffset(cols) }

    private func layer(_ c: Int) -> GridLayer {
        if let l = layers[c] { return l }
        let l = GridLayer(cols: c)
        insertSubview(l, at: 0)
        l.bounds = CGRect(x: 0, y: 0, width: bounds.width, height: contentHeight(c))
        l.place(scale: 1, origin: .zero)
        layers[c] = l
        return l
    }

    private func dropLayer(_ c: Int) {
        guard let l = layers.removeValue(forKey: c) else { return }
        for (_, t) in l.tiles { recycle(t) }
        l.removeFromSuperview()
    }

    private func applyGeometry() {
        let h = contentHeight(cols)
        let m = main
        m.transform = .identity
        m.bounds = CGRect(x: 0, y: 0, width: bounds.width, height: h)
        m.center = .zero
        m.alpha = 1
        contentSize = CGSize(width: bounds.width, height: h)
        contentInset = UIEdgeInsets(top: topInset(cols), left: 0, bottom: bottomInset, right: 0)
        verticalScrollIndicatorInsets = UIEdgeInsets(top: safe.top + 50, left: 0, bottom: bottomInset + 60, right: 0)
    }

    func scrollToBottom() {
        contentOffset = CGPoint(x: 0, y: maxOffsetY)
    }

    // MARK: Data

    func setLevels(_ l: [Int]) {
        levels = l
        if !levels.contains(cols) { cols = levels.min(by: { abs($0 - cols) < abs($1 - cols) }) ?? 5 }
        reloadAll(keepPosition: false)
    }

    /// Ny data (fx en mosaik): opdatér felterne. Antal ændret = start forfra nederst.
    func reloadAll(keepPosition: Bool) {
        let n = count()
        let h = contentHeight(cols)
        if !keepPosition || abs(h - contentSize.height) > 0.5 {
            for c in Array(layers.keys) { dropLayer(c) }
            applyGeometry()
            if n > 0 && bounds.width > 0 { scrollToBottom(); didScrollToBottom = true }
        }
        sectionCache.removeAll()
        for (_, l) in layers {
            for (i, t) in l.tiles where i < n { configure(t, i, cols: l.cols) }
        }
        setNeedsLayout()
    }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.width != lastWidth && bounds.width > 0 {
            lastWidth = bounds.width
            for c in Array(layers.keys) { dropLayer(c) }
            applyGeometry()
            if !didScrollToBottom && count() > 0 { scrollToBottom(); didScrollToBottom = true }
        }
        layoutTiles()
        layoutPills()
        report()
    }

    // MARK: Datomærker

    /// gran 1 = måned, 2 = år
    private func sections(_ gran: Int) -> (starts: [Int], labels: [NSAttributedString]) {
        if let c = sectionCache[gran] { return c }
        let cal = Calendar.current
        var starts: [Int] = [], labels: [NSAttributedString] = []
        var lastKey = Int.min
        let white: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 17, weight: .semibold), .foregroundColor: UIColor.white]
        let gray: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 17, weight: .semibold), .foregroundColor: UIColor(white: 1, alpha: 0.6)]
        for i in 0..<count() {
            guard let d = dateAt(i) else { continue }
            let c = cal.dateComponents([.year, .month], from: d)
            let y = c.year ?? 0, m = c.month ?? 1
            let key = gran == 1 ? y * 12 + m : y
            if key == lastKey { continue }
            lastKey = key
            starts.append(i)
            if gran == 1 {
                let s = NSMutableAttributedString(string: Dates.monthShort(d), attributes: white)
                s.append(NSAttributedString(string: " \(y)", attributes: gray))
                labels.append(s)
            } else {
                labels.append(NSAttributedString(string: "\(y)", attributes: white))
            }
        }
        sectionCache[gran] = (starts, labels)
        return (starts, labels)
    }

    private func layoutPills() {
        var used = 0
        defer { for k in used..<pills.count { pills[k].isHidden = true } }
        guard !animating, !pinching, cols >= 15, count() > 0, bounds.width > 0 else { return }
        let (starts, labels) = sections(cols >= 24 ? 2 : 1)
        guard !starts.isEmpty else { return }
        let p = pitch(cols)
        func rowTop(_ i: Int) -> CGFloat { CGFloat(i / cols) * p }
        let probe = contentOffset.y + safe.top + 83     // mærkets faste plads under titlen
        let bottom = contentOffset.y + bounds.height - bottomInset
        let h = DatePill.height
        // sidste afsnit der er startet over den faste plads
        var lo = 0, hi = starts.count - 1, k = -1
        while lo <= hi { let mid = (lo + hi) / 2; if rowTop(starts[mid]) <= probe { k = mid; lo = mid + 1 } else { hi = mid - 1 } }
        func place(_ idx: Int, _ y: CGFloat) {
            if used == pills.count { let v = DatePill(); addSubview(v); pills.append(v) }
            let v = pills[used]; used += 1
            v.isHidden = false
            bringSubviewToFront(v)
            v.set(labels[idx])
            v.frame = CGRect(x: 13, y: y, width: v.width, height: h)
        }
        if k >= 0 {
            var y = probe
            if k + 1 < starts.count { y = min(y, rowTop(starts[k + 1]) - h - 8) }
            place(k, y)
        }
        var j = k + 1
        while j < starts.count, rowTop(starts[j]) < bottom, used < 12 {
            place(j, rowTop(starts[j]))
            j += 1
        }
    }

    private func range(cols c: Int, rect: CGRect) -> Range<Int> {
        let p = pitch(c), n = count()
        let r0 = max(0, Int(floor(rect.minY / p)))
        let r1 = max(r0, Int(ceil(rect.maxY / p)))
        let lo = min(n, r0 * c), hi = min(n, (r1 + 1) * c)
        return lo..<max(lo, hi)
    }

    func visibleIndices() -> [Int] {
        Array(range(cols: cols, rect: bounds))
    }

    /// Sørg for felter i `l` for området `rect` (i lagets egne koordinater); resten genbruges.
    private func fill(_ l: GridLayer, rect: CGRect) {
        let r = range(cols: l.cols, rect: rect)
        for i in Array(l.tiles.keys) where !r.contains(i) {
            if let t = l.tiles.removeValue(forKey: i) { recycle(t) }
        }
        UIView.performWithoutAnimation {
            for i in r where l.tiles[i] == nil {
                let t = dequeue(into: l)
                t.index = i
                t.frame = frameFor(i, cols: l.cols)
                configure(t, i, cols: l.cols)
                l.tiles[i] = t
            }
        }
    }

    private func layoutTiles() {
        guard !animating, !pinching, bounds.width > 0 else { return }
        fill(main, rect: bounds.insetBy(dx: 0, dy: -pitch(cols)))
    }

    private func dequeue(into l: GridLayer) -> TileView {
        let t = spare.popLast() ?? TileView(frame: .zero)
        if t.superview !== l { l.addSubview(t) }
        t.isHidden = false
        t.alpha = 1
        return t
    }

    private func recycle(_ t: TileView) {
        t.isHidden = true
        t.index = -1
        t.layer.removeAllAnimations()
        spare.append(t)
    }

    func tintFactor(_ c: Int) -> CGFloat {
        let lo: CGFloat = 5, hi = CGFloat(levels.last ?? 30)
        guard CGFloat(c) > lo, hi > lo else { return 0 }
        return pow(min(1, (CGFloat(c) - lo) / (hi - lo)), 1.4)
    }

    private func configure(_ t: TileView, _ i: Int, cols c: Int) {
        let tile = tileAt(i)
        let wantBig = pitch(c) * scale > 110
        let store = ImageStore.shared
        if t.src != tile.src || (wantBig && !t.isBig) {
            t.src = tile.src
            t.isBig = wantBig
            let have = (wantBig ? store.big(tile.src) : nil) ?? store.small(tile.src)
            t.layer.contents = have
            let missingBig = wantBig && store.big(tile.src) == nil
            if have == nil || missingBig {
                let src = tile.src
                store.load(src, big: wantBig) { [weak t] img in
                    guard let t, t.src == src, let img else { return }
                    t.layer.contents = img
                }
            }
        }
        t.alpha = i == hiddenIndex ? 0 : 1
        // Fotos runder de yderste hjørner af sidste række
        let n = count(), lastRow = ((n - 1) / c) * c
        var corners: CACornerMask = []
        if i == lastRow { corners.insert(.layerMinXMaxYCorner) }
        if i == n - 1 { corners.insert(.layerMaxXMaxYCorner) }
        if n % c != 0 && i == lastRow - 1 { corners.insert(.layerMaxXMaxYCorner) }
        t.layer.maskedCorners = corners
        t.layer.cornerRadius = corners.isEmpty ? 0 : (c <= 5 ? 5 : 2)

        let a = CGFloat(tile.alpha) * tintFactor(c)
        t.tintView.alpha = a
        if a > 0.001 {
            t.tintView.backgroundColor = UIColor(red: CGFloat(tile.tint.x), green: CGFloat(tile.tint.y), blue: CGFloat(tile.tint.z), alpha: 1)
        }
    }

    private func refreshHidden(_ old: Int?) {
        for (_, l) in layers {
            if let o = old { l.tiles[o]?.alpha = 1 }
            if let h = hiddenIndex { l.tiles[h]?.alpha = 0 }
        }
    }

    /// Feltets plads på skærmen (vinduets koordinater). Ruller så feltet ses helt, hvis `reveal`.
    func screenRect(_ i: Int, reveal: Bool) -> CGRect? {
        guard i >= 0, i < count(), bounds.width > 0, !pinching else { return nil }
        let f = frameFor(i, cols: cols)
        if reveal {
            let top = contentOffset.y + safe.top + 100, bot = contentOffset.y + bounds.height - bottomInset - 10
            var y = contentOffset.y
            if f.minY < top { y -= top - f.minY } else if f.maxY > bot { y += f.maxY - bot }
            y = min(maxOffsetY, max(-contentInset.top, y))
            if y != contentOffset.y { contentOffset.y = y; layoutIfNeeded() }
        }
        return main.convert(f, to: nil)
    }

    private var lastReport = (-2, false, 0)
    private func report() {
        guard bounds.width > 0, !animating, !pinching else { return }
        let p = pitch(cols)
        let y = contentOffset.y + safe.top + 60
        let row = max(0, Int(y / p))
        let top = min(max(0, count() - 1), row * cols)
        let atBottom = contentOffset.y >= maxOffsetY - p * 1.5
        if (top, atBottom, cols) != lastReport {
            lastReport = (top, atBottom, cols)
            onInfo(top, atBottom, cols)
        }
    }

    // MARK: Tryk

    @objc private func onTapGesture(_ g: UITapGestureRecognizer) {
        guard !animating, !pinching else { return }
        let pt = g.location(in: main)
        let p = pitch(cols)
        guard pt.x >= 0, pt.y >= 0 else { return }
        let i = Int(pt.y / p) * cols + min(cols - 1, Int(pt.x / p))
        if i < count() { onTap(i) }
    }

    // MARK: Knib
    //
    // Som i Fotos fylder gitteret hele tiden bredden: under knibet vises de to nærmeste niveauer oven i
    // hinanden, hver skaleret så de har `e` kolonner på skærmen, og der tones mellem dem.
    // Det grovere niveau ligger øverst og tones ud/ind; feltet under fingeren følger fingeren.

    private func anchorY(_ c: Int) -> CGFloat {
        let p = pitch(c)
        return (CGFloat(anchorIndex / c) + anchorFY) * p
    }

    @objc private func onPinch(_ g: UIPinchGestureRecognizer) {
        switch g.state {
        case .began:
            guard !animating, g.numberOfTouches >= 2, count() > 0 else { return }
            pinching = true
            pinchStartCols = cols
            setContentOffset(contentOffset, animated: false)   // stop evt. glid
            isScrollEnabled = false
            pinchP = g.location(in: self)
            let a = main.convert(pinchP, from: self)
            let p = pitch(cols)
            let r = max(0, Int(a.y / p)), c = min(cols - 1, max(0, Int(a.x / p)))
            anchorIndex = min(count() - 1, r * cols + c)
            anchorFY = min(1, max(0, a.y / p - CGFloat(anchorIndex / cols)))
            anchorX = a.x
            pinchE = CGFloat(cols)
            layoutPills()
        case .changed:
            guard pinching else { return }
            if g.numberOfTouches >= 2 { pinchP = g.location(in: self) }
            var e = CGFloat(pinchStartCols) / max(0.05, g.scale)
            // modstand i yderpunkterne
            let lo = CGFloat(levels.first ?? 3), hi = CGFloat(levels.last ?? 30)
            if e < lo { e = lo * pow(e / lo, 0.25) }
            if e > hi { e = hi * pow(e / hi, 0.25) }
            pinchE = e
            render(e: e, p: pinchP)
        case .ended, .cancelled, .failed:
            guard pinching else { return }
            finishPinch(velocity: g.velocity)
        default: break
        }
    }

    /// De to niveauer omkring `e` (grov, fin)
    private func bracket(_ e: CGFloat) -> (Int, Int) {
        let lo = levels.first ?? 3, hi = levels.last ?? 30
        if e <= CGFloat(lo) { return (lo, lo) }
        if e >= CGFloat(hi) { return (hi, hi) }
        let c = levels.last(where: { CGFloat($0) <= e }) ?? lo
        let d = levels.first(where: { CGFloat($0) >= e }) ?? hi
        return (c, d)
    }

    private func origin(_ c: Int, e: CGFloat, p: CGPoint) -> CGPoint {
        let s = CGFloat(c) / e
        return CGPoint(x: p.x - s * anchorX, y: p.y - s * anchorY(c))
    }

    private func render(e: CGFloat, p: CGPoint) {
        let (c, d) = bracket(e)
        for k in Array(layers.keys) where k != c && k != d { dropLayer(k) }
        let w = c == d ? 1 : log(CGFloat(d) / e) / log(CGFloat(d) / CGFloat(c))   // det grove lags styrke
        for k in Set([c, d]) {
            let l = layer(k)
            let s = CGFloat(k) / e
            let o = origin(k, e: e, p: p)
            l.place(scale: s, origin: o)
            l.alpha = k == c ? min(1, max(0, w)) : 1
            if k == c && c != d { bringSubviewToFront(l) }
            let vis = CGRect(x: (bounds.minX - o.x) / s, y: (bounds.minY - o.y) / s,
                             width: bounds.width / s, height: bounds.height / s)
            fill(l, rect: vis.insetBy(dx: 0, dy: -pitch(k)))
        }
    }

    private func finishPinch(velocity v: CGFloat) {
        pinching = false
        let e = pinchE
        let (c, d) = bracket(e)
        var f: Int
        if c == d { f = c }
        else {
            let t = log(e / CGFloat(c)) / log(CGFloat(d) / CGFloat(c))     // 0 = grov, 1 = fin
            if v < -0.6 { f = d } else if v > 0.6 { f = c } else { f = t > 0.5 ? d : c }
        }
        let oldOffset = contentOffset
        // slutposition: fuld bredde, ankerrækken bliver under fingeren så vidt muligt
        let oy = pinchP.y - anchorY(f)
        var newY = oldOffset.y - oy
        newY = min(maxOffset(f), max(-topInset(f), newY))
        let pEnd = CGPoint(x: anchorX, y: oldOffset.y - newY + anchorY(f))
        let eEnd = CGFloat(f)

        // sørg for at slutlaget har felter nok
        let fl = layer(f)
        let endVis = CGRect(x: 0, y: newY, width: bounds.width, height: bounds.height)
        let have = fl.tiles.keys
        let need = range(cols: f, rect: endVis.insetBy(dx: 0, dy: -pitch(f)))
        if need.contains(where: { !have.contains($0) }) {
            // tilføj uden at fjerne dem der ses nu
            UIView.performWithoutAnimation {
                for i in need where fl.tiles[i] == nil {
                    let t = dequeue(into: fl)
                    t.index = i
                    t.frame = frameFor(i, cols: f)
                    configure(t, i, cols: f)
                    fl.tiles[i] = t
                }
            }
        }

        animating = true
        UIView.animate(withDuration: 0.38, delay: 0, usingSpringWithDamping: 0.92, initialSpringVelocity: 0,
                       options: [.allowUserInteraction, .beginFromCurrentState]) {
            for (k, l) in self.layers {
                l.place(scale: CGFloat(k) / eEnd, origin: self.origin(k, e: eEnd, p: pEnd))
                l.alpha = k == f ? 1 : 0
            }
        } completion: { _ in
            for k in Array(self.layers.keys) where k != f { self.dropLayer(k) }
            self.cols = f
            self.applyGeometry()
            self.contentOffset = CGPoint(x: 0, y: newY)
            self.animating = false
            self.isScrollEnabled = true
            self.layoutTiles()
            self.layoutPills()
            self.report()
        }
    }
}

/// SwiftUI-indpakning
struct LibraryGrid: UIViewRepresentable {
    @Environment(AppState.self) private var app

    func makeUIView(context: Context) -> GridView {
        let g = GridView(frame: .zero)
        let app = self.app
        g.count = { [unowned app] in app.tiles.count }
        g.tileAt = { [unowned app] i in i < app.tiles.count ? app.tiles[i] : Tile(src: 0) }
        g.onTap = { [unowned app] i in app.viewerIndex = i }
        g.onInfo = { [unowned app] top, bottom, cols in app.gridInfo(topIndex: top, atBottom: bottom, cols: cols) }
        g.dateAt = { [unowned app] i in i < app.dates.count ? app.dates[i] : nil }
        app.visibleItems = { [weak g] in g?.visibleIndices() ?? [] }
        app.tileRect = { [weak g] i, reveal in g?.screenRect(i, reveal: reveal) }
        g.setLevels(app.levels)
        g.rev = app.rev
        return g
    }

    func updateUIView(_ g: GridView, context: Context) {
        let lv = app.levels
        if g.levels != lv { g.setLevels(lv) }
        g.hiddenIndex = app.heroHidden
        if g.rev != app.rev {
            g.rev = app.rev
            g.reloadAll(keepPosition: true)
        }
    }
}

/// Mørkt mærke med måned/år øverst til venstre i gitteret
final class DatePill: UIView {
    static let height: CGFloat = 27
    private let label = UILabel()
    private(set) var width: CGFloat = 60

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(white: 0.07, alpha: 0.78)
        layer.cornerRadius = 10
        layer.cornerCurve = .continuous
        isUserInteractionEnabled = false
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError() }

    func set(_ text: NSAttributedString) {
        if label.attributedText != text {
            label.attributedText = text
            label.sizeToFit()
        }
        width = ceil(label.bounds.width) + 22
        label.frame = CGRect(x: 11, y: (Self.height - label.bounds.height) / 2, width: ceil(label.bounds.width), height: label.bounds.height)
    }
}
