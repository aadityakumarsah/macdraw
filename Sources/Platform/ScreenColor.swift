import AppKit
import ScreenCaptureKit

/// Reads the colour of a pixel on screen, from the windows *underneath* the
/// overlay.
///
/// This is the version of an eyedropper that only an overlay app can offer.
/// Excalidraw's samples its own canvas, because that is all a web page can
/// see; macdraw sits on top of whatever you are annotating, so the useful
/// pixel is usually in the app below — the exact blue of a button you are
/// circling, the grey of a chart you are marking up.
///
/// Both of the old one-call APIs for this (`CGWindowListCreateImage` and
/// `CGDisplayCreateImage`) are now *unavailable*, not merely deprecated, so
/// this goes through ScreenCaptureKit. `SCScreenshotManager` needs macOS 14
/// while the app supports 13, hence the availability gate and the caller's
/// fallback to sampling macdraw's own drawing.
enum ScreenColor {
    /// Whether screen sampling can work at all on this OS.
    static var isSupported: Bool {
        if #available(macOS 14.0, *) { return true }
        return false
    }

    /// Screen reading needs the Screen Recording permission. Without it the
    /// capture returns only the desktop, so the colour would be silently
    /// wrong — check before sampling rather than after.
    static var isAuthorized: Bool { CGPreflightScreenCaptureAccess() }

    /// Prompts for the permission. Returns true if it was already granted.
    /// macOS shows its dialog once per app; after that the user has to go to
    /// System Settings, which `openPrivacySettings` links to.
    @discardableResult
    static func requestAuthorization() -> Bool { CGRequestScreenCaptureAccess() }

    static func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }

    /// The colour under a point given in Cocoa screen coordinates (origin at
    /// the bottom-left of the main display — what `NSEvent.mouseLocation`
    /// reports), excluding macdraw's own window so neither the overlay's ink
    /// nor its toolbar can be sampled by accident.
    @available(macOS 14.0, *)
    static func color(atCocoaPoint point: CGPoint, excludingWindow windowNumber: Int) async -> NSColor? {
        guard let screen = screen(containing: point),
              let displayID = screen.displayID else { return nil }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true
            )
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else { return nil }
            // Everything of ours is excluded: the overlay panel, the toolbar's
            // hosting window, any popover.
            let ours = content.windows.filter { $0.owningApplication?.processID == getpid() }
            _ = windowNumber
            let filter = SCContentFilter(display: display, excludingWindows: ours)

            let local = cgPoint(in: screen, fromCocoa: point)
            let configuration = SCStreamConfiguration()
            configuration.sourceRect = CGRect(x: local.x, y: local.y, width: 1, height: 1)
            configuration.width = 1
            configuration.height = 1
            configuration.showsCursor = false
            configuration.captureResolution = .best

            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: configuration
            )
            return firstPixel(of: image)
        } catch {
            return nil
        }
    }

    /// Display-local CoreGraphics coordinates (y-down from the display's own
    /// top-left), which is what `sourceRect` is relative to.
    private static func cgPoint(in screen: NSScreen, fromCocoa point: CGPoint) -> CGPoint {
        CGPoint(
            x: point.x - screen.frame.minX,
            y: screen.frame.maxY - point.y
        )
    }

    private static func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
    }

    /// Reads pixel (0, 0) out of a captured image.
    static func firstPixel(of image: CGImage) -> NSColor? {
        var pixel: [UInt8] = [0, 0, 0, 0]
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: &pixel, width: 1, height: 1,
                  bitsPerComponent: 8, bytesPerRow: 4, space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        guard pixel[3] > 0 else { return nil }
        return NSColor(
            srgbRed: CGFloat(pixel[0]) / 255,
            green: CGFloat(pixel[1]) / 255,
            blue: CGFloat(pixel[2]) / 255,
            alpha: 1
        )
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
