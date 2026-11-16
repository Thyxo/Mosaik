// Fremviseren: bladr mellem billeder, træk ned for at lukke, tryk for at skjule knapperne.
import SwiftUI

struct ViewerView: View {
    @Environment(AppState.self) private var app
    @Environment(\.colorScheme) private var scheme
    let start: Int
    @State private var current: Int?
    @State private var chrome = true
    @State private var drag: CGFloat = 0
    @State private var liked: Set<Int> = []

    init(start: Int) {
        self.start = start
        _current = State(initialValue: start)
    }

    var body: some View {
        let bg: Color = scheme == .dark || !chrome ? .black : .white
        let progress = min(1, abs(drag) / 300)
        ZStack {
            bg.opacity(1 - progress * 0.9).ignoresSafeArea()
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
                .ignoresSafeArea()
                .onAppear { proxy.scrollTo(start) }
            }
            .scaleEffect(1 - progress * 0.25)
            .offset(y: drag)
            .simultaneousGesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { v in
                        if abs(v.translation.height) > abs(v.translation.width) * 1.2 && v.translation.height > 0 {
                            drag = v.translation.height
                        }
                    }
                    .onEnded { v in
                        if drag > 110 || v.predictedEndTranslation.height > 400 && drag > 30 { close() }
                        else { withAnimation(.spring(duration: 0.3)) { drag = 0 } }
                    }
            )
            .onTapGesture { withAnimation(.easeOut(duration: 0.18)) { chrome.toggle() } }

            if chrome && drag == 0 {
                VStack {
                    topBar
                    Spacer()
                    bottomBar
                }
                .transition(.opacity)
            }
        }
        .statusBarHidden(!chrome)
    }

    private var idx: Int { min(max(0, current ?? start), max(0, app.dates.count - 1)) }

    private var topBar: some View {
        let (title, time) = app.dates.isEmpty ? ("", "") : Dates.viewer(app.dates[idx])
        return HStack {
            GlassCircle(icon: "chevron.left", size: 44, iconSize: 18) { close() }
            Spacer()
            VStack(spacing: 0) {
                Text(title).font(.system(size: 16, weight: .semibold))
                Text(time).font(.system(size: 12, weight: .regular)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            .glass(Capsule(), interactive: false)
            Spacer()
            GlassCircle(icon: "ellipsis", size: 44, iconSize: 17)
        }
        .padding(.horizontal, 16)
    }

    private var bottomBar: some View {
        HStack {
            GlassCircle(icon: "square.and.arrow.up", size: 50, iconSize: 18)
            Spacer()
            HStack(spacing: 30) {
                Button { if liked.contains(idx) { liked.remove(idx) } else { liked.insert(idx) } } label: {
                    Image(systemName: liked.contains(idx) ? "heart.fill" : "heart")
                }
                Image(systemName: "info.circle")
                Image(systemName: "slider.horizontal.3")
            }
            .font(.system(size: 19, weight: .medium))
            .foregroundStyle(.primary)
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .frame(height: 50)
            .glass(Capsule())
            Spacer()
            GlassCircle(icon: "trash", size: 50, iconSize: 18)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    private func close() {
        withAnimation(.easeOut(duration: 0.22)) { app.viewerIndex = nil }
        drag = 0
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
