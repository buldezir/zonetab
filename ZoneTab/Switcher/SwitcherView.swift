import SwiftUI

final class SwitcherViewModel: ObservableObject {
    @Published var items: [SwitcherItem] = []
    @Published var selection = 0
    @Published var iconSize: CGFloat = 80
}

struct SwitcherView: View {
    @ObservedObject var model: SwitcherViewModel

    private var selectedName: String {
        model.items.indices.contains(model.selection) ? model.items[model.selection].name : ""
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                    Image(nsImage: item.icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: model.iconSize, height: model.iconSize)
                        .opacity(item.isHidden ? 0.45 : 1)
                        .padding(8)
                        .background {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(index == model.selection ? Color.primary.opacity(0.16) : .clear)
                        }
                }
            }
            Text(selectedName)
                .font(.system(size: 15, weight: .medium))
                .lineLimit(1)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
        .fixedSize()
    }
}
