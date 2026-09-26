// SPDX-License-Identifier: GPL-3.0-only
// Copyright © 2026 Reom Nagasaka

import Foundation

@MainActor
final class LEDRenderer {
    private let midi: MIDIService
    private var activeLayout: ResolvedLayout?
    private var lastSent = Array(repeating: PadColor.off, count: 64)
    private var paused = false

    init(midi: MIDIService) {
        self.midi = midi
    }

    func render(_ layout: ResolvedLayout, paused: Bool) {
        activeLayout = layout
        self.paused = paused
        transmit(desiredColors())
    }

    func repaint() {
        lastSent = Array(repeating: .off, count: 64)
        transmit(desiredColors())
    }

    func flash(index: Int, color: PadColor, durationNanoseconds: UInt64 = 120_000_000) {
        guard (0..<64).contains(index), !paused else { return }
        let revision = activeLayout?.revision
        transmit([index: color])
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: durationNanoseconds)
            guard self?.activeLayout?.revision == revision else { return }
            guard let restoration = self?.desiredColors()[index] else { return }
            self?.transmit([index: restoration])
        }
    }

    private func desiredColors() -> [Int: PadColor] {
        guard !paused, let activeLayout else {
            return Dictionary(uniqueKeysWithValues: (0..<64).map { ($0, .off) })
        }
        return Dictionary(uniqueKeysWithValues: (0..<64).map { index in
            (index, activeLayout.binding(at: index)?.color ?? .off)
        })
    }

    private func transmit(_ colors: [Int: PadColor]) {
        var changes: [Int: PadColor] = [:]
        for (index, color) in colors where lastSent[index] != color {
            changes[index] = color
            lastSent[index] = color
        }
        guard !changes.isEmpty else { return }
        midi.sendSysEx(MiniMK3Adapter.rgbFrame(for: changes))
    }
}
