import AppKit
import ImageIO

/// Downsampled, decoded thumbnail cache for people photos. Replaces repeated
/// full-resolution `NSImage(contentsOf:)` loads (one per scroll / re-render) with
/// a single ImageIO downsample to roughly the display size, kept in an NSCache.
/// Cuts both decode time and the memory held for a full-res image. (E2-5)
enum ThumbnailCache {
    /// Assume Retina; thumbnails don't need exact backing-scale fidelity.
    private static let scale: CGFloat = 2

    private static let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 256
        return c
    }()

    static func thumbnail(at url: URL, maxPixel: CGFloat) -> NSImage? {
        let key = "\(url.path)|\(Int(maxPixel))" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let img = downsample(url: url, maxPixel: maxPixel) else { return nil }
        cache.setObject(img, forKey: key)
        return img
    }

    private static func downsample(url: URL, maxPixel: CGFloat) -> NSImage? {
        let srcOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let src = CGImageSourceCreateWithURL(url as CFURL, srcOptions) else { return nil }
        let maxDim = Int(maxPixel * scale)
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDim
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: maxPixel, height: maxPixel))
    }
}
