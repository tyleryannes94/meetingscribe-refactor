import AppKit
import SwiftUI
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
        c.totalCostLimit = 48 * 1024 * 1024   // byte-bound to prevent OOM (V5 PS-5)
        return c
    }()

    private static func key(_ url: URL, _ maxPixel: CGFloat) -> NSString {
        "\(url.path)|\(Int(maxPixel))" as NSString
    }

    /// Memory hit only — no decode. For an instant first paint before the async
    /// decode lands.
    static func cached(url: URL, maxPixel: CGFloat) -> NSImage? {
        cache.object(forKey: key(url, maxPixel))
    }

    static func thumbnail(at url: URL, maxPixel: CGFloat) -> NSImage? {
        let k = key(url, maxPixel)
        if let hit = cache.object(forKey: k) { return hit }
        guard let img = downsample(url: url, maxPixel: maxPixel) else { return nil }
        // Cost ≈ decoded RGBA bytes so totalCostLimit evicts by real memory.
        let px = maxPixel * scale
        cache.setObject(img, forKey: k, cost: Int(px * px * 4))
        return img
    }

    static func downsampleOffMain(url: URL, maxPixel: CGFloat) -> NSImage? {
        downsample(url: url, maxPixel: maxPixel)
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

/// Renders a downsampled, cached thumbnail with the decode done OFF the main
/// thread (the synchronous decode-in-body was a confirmed scroll stall — V5
/// DI-2). Shows a memory hit instantly; otherwise a placeholder fades to the
/// image once decoded.
@available(macOS 14.0, *)
struct CachedThumbnail: View {
    let url: URL
    let side: CGFloat
    var cornerRadius: CGFloat = 8
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(NDS.fieldBg)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: url) { await load() }
    }

    private func load() async {
        if let hit = ThumbnailCache.cached(url: url, maxPixel: side) { image = hit; return }
        let side = self.side, url = self.url
        let decoded = await Task.detached(priority: .utility) {
            ThumbnailCache.thumbnail(at: url, maxPixel: side)
        }.value
        if !Task.isCancelled { image = decoded }
    }
}
