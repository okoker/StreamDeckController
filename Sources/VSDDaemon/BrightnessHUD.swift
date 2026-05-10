import AppKit

final class BrightnessHUD {

    private static var windows: [NSWindow] = []
    private static var labels: [NSTextField] = []
    private static var dismissTimer: DispatchSourceTimer?
    private static var screenCount: Int = 0

    /// Show (or update) a large HUD overlay on ALL screens simultaneously.
    /// Auto-dismisses 2.5 s after the last call. Reuses windows when possible.
    static func show(text: String) {
        dispatchPrecondition(condition: .onQueue(.main))

        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }

        if !labels.isEmpty && screenCount == screens.count {
            for lbl in labels { lbl.stringValue = text }
            for win in windows { win.orderFrontRegardless() }
        } else {
            closeAll()
            for screen in screens {
                createWindow(text: text, screen: screen)
            }
            screenCount = screens.count
            print("BrightnessHUD: created \(screens.count) window(s)")
        }

        dismissTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 2.5)
        timer.setEventHandler { closeAll() }
        timer.resume()
        dismissTimer = timer
    }

    // MARK: - Private

    private static func createWindow(text: String, screen: NSScreen) {
        let winW: CGFloat = 700
        let winH: CGFloat = 160
        let sf = screen.frame
        let origin = NSPoint(x: sf.midX - winW / 2, y: sf.midY - winH / 2)

        let win = NSWindow(
            contentRect: NSRect(origin: origin, size: NSSize(width: winW, height: winH)),
            styleMask: .borderless,
            backing: .buffered,
            defer: false)
        win.level = .floating
        win.backgroundColor = NSColor.black.withAlphaComponent(0.80)
        win.isOpaque = false
        win.hasShadow = true
        win.ignoresMouseEvents = true
        win.collectionBehavior = [.canJoinAllSpaces, .stationary]

        win.contentView?.wantsLayer = true
        win.contentView?.layer?.cornerRadius = 24
        win.contentView?.layer?.masksToBounds = true

        let lbl = NSTextField(labelWithString: text)
        lbl.font = NSFont.monospacedSystemFont(ofSize: 80, weight: .bold)
        lbl.textColor = .white
        lbl.alignment = .center
        lbl.backgroundColor = .clear
        lbl.isBezeled = false
        lbl.isEditable = false
        lbl.frame = NSRect(x: 0, y: 0, width: winW, height: winH)

        win.contentView?.addSubview(lbl)
        win.orderFrontRegardless()

        windows.append(win)
        labels.append(lbl)
    }

    private static func closeAll() {
        dismissTimer?.cancel()
        dismissTimer = nil
        for win in windows { win.close() }
        windows.removeAll()
        labels.removeAll()
        screenCount = 0
    }
}
