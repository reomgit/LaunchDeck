// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import ImageIO
import CoreGraphics

/// CGImage is immutable; decoded thumbnails can safely travel from a background task.
struct ArtworkThumbnailImage: @unchecked Sendable {
    let image: CGImage
}

actor ArtworkThumbnailStore {
    static let shared = ArtworkThumbnailStore()
    private let cache = NSCache<NSString, ThumbnailBox>()
    private var pending: [String: Task<ArtworkThumbnailImage?, Never>] = [:]

    init() {
        cache.countLimit = 256
        cache.totalCostLimit = 32 * 1024 * 1024
    }

    func thumbnail(at url: URL, pixels: Int) async -> ArtworkThumbnailImage? {
        let pixels = max(1, min(512, pixels))
        let key = url.standardizedFileURL.path + "#\(pixels)"
        if let result = cache.object(forKey: key as NSString) { return result.value }
        if let task = pending[key] { return await task.value }
        let task = Task.detached(priority: .utility) { () -> ArtworkThumbnailImage? in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceShouldCacheImmediately: true,
                    kCGImageSourceThumbnailMaxPixelSize: pixels
                  ] as CFDictionary) else { return nil }
            return ArtworkThumbnailImage(image: image)
        }
        pending[key] = task
        let result = await task.value
        pending[key] = nil
        if let result { cache.setObject(ThumbnailBox(result), forKey: key as NSString, cost: result.image.bytesPerRow * result.image.height) }
        return result
    }
}

private final class ThumbnailBox {
    let value: ArtworkThumbnailImage
    init(_ value: ArtworkThumbnailImage) { self.value = value }
}
