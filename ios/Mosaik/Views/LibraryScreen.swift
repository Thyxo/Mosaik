// Fanerne (iOS' egen fanebjælke = ægte Liquid Glass på iOS 26) og Bibliotek-skærmen:
// gitteret + titel, antal (kun nederst) og glasknapperne. Mål taget fra skærmbilleder af Fotos (ref/).
import SwiftUI

struct MainTabs: View {
    @Environment(AppState.self) private var app
    @State private var tab = 0

    var body: some View {
        let (t0, t1) = app.tabTitles
        TabView(selection: $tab) {
            Tab(t0, systemImage: "photo.fill.on.rectangle.fill", value: 0) {
                LibraryScreen()
            }
            .badge(app.badge ? 1 : 0)
            Tab(t1, systemImage: "rectangle.stack.fill", value: 1) {
                CollectionsScreen()
            }
            Tab(value: 2, role: .search) {
                SearchScreen()
            }
        }
    }
}

struct LibraryScreen: View {
    @Environment(AppState.self) private var app
    @State private var selecting = false
    @State private var taps: [Date] = []

    var body: some View {
        ZStack(alignment: .top) {
            LibraryGrid().ignoresSafeArea()
            EdgeFade(top: true, height: 160).ignoresSafeArea()
            header
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Bibliotek")
                    .font(.system(size: 35, weight: .bold))
                    .foregroundStyle(.white)
                    .contentShape(Rectangle())
                    .onTapGesture { secretTap() }
                Text(app.subtitle.isEmpty ? " " : app.subtitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .opacity(app.subtitle.isEmpty ? 0 : 1)
                    .animation(.easeOut(duration: 0.2), value: app.subtitle.isEmpty)
            }
            .shadow(color: .black.opacity(0.35), radius: 8, y: 1)
            Spacer(minLength: 8)
            HStack(spacing: 12) {
                Menu {
                    Section("Sortér efter") {
                        Button("Seneste tilføjede") {}
                        Button { } label: { Label("Optagelsesdato", systemImage: "checkmark") }
                    }
                    Section {
                        Button { } label: { Label("Filtrér", systemImage: "line.3.horizontal.decrease.circle") }
                        Button { } label: { Label("Vis metadata", systemImage: "info.circle") }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .glass(Circle())
                Button { withAnimation(.snappy) { selecting.toggle() } } label: {
                    Text(selecting ? "Annuller" : "Vælg")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(minWidth: 72)
                        .frame(height: 44)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .glass(Capsule())
            }
            .padding(.top, 2)
        }
        .padding(.leading, 16)
        .padding(.trailing, 16)
        .padding(.top, 2)
    }

    /// 5 hurtige tryk på titlen = hemmeligt panel
    private func secretTap() {
        let now = Date()
        taps = taps.filter { now.timeIntervalSince($0) < 2.5 } + [now]
        if taps.count >= 5 {
            taps = []
            app.badge = false
            app.secretOpen = true
        }
    }
}

/// Samlinger: enkel udgave med album lavet af biblioteket
struct CollectionsScreen: View {
    @Environment(AppState.self) private var app
    private let albums = ["Seneste", "Favoritter", "Skærmbilleder", "Selfies", "Portrætter", "Videoer"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    section("Seneste dage") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(0..<6, id: \.self) { k in
                                    VStack(alignment: .leading, spacing: 4) {
                                        PoolThumb(src: src(k * 7 + 1)).frame(width: 150, height: 190)
                                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                        Text(k == 0 ? "I dag" : k == 1 ? "I går" : Dates.viewer(date(k * 7 + 1)).0)
                                            .font(.system(size: 15, weight: .semibold))
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                    section("Album") {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 14) {
                            ForEach(albums.indices, id: \.self) { k in
                                VStack(alignment: .leading, spacing: 3) {
                                    PoolThumb(src: src(k * 13 + 40)).aspectRatio(1, contentMode: .fit)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    Text(albums[k]).font(.system(size: 15, weight: .regular))
                                    Text(Dates.number(max(1, app.tiles.count / (k + 2)))).font(.system(size: 13)).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.bottom, 100)
            }
            .navigationTitle("Samlinger")
        }
    }

    private func src(_ fromEnd: Int) -> Int32 {
        let i = app.tiles.count - 1 - fromEnd
        return i >= 0 ? app.tiles[i].src : 0
    }
    private func date(_ fromEnd: Int) -> Date {
        let i = app.dates.count - 1 - fromEnd
        return i >= 0 ? app.dates[i] : Date()
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                Text(title).font(.system(size: 22, weight: .bold))
                Image(systemName: "chevron.right").font(.system(size: 16, weight: .semibold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            c()
        }
    }
}

/// Søg: tom søgeskærm
struct SearchScreen: View {
    @State private var text = ""
    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "magnifyingglass").font(.system(size: 44, weight: .light)).foregroundStyle(.secondary)
                Text("Søg i dine fotos").font(.system(size: 20, weight: .semibold))
                Text("Søg efter steder, personer, ting og mere.").font(.system(size: 15)).foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .navigationTitle("Søg")
            .searchable(text: $text, prompt: "Fotos, personer, steder …")
        }
    }
}

/// Lille billede fra biblioteket (SwiftUI)
struct PoolThumb: View {
    let src: Int32
    @State private var img: CGImage?
    var body: some View {
        Color.secondary.opacity(0.2)
            .overlay {
                if let img { Image(decorative: img, scale: 1).resizable().scaledToFill() }
            }
            .clipped()
            .task(id: src) {
                if let b = ImageStore.shared.big(src) { img = b; return }
                img = ImageStore.shared.small(src)
                ImageStore.shared.load(src, big: true) { i in if let i { img = i } }
            }
    }
}
