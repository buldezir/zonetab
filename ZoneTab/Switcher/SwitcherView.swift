import SwiftUI

final class SwitcherViewModel: ObservableObject {
    @Published var items: [SwitcherItem] = []
    @Published var selection = 0
    @Published var iconSize: CGFloat = 80
    /// Each item's tile, in `SwitcherView.coordinateSpace` (the view's own top-left-origin coordinates), for
    /// finding the app under the mouse. Not published: nothing in the view depends on it.
    var itemFrames: [pid_t: CGRect] = [:]

    /// The index of the item at `point`, in `SwitcherView.coordinateSpace`.
    func item(at point: CGPoint) -> Int? {
        items.firstIndex { itemFrames[$0.pid]?.contains(point) ?? false }
    }
}

struct SwitcherView: View {
    nonisolated static let coordinateSpace = "switcher"

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
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.coordinateSpace)) } action: { frame in
                            model.itemFrames[item.pid] = frame
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
        .coordinateSpace(.named(Self.coordinateSpace))
    }
}
