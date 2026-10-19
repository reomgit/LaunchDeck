// SPDX-License-Identifier: GPL-3.0-only
// Copyright © 2026 Reom Nagasaka

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Converts one PNG/JPEG into a centered square crop, flattened over black.
/// The returned pixels use physical grid indices: bottom-left 0, top-left 56.
enum LEDGridArtwork {
    enum ImportError: LocalizedError {
        case dataTooLarge, unsupportedFormat, multipleImages, invalidDimensions, invalidImage

        var errorDescription: String? {
            switch self {
            case .dataTooLarge: "Choose an image no larger than 20 MB."
            case .unsupportedFormat: "Choose a PNG or JPEG image."
            case .multipleImages: "Choose a single image without animation."
            case .invalidDimensions: "Image dimensions must be between 1 and 4096 pixels."
            case .invalidImage: "The image is incomplete or could not be decoded."
            }
        }
    }

    static func colors(from data: Data) throws -> [PadColor] {
        guard data.count <= 20_000_000 else { throw ImportError.dataTooLarge }
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData,
                  [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetStatus(source) == .statusComplete,
              let type = CGImageSourceGetType(source) as String? else {
            throw ImportError.invalidImage
        }
        guard type == UTType.png.identifier || type == UTType.jpeg.identifier else {
            throw ImportError.unsupportedFormat
        }
        guard CGImageSourceGetCount(source) == 1 else { throw ImportError.multipleImages }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              (1...4096).contains(width), (1...4096).contains(height) else {
            throw ImportError.invalidDimensions
        }
        // ImageIO handles all EXIF rotations and reflections before the square crop.
        // A bounded thumbnail avoids allocating a full-resolution bitmap just for 64 LEDs.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 256,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete else {
            throw ImportError.invalidImage
        }
        let side = min(image.width, image.height)
        guard let square = image.cropping(to: CGRect(x: (image.width - side) / 2,
            y: (image.height - side) / 2, width: side, height: side)),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw ImportError.invalidImage
        }
        var bytes = [UInt8](repeating: 0, count: 8 * 8 * 4)
        let rendered = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: 8, height: 8,
                bitsPerComponent: 8, bytesPerRow: 32, space: colorSpace,
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.noneSkipLast.rawValue) else {
                return false
            }
            context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
            context.interpolationQuality = .high
            context.draw(square, in: CGRect(x: 0, y: 0, width: 8, height: 8))
            return true
        }
        guard rendered else { throw ImportError.invalidImage }
        var pixels = [PadColor](repeating: .off, count: 64)
        for row in 0..<8 {
            for column in 0..<8 {
                let offset = (row * 8 + column) * 4
                // Bitmap scanlines start at the image top; Launchpad rows start at its bottom.
                pixels[(7 - row) * 8 + column] = PadColor(
                    red: sevenBit(bytes[offset]), green: sevenBit(bytes[offset + 1]),
                    blue: sevenBit(bytes[offset + 2]))
            }
        }
        return pixels
    }

    private static func sevenBit(_ component: UInt8) -> Int {
        (Int(component) * 127 + 127) / 255
    }
}
