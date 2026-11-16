// Bibliotek-skærmen: gitteret + titel/knapper øverst og glas-fanebjælken nederst (iOS 26 Fotos).
import SwiftUI

struct LibraryScreen: View {
    @Environment(AppState.self) private var app
    @State private var selecting = false
    @State private var taps: [Date] = []

    var body: some View {
        ZStack {
            LibraryGrid().ignoresSafeArea()
            VStack(spacing: 0) {
                EdgeFade(top: true, height: 150).ignoresSafeArea(edges: .top)
                Spacer()
                EdgeFade(top: false, height: 110).ignoresSafeArea(edges: .bottom)
            }
            .ignoresSafeArea()
            VStack(spacing: 0) {
                header
                Spacer()
                tabBar
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Bibliotek")
                    .font(.system(size: 34, weight: .bold))
                    .contentShape(Rectangle())
                    .onTapGesture { secretTap() }
                Text(app.subtitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.75))
                    .contentTransition(.numericText())
            }
            .shadow(color: .black.opacity(0.25), radius: 6, y: 1)
            Spacer()
            HStack(spacing: 10) {
                Menu {
                    Section("Sortér efter") {
                        Button("Seneste tilføjede") {}
                        Button { } label: { Label("Optagelsesdato", systemImage: "checkmark") }
                    }
                    Section {
                        Button { } label: { Label("Filtrér", systemImage: "line.3.horizontal.decrease.circle") }
                        Button { } label: { Label("Vis kortlayout", systemImage: "square.grid.2x2") }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .glass(Circle())
                Button { withAnimation(.snappy) { selecting.toggle() } } label: {
                    Text(selecting ? "Annuller" : "Vælg")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 16)
                        .frame(height: 44)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .glass(Capsule())
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    private var tabBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 18, weight: .semibold))
                Text("Bibliotek")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 26)
            .frame(height: 56)
            .frame(maxWidth: .infinity)
            .glass(Capsule())
            .overlay(alignment: .topTrailing) {
                if app.badge {
                    Text("1")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(minWidth: 20, minHeight: 20)
                        .background(Circle().fill(Color.red))
                        .offset(x: -14, y: -3)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .onTapGesture { withAnimation { app.badge = false } }
            GlassCircle(icon: "square.stack.fill", size: 56, iconSize: 19, color: .secondary)
            GlassCircle(icon: "magnifyingglass", size: 56, iconSize: 19, color: .primary)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 2)
        .animation(.spring(duration: 0.35), value: app.badge)
    }

    /// 5 hurtige tryk på titlen = hemmeligt panel
    private func secretTap() {
        let now = Date()
        taps = taps.filter { now.timeIntervalSince($0) < 2.5 } + [now]
        if taps.count >= 5 {
            taps = []
            app.secretOpen = true
        }
    }
}
