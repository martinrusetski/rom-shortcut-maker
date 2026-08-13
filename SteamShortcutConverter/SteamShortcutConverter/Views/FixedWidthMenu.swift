import SwiftUI

/// A menu whose visible face has deterministic geometry. Native macOS menu
/// buttons size themselves from their current title, so rows with short and
/// long values otherwise produce mismatched control widths.
struct FixedWidthMenu<MenuContent: View>: View {
    let title: String
    let width: CGFloat
    let accessibilityLabel: String
    @ViewBuilder let menuContent: () -> MenuContent

    init(
        title: String,
        width: CGFloat,
        accessibilityLabel: String,
        @ViewBuilder menuContent: @escaping () -> MenuContent
    ) {
        self.title = title
        self.width = width
        self.accessibilityLabel = accessibilityLabel
        self.menuContent = menuContent
    }

    var body: some View {
        ZStack {
            Menu(content: menuContent) {
                Color.clear
                    .frame(width: width, height: 24)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .accessibilityLabel(accessibilityLabel)

            HStack(spacing: 6) {
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 4)

                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 9)
            .frame(width: width, height: 24)
            .background(
                Color.primary.opacity(0.075),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}
