import AppKit
import CoreGraphics
import Foundation

final class ScreenCaptureService: ObservableObject {
    static let shared = ScreenCaptureService()

    @Published var image: CGImage?
    @Published var failed = false

    private var pixels: [UInt8] = []
    private var width = 0
    private var height = 0
    private let file = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("nook-screenshot.png")

    func capture() {
        guard CGPreflightScreenCaptureAccess() else {
            failed = true
            image = nil
            return
        }
        let out = Util.shell("/usr/sbin/screencapture", ["-x", "-o", "-t", "png", file.path])
        guard out != nil, let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            failed = true
            image = nil
            return
        }
        failed = false
        image = cg
        width = cg.width
        height = cg.height
        let space = CGColorSpaceCreateDeviceRGB()
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &buffer, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width * 4, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        if let context {
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            pixels = buffer
        }
    }

    /// Asks the system for Screen Recording. macOS only prompts when it has
    /// not already recorded a decision; after granting, relaunch Nook.
    func requestAccess() {
        if CGRequestScreenCaptureAccess() {
            capture()
        } else {
            failed = true
        }
    }

    /// A small square crop around a pixel, used by the magnifier.
    func crop(center: CGPoint, side: Int) -> CGImage? {
        guard let image, width > 0, height > 0, side > 0 else { return nil }
        let rect = CGRect(x: Int(center.x) - side / 2,
                          y: Int(center.y) - side / 2,
                          width: side, height: side)
            .intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard rect.width >= 1, rect.height >= 1 else { return nil }
        return image.cropping(to: rect)
    }

    /// point in image pixel space, origin top-left.
    func color(at point: CGPoint) -> NSColor? {
        guard width > 0, height > 0 else { return nil }
        let x = min(max(Int(point.x), 0), width - 1)
        let y = min(max(Int(point.y), 0), height - 1)
        let index = (y * width + x) * 4
        guard index + 3 < pixels.count else { return nil }
        return NSColor(srgbRed: CGFloat(pixels[index]) / 255,
                       green: CGFloat(pixels[index + 1]) / 255,
                       blue: CGFloat(pixels[index + 2]) / 255,
                       alpha: 1)
    }

    var pixelSize: CGSize { CGSize(width: width, height: height) }

    enum Format: String, CaseIterable { case hex, rgb, hsl, css

        var label: String {
            switch self {
            case .hex: return "HEX"
            case .rgb: return "RGB"
            case .hsl: return "HSL"
            case .css: return "CSS"
            }
        }

        func string(from color: NSColor) -> String {
            guard let c = color.usingColorSpace(.sRGB) else { return "" }
            let r = Int(round(c.redComponent * 255))
            let g = Int(round(c.greenComponent * 255))
            let b = Int(round(c.blueComponent * 255))
            switch self {
            case .hex: return String(format: "#%02X%02X%02X", r, g, b)
            case .rgb: return "rgb(\(r), \(g), \(b))"
            case .css: return "color(srgb \(Util.rounded(c.redComponent, 3)) \(Util.rounded(c.greenComponent, 3)) \(Util.rounded(c.blueComponent, 3)))"
            case .hsl:
                let hsl = Self.hsl(r, g, b)
                return "hsl(\(Int(hsl.h.rounded())), \(Int(hsl.s.rounded()))%, \(Int(hsl.l.rounded()))%)"
            }
        }

        private static func hsl(_ r: Int, _ g: Int, _ b: Int) -> (h: Double, s: Double, l: Double) {
            let rf = Double(r) / 255, gf = Double(g) / 255, bf = Double(b) / 255
            let maxC = max(rf, gf, bf), minC = min(rf, gf, bf)
            let delta = maxC - minC
            let l = (maxC + minC) / 2
            var h = 0.0
            if delta > 0 {
                if maxC == rf { h = 60 * ((gf - bf) / delta.truncatingRemainder(dividingBy: 6)) }
                else if maxC == gf { h = 60 * ((bf - rf) / delta + 2) }
                else { h = 60 * ((rf - gf) / delta + 4) }
            }
            let s = delta == 0 ? 0 : delta / (1 - abs(2 * l - 1))
            return ((h + 360).truncatingRemainder(dividingBy: 360), s * 100, l * 100)
        }
    }
}
