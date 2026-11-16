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

final class GridView: UIScrollView {
    let content = UIView()
    var count: () -> Int = { 0 }
    var tileAt: (Int) -> Tile = { _ in Tile(src: 0) }
    var onTap: (Int) -> Void = { _ in }
    var onInfo: (Int, Bool, Int) -> Void = { _, _, _ in }

    private(set) var levels = [3, 5, 9, 15, 24, 36]
    private(set) var cols = 3
    var rev = -1

    private var tiles: [Int: TileView] = [:]
    private var spare: [TileView] = []
    private var animating = false
    private var lastWidth: CGFloat = 0
    private var didScrollToBottom = false

    // knib
    private var pinching = false
    private var pinchStartCols = 3
    private var a0 = CGPoint.zero
    private var lastScale: CGFloat = 1
    private var lastPoint = CGPoint.zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .systemBackground
        contentInsetAdjustmentBehavior = .never
        alwaysBounceVertical = true
        showsHorizontalScrollIndicator = false
        addSubview(content)
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(onPinch(_:)))
        addGestureRecognizer(pinch)
        let tap = UITapGestureRecognizer(target: self, action: #selector(onTapGesture(_:)))
        addGestureRecognizer(tap)
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: Geometri

    private var safe: UIEdgeInsets { window?.safeAreaInsets ?? UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0) }
    private var scale: CGFloat { max(1, traitCollection.displayScale) }

    func gap(_ c: Int) -> CGFloat { c <= 5 ? 2 : (c <= 9 ? 1 : 2 / scale) }
    func pitch(_ c: Int) -> CGFloat { (bounds.width + gap(c)) / CGFloat(c) }
    func frameFor(_ i: Int, cols c: Int) -> CGRect {
        let p = pitch(c), g = gap(c)
        return CGRect(x: CGFloat(i % c) * p, y: CGFloat(i / c) * p, width: p - g, height: p - g)
    }
    func contentHeight(_ c: Int) -> CGFloat {
        let rows = (count() + c - 1) / c
        return max(0, CGFloat(rows) * pitch(c) - gap(c))
    }
    private var bottomInset: CGFloat { safe.bottom }
    private func topInset(_ c: Int) -> CGFloat { max(safe.top + 58, bounds.height - bottomInset - contentHeight(c)) }
    private var maxOffsetY: CGFloat { max(-contentInset.top, contentSize.height + contentInset.bottom - bounds.height) }

    private func applyGeometry() {
        let h = contentHeight(cols)
        content.bounds = CGRect(x: 0, y: 0, width: bounds.width, height: h)
        content.center = CGPoint(x: bounds.width / 2, y: h / 2)
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
        if !levels.contains(cols) { cols = levels.min(by: { abs($0 - cols) < abs($1 - cols) }) ?? 3 }
        reloadAll(keepPosition: false)
    }

    /// Ny data (fx en mosaik): opdatér felterne. Antal ændret = start forfra nederst.
    func reloadAll(keepPosition: Bool) {
        let n = count()
        let h = contentHeight(cols)
        if !keepPosition || abs(h - contentSize.height) > 0.5 {
            for (_, t) in tiles { recycle(t) }
            tiles.removeAll()
            applyGeometry()
            if n > 0 && bounds.width > 0 { scrollToBottom(); didScrollToBottom = true }
        }
        for (i, t) in tiles {
            if i >= n { continue }
            configure(t, i)
        }
        setNeedsLayout()
    }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.width != lastWidth && bounds.width > 0 {
            lastWidth = bounds.width
            applyGeometry()
            if !didScrollToBottom && count() > 0 { scrollToBottom(); didScrollToBottom = true }
        }
        layoutTiles()
        report()
    }

    private func range(cols c: Int, rect: CGRect) -> Range<Int> {
        let p = pitch(c), n = count()
        let r0 = max(0, Int(floor(rect.minY / p)))
        let r1 = max(r0, Int(ceil(rect.maxY / p)))
        let lo = min(n, r0 * c), hi = min(n, (r1 + 1) * c)
        return lo..<max(lo, hi)
    }

    private func visibleRect() -> CGRect {
        content.convert(bounds, from: self).insetBy(dx: 0, dy: -pitch(cols))
    }

    func visibleIndices() -> [Int] {
        let r = range(cols: cols, rect: content.convert(bounds, from: self))
        return Array(r)
    }

    private func layoutTiles() {
        guard !animating, bounds.width > 0 else { return }
        let r = range(cols: cols, rect: visibleRect())
        for i in Array(tiles.keys) where !r.contains(i) {
            if let t = tiles.removeValue(forKey: i) { recycle(t) }
        }
        UIView.performWithoutAnimation {
            for i in r where tiles[i] == nil {
                let t = dequeue()
                t.index = i
                t.frame = frameFor(i, cols: cols)
                configure(t, i)
                tiles[i] = t
            }
        }
    }

    private func dequeue() -> TileView {
        if let t = spare.popLast() { t.isHidden = false; t.alpha = 1; return t }
        let t = TileView(frame: .zero)
        content.addSubview(t)
        return t
    }

    private func recycle(_ t: TileView) {
        t.isHidden = true
        t.index = -1
        t.layer.removeAllAnimations()
        spare.append(t)
    }

    func tintFactor(_ c: Int) -> CGFloat {
        let lo: CGFloat = 9, hi = CGFloat(levels.last ?? 36)
        guard CGFloat(c) > lo, hi > lo else { return 0 }
        return pow(min(1, (CGFloat(c) - lo) / (hi - lo)), 1.4)
    }

    private func configure(_ t: TileView, _ i: Int) {
        let tile = tileAt(i)
        let wantBig = pitch(cols) * scale > 110
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
        let a = CGFloat(tile.alpha) * tintFactor(cols)
        t.tintView.alpha = a
        if a > 0.001 {
            t.tintView.backgroundColor = UIColor(red: CGFloat(tile.tint.x), green: CGFloat(tile.tint.y), blue: CGFloat(tile.tint.z), alpha: 1)
        }
    }

    private var lastReport = (-2, false, 0)
    private func report() {
        guard bounds.width > 0, !animating else { return }
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
        let pt = g.location(in: content)
        let p = pitch(cols)
        guard pt.x >= 0, pt.y >= 0 else { return }
        let i = Int(pt.y / p) * cols + min(cols - 1, Int(pt.x / p))
        if i < count() { onTap(i) }
    }

    // MARK: Knib

    private func transformFor(scale s: CGFloat, point p: CGPoint) -> CGAffineTransform {
        let bc = CGPoint(x: content.bounds.midX, y: content.bounds.midY)
        return CGAffineTransform(a: s, b: 0, c: 0, d: s,
                                 tx: p.x - bc.x - s * (a0.x - bc.x),
                                 ty: p.y - bc.y - s * (a0.y - bc.y))
    }

    @objc private func onPinch(_ g: UIPinchGestureRecognizer) {
        switch g.state {
        case .began:
            guard !animating, g.numberOfTouches >= 2 else { return }
            pinching = true
            pinchStartCols = cols
            setContentOffset(contentOffset, animated: false)   // stop evt. glid
            isScrollEnabled = false
            lastPoint = g.location(in: self)
            a0 = content.convert(lastPoint, from: self)
            lastScale = 1
        case .changed:
            guard pinching else { return }
            let atMax = cols == levels.last, atMin = cols == levels.first
            var s = g.scale
            // modstand i yderpunkterne
            if atMax && s < 1 { s = 1 - (1 - s) * 0.25 }
            if atMin && s > 1 { s = 1 + (s - 1) * 0.25 }
            s = min(4, max(0.25, s))
            if g.numberOfTouches >= 2 { lastPoint = g.location(in: self) }
            lastScale = s
            content.transform = transformFor(scale: s, point: lastPoint)
            layoutTiles()
        case .ended, .cancelled, .failed:
            guard pinching else { return }
            pinching = false
            isScrollEnabled = true
            finishPinch(scale: lastScale, point: lastPoint, velocity: g.velocity)
        default: break
        }
    }

    private func finishPinch(scale s: CGFloat, point p: CGPoint, velocity: CGFloat) {
        let eff = Double(pinchStartCols) / Double(s)
        let startIdx = levels.firstIndex(of: pinchStartCols) ?? 0
        var idx = levels.indices.min(by: { abs(log(Double(levels[$0])) - log(eff)) < abs(log(Double(levels[$1])) - log(eff)) }) ?? startIdx
        if idx == startIdx {
            if s > 1.1 || velocity > 1.5 { idx = max(0, startIdx - 1) }
            else if s < 0.9 || velocity < -1.5 { idx = min(levels.count - 1, startIdx + 1) }
        }
        transition(to: levels[idx], scale: s, point: p)
    }

    /// Skift antal kolonner. Felterne flyver fra hvor de ses nu til deres nye plads; fingerens felt bliver under fingeren.
    private func transition(to newCols: Int, scale s: CGFloat, point p: CGPoint) {
        let n = count()
        guard n > 0 else { content.transform = .identity; return }
        let oldCols = cols
        let oldOffset = contentOffset
        let bc = CGPoint(x: content.bounds.midX, y: content.bounds.midY)
        let T = content.transform
        // felt under fingeren (gamle layout)
        let p0 = pitch(oldCols)
        let ar = max(0, Int(a0.y / p0)), ac = min(oldCols - 1, max(0, Int(a0.x / p0)))
        let anchor = min(n - 1, ar * oldCols + ac)
        let vpY = p.y - oldOffset.y

        animating = true
        content.transform = .identity
        cols = newCols
        applyGeometry()
        let nf = frameFor(anchor, cols: newCols)
        var newY = nf.midY - vpY
        newY = min(maxOffsetY, max(-contentInset.top, newY))
        contentOffset = CGPoint(x: 0, y: newY)
        let dy = newY - oldOffset.y

        func from(_ i: Int) -> CGRect {
            let f = frameFor(i, cols: oldCols)
            let ox = bc.x + T.a * (f.minX - bc.x) + T.tx
            let oy = bc.y + T.d * (f.minY - bc.y) + T.ty
            return CGRect(x: ox, y: oy + dy, width: f.width * T.a, height: f.height * T.d)
        }

        let newRange = range(cols: newCols, rect: content.convert(bounds, from: self).insetBy(dx: 0, dy: -pitch(newCols)))
        UIView.performWithoutAnimation {
            for (i, t) in tiles { t.frame = from(i) }
            for i in newRange where tiles[i] == nil {
                let t = dequeue()
                t.index = i
                t.frame = from(i)
                configure(t, i)
                tiles[i] = t
            }
        }
        let fac = tintFactor(newCols)
        UIView.animate(withDuration: 0.44, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0,
                       options: [.allowUserInteraction, .beginFromCurrentState]) {
            for (i, t) in self.tiles {
                t.frame = self.frameFor(i, cols: newCols)
                t.tintView.alpha = CGFloat(self.tileAt(i).alpha) * fac
            }
        } completion: { _ in
            self.animating = false
            for (i, t) in self.tiles where newRange.contains(i) { self.configure(t, i) }
            self.layoutTiles()
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
        app.visibleItems = { [weak g] in g?.visibleIndices() ?? [] }
        g.setLevels(app.levels)
        g.rev = app.rev
        return g
    }

    func updateUIView(_ g: GridView, context: Context) {
        let lv = app.levels
        if g.levels != lv { g.setLevels(lv) }
        if g.rev != app.rev {
            g.rev = app.rev
            g.reloadAll(keepPosition: true)
        }
    }
}
