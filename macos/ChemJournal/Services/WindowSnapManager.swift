import AppKit
import SwiftUI

/// Lässt das Fenster beim Ziehen an der optimalen Breite (1024 pt) einrasten.
///
/// Vorher wurde `window.delegate` einfach ersetzt. Dabei ging der Delegate von SwiftUI verloren.
/// Jetzt bekommt jedes Fenster einen Proxy, der alle anderen Delegate-Aufrufe an SwiftUI weiterreicht.
final class WindowSnapManager {
    static let shared = WindowSnapManager()

    var perfectWidth: CGFloat = 1024
    var snapWidths: [CGFloat] = [1024]
    var snapTolerance: CGFloat = 20

    private var proxies: [ObjectIdentifier: SnapDelegateProxy] = [:]
    private weak var lastWindow: NSWindow?

    func attach(to window: NSWindow) {
        lastWindow = window
        let key = ObjectIdentifier(window)
        if let proxy = proxies[key], window.delegate === proxy { return }
        let proxy = SnapDelegateProxy(manager: self, original: window.delegate)
        proxies[key] = proxy   // NSWindow hält den Delegate nur schwach
        window.delegate = proxy
    }

    fileprivate func detach(_ window: NSWindow) {
        proxies[ObjectIdentifier(window)] = nil
    }

    func updateSnapWidth(_ width: CGFloat) {
        var rounded = round(width)
        if let screen = (NSApp.keyWindow ?? lastWindow)?.screen {
            rounded = min(rounded, screen.visibleFrame.width - 20)
        }
        guard rounded >= 500 else { return }
        perfectWidth = rounded
        snapWidths = [rounded]
    }

    /// Menü "Auf optimale Breite einrasten" – wirkt auf das aktive Fenster.
    func snapToPerfectWidth() {
        DispatchQueue.main.async {
            guard let window = NSApp.keyWindow ?? self.lastWindow else { return }
            var frame = window.frame
            let targetWidth = self.perfectWidth
            frame.size.width = targetWidth
            if let screen = window.screen {
                let maxX = screen.visibleFrame.maxX
                if frame.maxX > maxX {
                    frame.origin.x = max(screen.visibleFrame.minX, maxX - targetWidth)
                }
            }
            window.setFrame(frame, display: true, animate: true)
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        }
    }

    fileprivate func snappedSize(for frameSize: NSSize, lastSnapped: inout CGFloat?) -> NSSize {
        var size = frameSize
        for target in snapWidths where abs(size.width - target) <= snapTolerance {
            if lastSnapped != target {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                lastSnapped = target
            }
            size.width = target
            return size
        }
        lastSnapped = nil
        return size
    }
}

/// Delegate-Proxy pro Fenster: rastet beim Resizen ein und leitet alles andere an den ursprünglichen Delegate weiter.
private final class SnapDelegateProxy: NSObject, NSWindowDelegate {
    weak var manager: WindowSnapManager?
    weak var original: NSWindowDelegate?
    private var lastSnapped: CGFloat?

    init(manager: WindowSnapManager, original: NSWindowDelegate?) {
        self.manager = manager
        self.original = original
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let proposed = original?.windowWillResize?(sender, to: frameSize) ?? frameSize
        return manager?.snappedSize(for: proposed, lastSnapped: &lastSnapped) ?? proposed
    }

    func windowWillClose(_ notification: Notification) {
        original?.windowWillClose?(notification)
        if let window = notification.object as? NSWindow { manager?.detach(window) }
    }

    override func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector) || (original?.responds(to: aSelector) ?? false)
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if let original, original.responds(to: aSelector) { return original }
        return super.forwardingTarget(for: aSelector)
    }
}

struct WindowSnapAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { WindowObservingView() }
    func updateNSView(_ nsView: NSView, context: Context) {
        if let window = nsView.window { WindowSnapManager.shared.attach(to: window) }
    }
}

private class WindowObservingView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window { WindowSnapManager.shared.attach(to: window) }
    }
}
