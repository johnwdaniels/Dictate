import SwiftUI

extension View {
    /// Liquid Glass on macOS 26 and later. Older systems keep a flat fill with a hairline edge.
    @ViewBuilder
    func dictateGlass<S: InsettableShape>(in shape: S, tint: Color? = nil, fallback: Color, edge: Color) -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular.tint(tint), in: shape)
        } else {
            background(fallback, in: shape)
                .overlay { shape.strokeBorder(edge, lineWidth: 1) }
        }
    }
}

extension View {
    /// The one main action on a page: tinted glass on macOS 26 and later, the filled accent button before that.
    @ViewBuilder
    func prominentButton() -> some View {
        if #available(macOS 26, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }
}
