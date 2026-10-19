// SPDX-License-Identifier: GPL-3.0-only
import Testing
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import LaunchDeckCore

struct LEDGridArtworkTests {
    private let red = PadColor(red: 127, green: 0, blue: 0)
    private let green = PadColor(red: 0, green: 127, blue: 0)
    private let blue = PadColor(red: 0, green: 0, blue: 127)
    private let white = PadColor(red: 127, green: 127, blue: 127)

    // Bytes are ordered as literal top-to-bottom scanlines, independent of the importer.
    private func quadrants() -> [UInt8] {
        let top: [UInt8] = Array(repeating: [255, 0, 0, 255], count: 4).flatMap { $0 }
            + Array(repeating: [0, 255, 0, 255], count: 4).flatMap { $0 }
        let bottom: [UInt8] = Array(repeating: [0, 0, 255, 255], count: 4).flatMap { $0 }
            + Array(repeating: [255, 255, 255, 255], count: 4).flatMap { $0 }
        return Array(repeating: top, count: 4).flatMap { $0 }
            + Array(repeating: bottom, count: 4).flatMap { $0 }
    }

    private func encoded(_ bytes: [UInt8], width: Int = 8, height: Int = 8,
                         type: UTType = .png, orientation: Int = 1, frames: Int = 1) throws -> Data {
        let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
        let image = try #require(CGImage(width: width, height: height, bitsPerComponent: 8,
            bitsPerPixel: 32, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider,
            decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let result = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(result, type.identifier as CFString, frames, nil))
        for _ in 0..<frames {
            CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation,
                kCGImageDestinationLossyCompressionQuality: 1] as CFDictionary)
        }
        #expect(CGImageDestinationFinalize(destination))
        return result as Data
    }

    @Test func pngLiteralQuadrantsMapTopLeftTo56AndBottomLeftTo0() throws {
        let pixels = try LEDGridArtwork.colors(from: encoded(quadrants()))
        #expect(pixels.count == 64)
        #expect(Array(pixels[56...59]) == [red, red, red, red])
        #expect(Array(pixels[60...63]) == [green, green, green, green])
        #expect(Array(pixels[0...3]) == [blue, blue, blue, blue])
        #expect(Array(pixels[4...7]) == [white, white, white, white])
        #expect(pixels.allSatisfy { $0.red <= 127 && $0.green <= 127 && $0.blue <= 127 })
    }

    @Test func exifOrientationIncludesRotationsAndMirroring() throws {
        // Expected displayed corners: top-left, top-right, bottom-left, bottom-right.
        let cases: [(Int, [PadColor])] = [
            (1, [red, green, blue, white]), (2, [green, red, white, blue]),
            (3, [white, blue, green, red]), (4, [blue, white, red, green]),
            (5, [red, blue, green, white]), (6, [blue, red, white, green]),
            (7, [white, green, blue, red]), (8, [green, white, red, blue])
        ]
        for (orientation, expected) in cases {
            let pixels = try LEDGridArtwork.colors(from: encoded(quadrants(), orientation: orientation))
            #expect([pixels[56], pixels[63], pixels[0], pixels[7]] == expected,
                    "EXIF orientation \(orientation)")
        }
    }

    @Test func alphaIsFlattenedOntoBlackBeforeSevenBitConversion() throws {
        let top = Array(repeating: [UInt8](arrayLiteral: 255, 0, 0, 128), count: 8).flatMap { $0 }
        let bottom = Array(repeating: [UInt8](arrayLiteral: 0, 255, 0, 0), count: 8).flatMap { $0 }
        let rgba = Array(repeating: top, count: 4).flatMap { $0 }
            + Array(repeating: bottom, count: 4).flatMap { $0 }
        let pixels = try LEDGridArtwork.colors(from: encoded(rgba))
        #expect(pixels[56] == PadColor(red: 64, green: 0, blue: 0))
        #expect(pixels[0] == .off)
    }

    @Test func nonSquareImageUsesCenteredSquareFillCrop() throws {
        let row = Array(repeating: [UInt8](arrayLiteral: 255, 0, 0, 255), count: 4).flatMap { $0 }
            + Array(repeating: [UInt8](arrayLiteral: 0, 255, 0, 255), count: 8).flatMap { $0 }
            + Array(repeating: [UInt8](arrayLiteral: 0, 0, 255, 255), count: 4).flatMap { $0 }
        let pixels = try LEDGridArtwork.colors(from: encoded(Array(repeating: row, count: 8).flatMap { $0 }, width: 16))
        #expect(pixels == Array(repeating: green, count: 64))
    }

    @Test func jpegIsAcceptedAndKeepsDisplayedOrientation() throws {
        let pixels = try LEDGridArtwork.colors(from: encoded(quadrants(), type: .jpeg, orientation: 6))
        #expect(pixels.count == 64)
        #expect(pixels[56].blue > 115 && pixels[56].red < 12 && pixels[56].green < 12)
        #expect(pixels[63].red > 115 && pixels[63].green < 12 && pixels[63].blue < 12)
    }

    @Test func malformedTruncatedAndOversizedDataAreRejected() throws {
        #expect(throws: (any Error).self) { try LEDGridArtwork.colors(from: Data()) }
        #expect(throws: (any Error).self) { try LEDGridArtwork.colors(from: Data("not an image".utf8)) }
        let png = try encoded(quadrants())
        #expect(throws: (any Error).self) { try LEDGridArtwork.colors(from: Data(png.prefix(png.count / 2))) }
        #expect(throws: LEDGridArtwork.ImportError.dataTooLarge) {
            try LEDGridArtwork.colors(from: Data(repeating: 0, count: 20_000_000 + 1))
        }
    }

    @Test func oversizedDimensionsAreRejectedBeforeDecoding() throws {
        let bytes = Array(repeating: [UInt8](arrayLiteral: 255, 0, 0, 255), count: 4097).flatMap { $0 }
        #expect(throws: LEDGridArtwork.ImportError.invalidDimensions) {
            try LEDGridArtwork.colors(from: encoded(bytes, width: 4097, height: 1))
        }
        #expect(throws: LEDGridArtwork.ImportError.invalidDimensions) {
            try LEDGridArtwork.colors(from: encoded(bytes, width: 1, height: 4097))
        }
        let allowed = Array(repeating: [UInt8](arrayLiteral: 255, 0, 0, 255), count: 4096).flatMap { $0 }
        #expect(try LEDGridArtwork.colors(from: encoded(allowed, width: 4096, height: 1))
            == Array(repeating: red, count: 64))
    }

    @Test func unsupportedAndMultiframeImagesAreRejected() throws {
        #expect(throws: LEDGridArtwork.ImportError.unsupportedFormat) {
            try LEDGridArtwork.colors(from: encoded(quadrants(), type: .tiff))
        }
        #expect(throws: (any Error).self) {
            try LEDGridArtwork.colors(from: encoded(quadrants(), type: .gif, frames: 2))
        }
        #expect(throws: LEDGridArtwork.ImportError.multipleImages) {
            try LEDGridArtwork.colors(from: encoded(quadrants(), frames: 2))
        }
    }
}
