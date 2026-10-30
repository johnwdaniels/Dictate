import SwiftUI

/// Settings section that picks the app icon.
struct AppIconSection: View {
    @AppStorage(AppIconChoice.storageKey) private var selection = AppIconChoice.fallback.rawValue

    var body: some View {
        Section("App icon") {
            // Three across, so each icon family sits on its own row.
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .top), count: 3), spacing: 14) {
                ForEach(AppIconChoice.allCases) { choice in
                    IconTile(choice: choice, isSelected: choice.rawValue == current.rawValue) {
                        selection = choice.rawValue
                        choice.apply()
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var current: AppIconChoice {
        AppIconChoice(rawValue: selection) ?? AppIconChoice.fallback
    }
}

private struct IconTile: View {
    let choice: AppIconChoice
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(spacing: 6) {
                Image(choice.imageName)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 64, height: 64)
                    .padding(4)
                    .background {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2.5)
                    }
                Text(choice.title)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(choice.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
