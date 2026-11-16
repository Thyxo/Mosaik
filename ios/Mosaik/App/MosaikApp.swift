// Mosaik – falsk Fotos-app. Zoomer man helt ud i biblioteket, danner billederne forudsigelsen.
import SwiftUI

@main
struct MosaikApp: App {
    @State private var app = AppState()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .preferredColorScheme(.dark)
                .task { await app.start() }
                .onChange(of: phase) { _, p in
                    if p == .active { app.resumeRelay() } else if p == .background { app.pauseRelay() }
                }
        }
    }
}

struct RootView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var app = app
        ZStack {
            MainTabs()
            if let i = app.viewerIndex {
                ViewerView(start: i)
                    .id(i)
                    .zIndex(10)
            }
        }
        .sheet(isPresented: $app.secretOpen) { SecretPanel() }
    }
}
