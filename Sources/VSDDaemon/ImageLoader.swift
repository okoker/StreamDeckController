import Foundation
import CoreGraphics
import ImageIO

enum ImageLoader {

    // LCD viewport offset — calibrated empirically to center on physical LCD
    private static let shiftX: CGFloat = -9
    private static let shiftY: CGFloat = 8

    /// Load an image file (.icns, .png, .jpg), auto-trim transparent padding,
    /// center in 90x90, rotate 90° CW, encode as JPEG.
    /// Max source image dimension (pixels). Icons are rendered at 85x85 —
    /// anything larger than 1024px is almost certainly not an icon.
    private static let maxSourceDimension = 1024

    static func loadAsJPEG(path: String, size: Int = 85, quality: Double = 0.9) -> Data? {
        let url = URL(fileURLWithPath: path) as CFURL
        guard let source = CGImageSourceCreateWithURL(url, nil),
              CGImageSourceGetCount(source) > 0 else {
            print("Warning: could not load image at \(path)")
            return nil
        }

        // Check dimensions from metadata before full decode
        if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let pw = props[kCGImagePropertyPixelWidth] as? Int,
           let ph = props[kCGImagePropertyPixelHeight] as? Int,
           pw > maxSourceDimension || ph > maxSourceDimension {
            print("Warning: image too large (\(pw)x\(ph), max \(maxSourceDimension)px) at \(path)")
            return nil
        }

        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            print("Warning: could not decode image at \(path)")
            return nil
        }

        // Auto-trim: crop to non-transparent content bounds
        let cropped = trimTransparency(image) ?? image

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            print("Warning: could not create CGContext for image")
            return nil
        }

        let fullRect = CGRect(x: 0, y: 0, width: size, height: size)

        // Black background (LCDs don't support transparency)
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(fullRect)

        // Rotate 90° clockwise (protocol v3 requirement)
        // Offset to compensate for LCD viewport alignment
        ctx.translateBy(x: CGFloat(size) + shiftX, y: shiftY)
        ctx.rotate(by: CGFloat.pi / 2)

        // Center the trimmed icon with a small margin
        let margin: CGFloat = 4
        let drawSize = CGFloat(size) - margin * 2
        let drawRect = CGRect(x: margin, y: margin, width: drawSize, height: drawSize)

        ctx.interpolationQuality = .high

        // 180° flip — LCDs are mounted upside-down relative to default orientation
        let cx = drawRect.midX
        let cy = drawRect.midY
        ctx.translateBy(x: cx, y: cy)
        ctx.rotate(by: CGFloat.pi)
        ctx.translateBy(x: -cx, y: -cy)

        ctx.draw(cropped, in: drawRect)

        guard let rotated = ctx.makeImage() else {
            print("Warning: could not create rotated image")
            return nil
        }

        // Encode as JPEG
        let jpegData = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            jpegData as CFMutableData, "public.jpeg" as CFString, 1, nil
        ) else {
            print("Warning: could not create JPEG encoder")
            return nil
        }

        let opts: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(dest, rotated, opts as CFDictionary)

        guard CGImageDestinationFinalize(dest) else {
            print("Warning: JPEG encoding failed")
            return nil
        }

        return jpegData as Data
    }

    /// Find bounding box of non-transparent pixels and crop to it.
    private static func trimTransparency(_ image: CGImage) -> CGImage? {
        let w = image.width
        let h = image.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data else { return nil }

        let pixels = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        let threshold: UInt8 = 10

        var minX = w, minY = h, maxX = 0, maxY = 0

        for y in 0..<h {
            for x in 0..<w {
                let alpha = pixels[(y * w + x) * 4 + 3]
                if alpha > threshold {
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
        }

        guard maxX >= minX, maxY >= minY else { return nil }

        // CG has y-up, but our pixel scan is y-down. Flip the Y bounds.
        let cropRect = CGRect(
            x: minX, y: h - maxY - 1,
            width: maxX - minX + 1, height: maxY - minY + 1
        )
        return image.cropping(to: cropRect)
    }
}
