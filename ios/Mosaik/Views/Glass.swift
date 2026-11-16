// Liquid Glass (iOS 26) med materiale som reserve på ældre iOS / ældre Xcode.
import SwiftUI

struct GlassBackground<S: Shape>: ViewModifier {
    var shape: S
    var interactive = true
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.glassEffect(interactive ? Glass.regular.interactive() : Glass.regular, in: shape)
        } else {
            content.background(.ultraThinMaterial, in: shape)
        }
        #else
        content.background(.ultraThinMaterial, in: shape)
        #endif
    }
}

extension View {
    func glass<S: Shape>(_ shape: S, interactive: Bool = true) -> some View { modifier(GlassBackground(shape: shape, interactive: interactive)) }
}

/// Rund glasknap med et SF Symbol
struct GlassCircle: View {
    var icon: String
    var size: CGFloat = 44
    var iconSize: CGFloat = 17
    var weight: Font.Weight = .semibold
    var color: Color = .primary
    var action: () -> Void = {}
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: iconSize, weight: weight))
                .foregroundStyle(color)
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glass(Circle())
    }
}

/// Fade-kant øverst/nederst (som iOS 26's scroll-kant): sløring der toner ud
struct EdgeFade: View {
    var top = true
    var height: CGFloat
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let bg: Color = scheme == .dark ? .black : .white
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
                .mask(LinearGradient(colors: [.black, .black.opacity(0.6), .clear], startPoint: top ? .top : .bottom, endPoint: top ? .bottom : .top))
            LinearGradient(colors: [bg.opacity(0.55), bg.opacity(0.2), .clear], startPoint: top ? .top : .bottom, endPoint: top ? .bottom : .top)
        }
        .frame(height: height)
        .allowsHitTesting(false)
    }
}
