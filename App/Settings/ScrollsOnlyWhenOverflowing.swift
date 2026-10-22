import SwiftUI

/// Grouped forms and lists rubber-band on a trackpad even when everything fits, so the page seems to drift.
/// Scrolling stays off until the content is taller than the space it has.
private struct ScrollsOnlyWhenOverflowing: ViewModifier {
    @State private var overflows = false

    func body(content: Content) -> some View {
        content
            // The container already excludes the toolbar inset, so adding the inset again makes a page that just fits scroll.
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentSize.height > geometry.containerSize.height + 0.5
            } action: { _, newValue in
                overflows = newValue
            }
            .scrollDisabled(!overflows)
    }
}

extension View {
    func scrollsOnlyWhenOverflowing() -> some View {
        modifier(ScrollsOnlyWhenOverflowing())
    }
}
