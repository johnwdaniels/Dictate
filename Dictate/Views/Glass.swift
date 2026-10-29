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
}
