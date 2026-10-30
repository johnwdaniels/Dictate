import SwiftUI

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

    /// A grouped form whose own background is cleared, so the window's glass shows through between the sections.
    func glassForm() -> some View {
        formStyle(.grouped)
            .scrollContentBackground(.hidden)
    }

    /// See-through window: the desktop blurs through behind every page. macOS 15 and later.
    @ViewBuilder
    func glassWindow() -> some View {
        if #available(macOS 15, *) {
            containerBackground(.ultraThinMaterial, for: .window)
        } else {
            self
        }
    }

    /// A secondary button that reads as a button at a glance: clear glass on macOS 26 and later, bordered before that.
    @ViewBuilder
    func glassButton() -> some View {
        if #available(macOS 26, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
    }
}
