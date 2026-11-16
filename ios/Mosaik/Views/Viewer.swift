// Fremviseren (som Fotos i iOS 26): zoomer ud af feltet i gitteret og tilbage igen, bladr mellem billeder,
// træk ned for at lukke, tryk for at skjule knapperne. Miniaturebånd nederst, LIVE-mærke på Live Photos.
import SwiftUI

struct ViewerView: View {
    @Environment(AppState.self) private var app
    let start: Int
    @State private var current: Int?
    @State private var chrome = true
    @State private var drag: CGSize = .zero
    @State private var liked: Set<Int> = []
    /// zoom-billedet mellem feltet og fremviseren (nil = siderne vises)
    @State private var hero: CGRect?
    @State private var heroSrc: Int32 = 0
    @State private var bgOpacity: Double = 0
    @State private var closing = false

    init(start: Int) {
        self.start = start
        _current = State(initialValue: start)
    }

    private var idx: Int { min(max(0, current ?? start), max(0, app.tiles.count - 1)) }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let progress = min(1, max(0, drag.height) / 300)
            ZStack {
                Color.black.opacity(bgOpacity * (1 - progress * 0.95))

                if hero == nil && !closing {
                    pager
                        .scaleEffect(1 - progress * 0.3)
                        .offset(drag)
                        .simultaneousGesture(dismissDrag(size))
                        .onTapGesture { withAnimation(.easeOut(duration: 0.18)) { chrome.toggle() } }
                }

                if let r = hero, let img = ImageStore.shared.big(heroSrc) ?? ImageStore.shared.small(heroSrc) {
                    Image(decorative: img, scale: 1).resizable().scaledToFill()
                        .frame(width: r.width, height: r.height)
                        .clipped()
                        .position(x: r.midX, y: r.midY)
                        .allowsHitTesting(false)
                }

                if chrome && hero == nil && !closing && drag == .zero {
                    controls.transition(.opacity)
                }
            }
            .frame(width: size.width, height: size.height)
            .onAppear { open(size) }
        }
        .ignoresSafeArea()
        .statusBarHidden(!chrome)
    }

    // MARK: Sider

    private var pager: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(0..<app.tiles.count, id: \.self) { i in
                        ViewerPage(index: i)
                            .containerRelativeFrame([.horizontal, .vertical])
                            .id(i)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $current)
            .scrollIndicators(.hidden)
            .onAppear { proxy.scrollTo(current ?? start) }
            .onChange(of: current) { _, v in if let v { app.heroHidden = v } }
        }
    }

    private func dismissDrag(_ size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { v in
                if drag != .zero || (v.translation.height > 0 && abs(v.translation.height) > abs(v.translation.width) * 1.2) {
                    drag = v.translation
                }
            }
            .onEnded { v in
                guard drag != .zero else { return }
                if drag.height > 90 || (v.predictedEndTranslation.height > 350 && drag.height > 25) { close(size) }
                else { withAnimation(.spring(duration: 0.3)) { drag = .zero } }
            }
    }

    // MARK: Zoom ind/ud

    private func fitted(_ src: Int32, _ size: CGSize) -> CGRect {
        let a = max(0.2, ImageStore.shared.aspect(src))
        let w = min(size.width, size.height * a), h = w / a
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }

    private func open(_ size: CGSize) {
        let src = app.tiles.indices.contains(start) ? app.tiles[start].src : 0
        heroSrc = src
        let end = fitted(src, size)
        guard let from = app.tileRect(start, false) else {
            hero = nil
            withAnimation(.easeOut(duration: 0.2)) { bgOpacity = 1 }
            app.heroHidden = start
            return
        }
        hero = from
        app.heroHidden = start
        withAnimation(.spring(duration: 0.38, bounce: 0.12)) {
            hero = end
            bgOpacity = 1
        } completion: {
            hero = nil
        }
    }

    private func close(_ size: CGSize) {
        guard !closing else { return }
        let i = idx
        let src = app.tiles.indices.contains(i) ? app.tiles[i].src : 0
        heroSrc = src
        // hvor billedet ses nu (efter træk og formindskelse)
        let f = fitted(src, size)
        let k = 1 - min(1, max(0, drag.height) / 300) * 0.3
        let now = CGRect(x: size.width / 2 + (f.midX - size.width / 2) * k + drag.width - f.width * k / 2,
                         y: size.height / 2 + (f.midY - size.height / 2) * k + drag.height - f.height * k / 2,
                         width: f.width * k, height: f.height * k)
        app.heroHidden = i
        let to = app.tileRect(i, true)
        closing = true
        hero = now
        drag = .zero
        withAnimation(.spring(duration: 0.36, bounce: 0.08)) {
            if let to { hero = to } else { hero = now.insetBy(dx: now.width * 0.1, dy: now.height * 0.1) }
            bgOpacity = 0
        } completion: {
            app.heroHidden = nil
            app.viewerIndex = nil
        }
    }

    // MARK: Knapper

    private var controls: some View {
        let safe = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.keyWindow?.safeAreaInsets ?? UIEdgeInsets(top: 62, left: 0, bottom: 34, right: 0)
        return VStack(spacing: 0) {
            topBar
            badges.padding(.top, 24)
            Spacer()
            Scrubber(index: idx) { i in current = i }
                .frame(height: 31)
                .padding(.bottom, 20)
            bottomBar
        }
        .padding(.top, max(20, safe.top - 1))
        .padding(.bottom, max(16, safe.bottom - 2))
    }

    private var topBar: some View {
        let (title, time) = app.dates.isEmpty ? ("", "") : Dates.viewer(app.dates[min(idx, app.dates.count - 1)])
        return HStack {
            GlassCircle(icon: "chevron.left", size: 44, iconSize: 19) { close(UIScreen.main.bounds.size) }
            Spacer()
            VStack(spacing: 1) {
                Text(title).font(.system(size: 17, weight: .semibold))
                Text(time).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            }
            .frame(width: 162, height: 44)
            .glass(Capsule(), interactive: false)
            Spacer()
            GlassCircle(icon: "ellipsis", size: 44, iconSize: 18)
        }
        .padding(.horizontal, 16)
    }

    private var badges: some View {
        let live = ImageStore.shared.isLive(app.tiles.indices.contains(idx) ? app.tiles[idx].src : 0)
        return HStack {
            if live {
                HStack(spacing: 4) {
                    Image(systemName: "livephoto").font(.system(size: 13, weight: .regular))
                    Text("LIVE").font(.system(size: 13, weight: .medium))
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 9)
                .frame(height: 22)
                .glass(Capsule(), interactive: false)
            }
            Spacer()
            HStack(spacing: 3) {
                Image(systemName: "cube.transparent").font(.system(size: 13, weight: .regular))
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 8)
            .frame(height: 22)
            .glass(Capsule(), interactive: false)
        }
        .padding(.horizontal, 17)
    }

    private var bottomBar: some View {
        HStack {
            GlassCircle(icon: "square.and.arrow.up", size: 49, iconSize: 19, weight: .regular)
            Spacer()
            HStack(spacing: 0) {
                Button { if liked.contains(idx) { liked.remove(idx) } else { liked.insert(idx) } } label: {
                    Image(systemName: liked.contains(idx) ? "heart.fill" : "heart").frame(width: 50, height: 49)
                }
                Image(systemName: "info.circle").frame(width: 50, height: 49)
                Image(systemName: "slider.horizontal.3").frame(width: 50, height: 49)
            }
            .font(.system(size: 20, weight: .regular))
            .foregroundStyle(.white)
            .buttonStyle(.plain)
            .padding(.horizontal, 6)
            .glass(Capsule())
            Spacer()
            GlassCircle(icon: "trash", size: 49, iconSize: 19, weight: .regular)
        }
        .padding(.horizontal, 28)
    }
}

