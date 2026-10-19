// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Observation

/// Editor-only preview and optional audio input. This object never sends MIDI or actions.
@MainActor
@Observable
final class DeckLightingController {
    let audio = AudioReactiveMonitor()
    private(set) var previewColors: [Int: PadColor] = [:]
    private(set) var isPreviewing = false
    var onAudioLevel: ((Double) -> Void)?
    private var layout: ResolvedLayout?
    private var paused = false
    private var applicationStates: [Int: ApplicationLightState] = [:]
    @ObservationIgnored private lazy var renderer: LEDRenderer = {
        let renderer = LEDRenderer(model: { [weak self] in self?.layout?.model ?? .miniMK3 }, send: { _ in })
        renderer.onFrame = { [weak self] colors in self?.previewColors = colors }
        return renderer
    }()

    init() {
        audio.onLevel = { [weak self] level in
            guard let self else { return }
            if self.isPreviewing { self.renderer.setAudioLevel(level) }
            self.onAudioLevel?(level)
        }
    }

    func startPreview(_ layout: ResolvedLayout, paused: Bool) {
        isPreviewing = true
        updatePreview(layout, paused: paused)
    }

    func updatePreview(_ layout: ResolvedLayout, paused: Bool) {
        self.layout = layout; self.paused = paused
        guard isPreviewing else { return }
        renderer.render(layout, paused: paused)
        renderer.setApplicationStates(applicationStates)
        renderer.setAudioLevel(audio.level)
    }

    func stopPreview() {
        isPreviewing = false
        renderer.stop(clear: true)
        previewColors = [:]
    }

    func previewPress(index: Int) {
        guard isPreviewing, !paused else { return }
        renderer.press(index: index)
    }

    func setApplicationStates(_ states: [Int: ApplicationLightState]) {
        applicationStates = states
        if isPreviewing { renderer.setApplicationStates(states) }
    }

    func shutdown() {
        stopPreview()
        audio.disable()
    }
}
