// SPDX-License-Identifier: GPL-3.0-only
// Copyright © 2026 Reom Nagasaka

import Foundation

enum MiniMK3Adapter {
    static let deviceInquiry: [UInt8] = [0xF0, 0x7E, 0x7F, 0x06, 0x01, 0xF7]
    static let programmerModeOn: [UInt8] = [0xF0, 0x00, 0x20, 0x29, 0x02, 0x0D, 0x0E, 0x01, 0xF7]
    static let programmerModeOff: [UInt8] = [0xF0, 0x00, 0x20, 0x29, 0x02, 0x0D, 0x0E, 0x00, 0xF7]

    static func padIndex(forMIDI1Note note: UInt8) -> Int? {
        let row = Int(note / 10) - 1
        let column = Int(note % 10) - 1
        guard (0..<8).contains(row), (0..<8).contains(column) else { return nil }
        return row * 8 + column
    }

    static func midi1Note(forPadIndex index: Int) -> UInt8? {
        guard (0..<64).contains(index) else { return nil }
        let row = index / 8
        let column = index % 8
        return UInt8((row + 1) * 10 + column + 1)
    }

    static func rgbFrame(for colors: [Int: PadColor]) -> [UInt8] {
        var bytes: [UInt8] = [0xF0, 0x00, 0x20, 0x29, 0x02, 0x0D, 0x03]
        for index in colors.keys.sorted() {
            guard let note = midi1Note(forPadIndex: index), let color = colors[index] else { continue }
            bytes += [0x03, note, color.red, color.green, color.blue]
        }
        bytes.append(0xF7)
        return bytes
    }

    static func padEvent(status: UInt8, data1: UInt8, data2: UInt8, generation: Int) -> PadEvent? {
        guard let index = padIndex(forMIDI1Note: data1) else { return nil }
        switch status & 0xF0 {
        case 0x90:
            return PadEvent(index: index, phase: data2 == 0 ? .released : .pressed, generation: generation)
        case 0x80:
            return PadEvent(index: index, phase: .released, generation: generation)
        default:
            return nil
        }
    }
}
