import AppKit
import SwiftUI

/// SwiftUI keeps one Settings window and only hides it on close, so it would reopen on the screen and
/// desktop it was first shown on. This brings it to the main window's desktop and screen each time it opens.
struct OpensBesideMainWindow: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowTracker { WindowTracker() }
    func updateNSView(_ nsView: WindowTracker, context: Context) {}

    final class WindowTracker: NSView {
        private var observer: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            guard let window else { return }
            window.collectionBehavior.insert(.moveToActiveSpace)
            Self.place(window)
            // The window is hidden, not closed, so later openings arrive as occlusion changes.
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
            ) { [weak window] _ in
                MainActor.assumeIsolated {
                    guard let window, window.occlusionState.contains(.visible) else { return }
                    Self.place(window)
                }
            }
        }

        /// Moves the window onto the main window's screen when it is on another one; otherwise leaves it where the user put it.
        private static func place(_ window: NSWindow) {
            guard let main = NSApp.windows.first(where: { $0 !== window && $0.isVisible && $0.canBecomeMain }),
                  let target = main.screen, window.screen != target else { return }
            let area = target.visibleFrame
            let origin = NSPoint(x: area.midX - window.frame.width / 2, y: area.midY - window.frame.height / 2)
            window.setFrameOrigin(origin)
        }
    }
}
