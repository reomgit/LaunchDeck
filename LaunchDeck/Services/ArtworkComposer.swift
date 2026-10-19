// SPDX-License-Identifier: GPL-3.0-only
import AppKit

@MainActor
enum ArtworkComposer {
    static func render(label: String, symbolName: String?, color: PadColor) -> Data? {
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 256, pixelsHigh: 256, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let pixels = bitmap.bitmapData else { return nil }
        for y in 0..<256 {
            for x in 0..<256 {
                let offset = y * bitmap.bytesPerRow + x * 4
                pixels[offset] = UInt8(clamping: Int(color.red) * 255 / 127)
                pixels[offset + 1] = UInt8(clamping: Int(color.green) * 255 / 127)
                pixels[offset + 2] = UInt8(clamping: Int(color.blue) * 255 / 127)
                pixels[offset + 3] = 255
            }
        }
        let symbol = symbolName.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
        if let symbol {
            let configured = symbol.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 90, weight: .medium).applying(.init(paletteColors: [.white]))) ?? symbol
            configured.draw(in: NSRect(x: 70, y: 100, width: 116, height: 116))
        }
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center; paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: symbol == nil ? 32 : 24, weight: .semibold), .foregroundColor: NSColor.white, .paragraphStyle: paragraph]
        (label as NSString).draw(in: NSRect(x: 16, y: symbol == nil ? 94 : 25, width: 224, height: 62), withAttributes: attributes)
        context.flushGraphics()
        return bitmap.representation(using: .png, properties: [:])
    }
}