/// Miniaturebåndet nederst: det aktuelle billede bredere og med luft omkring, de andre smalle.
struct Scrubber: View {
    @Environment(AppState.self) private var app
    let index: Int
    var onPick: (Int) -> Void

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let narrow: CGFloat = 19, gap: CGFloat = 2, pad: CGFloat = 8
            let curW = min(h * 1.4, max(narrow, h * ImageStore.shared.aspect(src(index))))
            let cx = geo.size.width / 2
            let n = Int(geo.size.width / (narrow + gap) / 2) + 2
            ZStack(alignment: .topLeading) {
                ForEach(Array(max(0, index - n)..<max(max(0, index - n), min(app.tiles.count, index + n + 1))), id: \.self) { i in
                    let d = i - index
                    let w = d == 0 ? curW : narrow
                    let x: CGFloat = d == 0 ? cx - curW / 2
                        : d < 0 ? cx - curW / 2 - pad - CGFloat(-d) * (narrow + gap) + gap
                        : cx + curW / 2 + pad + CGFloat(d - 1) * (narrow + gap)
                    Thumb(src: src(i))
                        .frame(width: w, height: h)
                        .clipped()
                        .offset(x: x)
                        .onTapGesture { onPick(i) }
                }
            }
            .frame(width: geo.size.width, height: h, alignment: .topLeading)
            .clipped()
            .animation(.easeOut(duration: 0.2), value: index)
        }
    }

    private func src(_ i: Int) -> Int32 { app.tiles.indices.contains(i) ? app.tiles[i].src : 0 }
}

private struct Thumb: View {
    let src: Int32
    @State private var img: CGImage?
    var body: some View {
        ZStack {
            Color.white.opacity(0.08)
            if let i = img ?? ImageStore.shared.small(src) {
                Image(decorative: i, scale: 1).resizable().scaledToFill()
            }
        }
        .task(id: src) {
            if ImageStore.shared.small(src) == nil {
                img = await withCheckedContinuation { c in ImageStore.shared.load(src, big: false) { c.resume(returning: $0) } }
            }
        }
    }
}

struct ViewerPage: View {
    @Environment(AppState.self) private var app
    let index: Int
    @State private var full: CGImage?

    var body: some View {
        let src = index < app.tiles.count ? app.tiles[index].src : 0
        let aspect = ImageStore.shared.aspect(src)
        GeometryReader { geo in
            let w = min(geo.size.width, geo.size.height * aspect)
            let h = w / aspect
            ZStack {
                if let full {
                    Image(decorative: full, scale: 1).resizable().scaledToFit()
                } else if let thumb = ImageStore.shared.big(src) ?? ImageStore.shared.small(src) {
                    Image(decorative: thumb, scale: 1).resizable().scaledToFill()
                        .frame(width: w, height: h).clipped()
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .task(id: src) {
            full = nil
            let px = UIScreen.main.bounds.height * UIScreen.main.scale
            full = await ImageStore.shared.full(src, screenPx: px)
        }
    }
}
