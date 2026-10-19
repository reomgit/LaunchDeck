// SPDX-License-Identifier: GPL-3.0-only
import Testing
import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
@testable import LaunchDeckCore

struct ArtworkThumbnailTests {
    @Test func downsamplingAndConcurrentCacheReuse() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: url) }
        let context = try #require(CGContext(data: nil, width: 1200, height: 800, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1200, height: 800))
        let image = try #require(context.makeImage())
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        let store = ArtworkThumbnailStore()
        async let first = store.thumbnail(at: url, pixels: 128)
        async let second = store.thumbnail(at: url, pixels: 128)
        let (one, two) = await (first, second)
        let thumbnail = try #require(one)
        #expect(thumbnail.image.width == 128)
        #expect(thumbnail.image.height <= 128)
        #expect(thumbnail.image === two?.image)
        let warm = await store.thumbnail(at: url, pixels: 128)
        #expect(thumbnail.image === warm?.image)
        let larger = try #require(await store.thumbnail(at: url, pixels: 256))
        #expect(larger.image.width == 256)
    }
    @Test func missingArtworkReturnsNoThumbnail() async {
        let store = ArtworkThumbnailStore()
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".png")
        #expect(await store.thumbnail(at: url, pixels: 128) == nil)
    }
}
