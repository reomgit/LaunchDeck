// SPDX-License-Identifier: GPL-3.0-only
// Copyright © 2026 Reom Nagasaka
import Foundation

enum PressEffect: String, CaseIterable, Codable, Hashable, Sendable {
    case glow, none, ripple, cross, sparkle
    var displayName: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

enum AmbientEffect: String, CaseIterable, Codable, Hashable, Sendable {
    case none, breathe, rainbow, scanner, audioMeter
    var displayName: String { self == .audioMeter ? "Audio Meter" : rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

struct LightingSettings: Codable, Hashable, Sendable {
    var pressEffect: PressEffect = .glow
    var ambientEffect: AmbientEffect = .none
    var brightness: Double = 1
    var speed: Double = 1
    var accentColor: PadColor = .blue
    var gridArtwork: [PadColor]?
    var showsActionStatus = true
    var showsApplicationStatus = true

    init(pressEffect: PressEffect = .glow, ambientEffect: AmbientEffect = .none,
         brightness: Double = 1, speed: Double = 1, accentColor: PadColor = .blue,
         gridArtwork: [PadColor]? = nil, showsActionStatus: Bool = true, showsApplicationStatus: Bool = true) {
        self.pressEffect = pressEffect; self.ambientEffect = ambientEffect
        self.brightness = brightness; self.speed = speed; self.accentColor = accentColor
        self.gridArtwork = gridArtwork; self.showsActionStatus = showsActionStatus; self.showsApplicationStatus = showsApplicationStatus
    }

    func validate() throws {
        guard brightness.isFinite, (0...1).contains(brightness), speed.isFinite, (0.25...3).contains(speed),
              accentColor.isSevenBit, gridArtwork.map({ $0.count == 64 && $0.allSatisfy(\.isSevenBit) }) ?? true else {
            throw CocoaError(.fileReadCorruptFile)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case pressEffect, ambientEffect, brightness, speed, accentColor, gridArtwork, showsActionStatus, showsApplicationStatus
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pressEffect = try c.decodeIfPresent(PressEffect.self, forKey: .pressEffect) ?? .glow
        ambientEffect = try c.decodeIfPresent(AmbientEffect.self, forKey: .ambientEffect) ?? .none
        brightness = try c.decodeIfPresent(Double.self, forKey: .brightness) ?? 1
        speed = try c.decodeIfPresent(Double.self, forKey: .speed) ?? 1
        accentColor = try c.decodeIfPresent(PadColor.self, forKey: .accentColor) ?? .blue
        gridArtwork = try c.decodeIfPresent([PadColor].self, forKey: .gridArtwork)
        showsActionStatus = try c.decodeIfPresent(Bool.self, forKey: .showsActionStatus) ?? true
        showsApplicationStatus = try c.decodeIfPresent(Bool.self, forKey: .showsApplicationStatus) ?? true
        try validate()
    }
}

enum LightingActionStatus: Hashable, Sendable { case running, success, failure }
enum ApplicationLightState: Hashable, Sendable { case running, frontmost }

extension PadColor {
    var isSevenBit: Bool { red <= 127 && green <= 127 && blue <= 127 }
}


struct LightingPress: Hashable, Sendable {
    let index: Int
    let effect: PressEffect
    let color: PadColor
    let startedAt: TimeInterval
    static let maximumCount = 24
    func isActive(at time: TimeInterval, speed: Double) -> Bool {
        let age = (time - startedAt) * LightingComposer.safeSpeed(speed)
        return age.isFinite && age >= 0 && age < 0.9
    }
}

struct LightingStatus: Hashable, Sendable {
    let status: LightingActionStatus
    let startedAt: TimeInterval
    func isActive(at time: TimeInterval) -> Bool {
        let age = time - startedAt
        return age.isFinite && age >= 0 && (status == .running || age < 0.8)
    }
}

/// Pure composition in device pad coordinates (grid row zero is the bottom row).
enum LightingComposer {
    static func frame(layout: ResolvedLayout, time: TimeInterval, presses: [LightingPress] = [],
                      statuses: [Int: LightingStatus] = [:], applicationStates: [Int: ApplicationLightState] = [:],
                      audioLevel: Double = 0) -> [Int: PadColor] {
        let settings = layout.lighting
        let speed = safeSpeed(settings.speed)
        let phase = (time.isFinite ? time.truncatingRemainder(dividingBy: 3600) : 0) * speed
        // Both the state owner and this public pure entry point bound composition work.
        let presses = presses.suffix(LightingPress.maximumCount).filter { $0.isActive(at: time, speed: speed) }
        let level = audioLevel.isFinite ? min(1, max(0, audioLevel)) : 0
        return Dictionary(uniqueKeysWithValues: (0..<layout.controlCount).map { index in
            let binding = layout.binding(at: index)
            var color = index < 64 ? (settings.gridArtwork?[safe: index] ?? binding?.effectiveColor ?? .off) : (binding?.effectiveColor ?? .off)
            if index < 64 {
                switch settings.ambientEffect {
                case .none: break
                case .breathe:
                    color = scaled(color == .off ? settings.accentColor : color, by: 0.25 + 0.75 * (sin(phase * .pi) + 1) / 2)
                case .rainbow:
                    color = rainbow(hue: phase * 0.15 + Double(index % 8 + index / 8) / 16)
                case .scanner:
                    let column = (phase * 4).truncatingRemainder(dividingBy: 14)
                    let position = column <= 7 ? column : 14 - column
                    color = blend(color, settings.accentColor, amount: max(0, 1 - abs(Double(index % 8) - position)))
                case .audioMeter:
                    color = Double(index / 8) < ceil(level * 8) ? settings.accentColor : color
                }
            }
            if settings.showsApplicationStatus, let state = applicationStates[index],
               case .step(.launchApplication) = binding?.action {
                color = state == .frontmost ? color.highlighted : blend(color, .green, amount: 0.35)
            }
            for press in presses {
                let age = (time - press.startedAt) * speed
                let strength = 1 - age / 0.9
                let same = index == press.index
                let isGrid = index < 64 && (0..<64).contains(press.index)
                var amount: Double = 0
                switch press.effect {
                case .none: break
                case .glow: amount = same ? strength : 0
                case .ripple:
                    if isGrid {
                        let dx = Double(index % 8 - press.index % 8), dy = Double(index / 8 - press.index / 8)
                        amount = max(0, 1 - abs(hypot(dx, dy) - age * 8)) * strength
                    } else { amount = same ? strength : 0 }
                case .cross:
                    amount = same || (isGrid && (index % 8 == press.index % 8 || index / 8 == press.index / 8)) ? strength : 0
                case .sparkle:
                    if same { amount = strength }
                    else if isGrid {
                        // Integer hash rather than random state: reproducible for preview, tests and hardware.
                        let seed = index &* 73 &+ press.index &* 151 &+ Int(age * 12) &* 199
                        amount = (seed ^ (seed >> 3)) % 13 == 0 ? strength : 0
                    }
                }
                color = blend(color, press.color, amount: amount)
            }
            if settings.showsActionStatus, let status = statuses[index], status.isActive(at: time) {
                switch status.status {
                case .running: color = scaled(.amber, by: 0.6 + 0.4 * (sin(phase * 8) + 1) / 2)
                case .success: color = .green
                case .failure: color = PadColor(red: 127, green: 15, blue: 10)
                }
            }
            // Disabled masks and brightness apply after *every* overlay, including unassigned artwork.
            let disabled = layout.pad(at: index)?.isDisabled == true || binding?.action == .disabled
            return (index, disabled ? .off : scaled(color, by: settings.brightness))
        })
    }

    static func safeSpeed(_ speed: Double) -> Double { speed.isFinite ? min(3, max(0.25, speed)) : 1 }

    private static func scaled(_ color: PadColor, by amount: Double) -> PadColor {
        let amount = amount.isFinite ? min(1, max(0, amount)) : 0
        return PadColor(red: Int((Double(min(color.red, 127)) * amount).rounded()),
                        green: Int((Double(min(color.green, 127)) * amount).rounded()),
                        blue: Int((Double(min(color.blue, 127)) * amount).rounded()))
    }
    private static func blend(_ base: PadColor, _ overlay: PadColor, amount: Double) -> PadColor {
        let amount = min(1, max(0, amount))
        return PadColor(red: Int((Double(base.red) * (1 - amount) + Double(overlay.red) * amount).rounded()),
                        green: Int((Double(base.green) * (1 - amount) + Double(overlay.green) * amount).rounded()),
                        blue: Int((Double(base.blue) * (1 - amount) + Double(overlay.blue) * amount).rounded()))
    }
    private static func rainbow(hue: Double) -> PadColor {
        let hue = hue - floor(hue)
        let sector = hue * 6
        let x = Int((127 * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))).rounded())
        switch Int(sector) {
        case 0: return PadColor(red: 127, green: x, blue: 0)
        case 1: return PadColor(red: x, green: 127, blue: 0)
        case 2: return PadColor(red: 0, green: 127, blue: x)
        case 3: return PadColor(red: 0, green: x, blue: 127)
        case 4: return PadColor(red: x, green: 0, blue: 127)
        default: return PadColor(red: 127, green: 0, blue: x)
        }
    }
}
