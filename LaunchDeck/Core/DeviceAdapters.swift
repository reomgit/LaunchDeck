// SPDX-License-Identifier: GPL-3.0-only
import Foundation

enum DeviceModel: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case miniMK3, launchpadX, proMK3, virtual
    var id: String { rawValue }
    var descriptor: DeviceDescriptor { DeviceAdapter(model: self).descriptor }
    var displayName: String {
        switch self { case .miniMK3: "Launchpad Mini MK3"; case .launchpadX: "Launchpad X"; case .proMK3: "Launchpad Pro MK3"; case .virtual: "Virtual Deck" }
    }
}
struct DeviceControl: Identifiable, Hashable, Sendable {
    var id: Int { index }
    let index: Int
    let row: Int
    let column: Int
    let name: String
    let isGrid: Bool
    let midiNumber: UInt8?
}
struct DeviceDescriptor: Sendable {
    let model: DeviceModel
    let controls: [DeviceControl]
    var name: String { model.displayName }
    var controlCount: Int { controls.count }
    var rowCount: Int { (controls.map(\.row).max() ?? 0) + 1 }
    var columnCount: Int { (controls.map(\.column).max() ?? 0) + 1 }
}
/// Programmer mapping follows Novation's references; the Pro's logo (CC99) is LED-only.
struct DeviceAdapter: Sendable {
    let model: DeviceModel
    var descriptor: DeviceDescriptor { Self.descriptors[model]! }
    private static let descriptors: [DeviceModel: DeviceDescriptor] = Dictionary(uniqueKeysWithValues: DeviceModel.allCases.map {
        ($0, DeviceAdapter(model: $0).makeDescriptor())
    })
    private func makeDescriptor() -> DeviceDescriptor {
        var controls = (0..<64).map { index in
            DeviceControl(index: index, row: 8 - index / 8, column: index % 8 + 1, name: "Pad \(index + 1)", isGrid: true, midiNumber: model == .virtual ? nil : MiniMK3Adapter.midi1Note(forPadIndex: index))
        }
        if model != .virtual {
            let topNames: [String]
            switch model {
            case .miniMK3: topNames = ["Up", "Down", "Left", "Right", "Session", "Drums", "Keys", "User"]
            case .launchpadX: topNames = ["Up", "Down", "Left", "Right", "Session", "Note", "Custom", "Capture MIDI"]
            default: topNames = ["Left", "Right", "Session", "Note", "Chord", "Custom", "Sequencer", "Projects"]
            }
            controls += (0..<8).map { DeviceControl(index: 64 + $0, row: 0, column: $0 + 1, name: topNames[$0], isGrid: false, midiNumber: UInt8(91 + $0)) }
            let sideNames = model == .proMK3 ? ["Patterns", "Steps", "Pattern Settings", "Velocity", "Probability", "Mutation", "Micro-Step", "Print to Clip"] : (1...8).map { "Scene \($0)" }
            controls += (0..<8).map { DeviceControl(index: 72 + $0, row: $0 + 1, column: 9, name: model == .miniMK3 && $0 == 7 ? "Stop / Solo / Mute" : sideNames[$0], isGrid: false, midiNumber: UInt8(89 - $0 * 10)) }
        }
        if model == .proMK3 {
            let left = ["Up", "Down", "Clear", "Duplicate / Double", "Quantise", "Fixed Length", "Play", "Capture MIDI"]
            controls += (0..<8).map { DeviceControl(index: 80 + $0, row: $0 + 1, column: 0, name: left[$0], isGrid: false, midiNumber: UInt8(80 - $0 * 10)) }
            controls += (0..<8).map { DeviceControl(index: 88 + $0, row: 9, column: $0 + 1, name: "Track \($0 + 1)", isGrid: false, midiNumber: UInt8(101 + $0)) }
            let bottom = ["Record Arm", "Mute", "Solo", "Volume", "Pan", "Sends", "Device", "Stop Clip"]
            controls += (0..<8).map { DeviceControl(index: 96 + $0, row: 10, column: $0 + 1, name: bottom[$0], isGrid: false, midiNumber: UInt8(1 + $0)) }
            controls.append(DeviceControl(index: 104, row: 0, column: 0, name: "Shift", isGrid: false, midiNumber: 90))
        }
        return DeviceDescriptor(model: model, controls: controls)
    }
    private var header: [UInt8] {
        let product: UInt8 = model == .proMK3 ? 0x0E : model == .launchpadX ? 0x0C : 0x0D
        return [0xF0, 0, 0x20, 0x29, 2, product]
    }
    var programmerModeOn: [UInt8] { model == .virtual ? [] : header + [0x0E, 1, 0xF7] }
    var programmerModeOff: [UInt8] { model == .virtual ? [] : header + [0x0E, 0, 0xF7] }
    func event(status: UInt8, data1: UInt8, data2: UInt8, generation: Int) -> PadEvent? {
        guard model != .virtual, let control = descriptor.controls.first(where: { $0.midiNumber == data1 }) else { return nil }
        let kind = status & 0xF0
        guard (control.isGrid && (kind == 0x90 || kind == 0x80)) || (!control.isGrid && kind == 0xB0) else { return nil }
        return PadEvent(index: control.index, phase: kind == 0x80 || data2 == 0 ? .released : .pressed, generation: generation)
    }
    func rgbFrame(for colors: [Int: PadColor]) -> [UInt8] {
        guard model != .virtual else { return [] }
        var bytes = header + [0x03]
        for index in colors.keys.sorted() {
            guard let number = descriptor.controls[safe: index]?.midiNumber, let color = colors[index] else { continue }
            bytes += [3, number, color.red, color.green, color.blue]
        }
        return bytes + [0xF7]
    }
}

struct MIDIEndpointIdentity: Sendable, Hashable {
    let endpoint: UInt32
    let uniqueID: Int32
    let device: UInt32
    let entity: UInt32
    let name: String
    let isSource: Bool
    var model: DeviceModel? {
        let compact = name.lowercased().filter { $0.isLetter || $0.isNumber }
        guard compact.contains("midi"), !compact.contains("daw"), !compact.contains("din") else { return nil }
        if compact.contains("lpminimk3") || compact.contains("launchpadminimk3") { return .miniMK3 }
        if compact.contains("lppromk3") || compact.contains("launchpadpromk3") { return .proMK3 }
        if compact.contains("lpx") || compact.contains("launchpadx") { return .launchpadX }
        return nil
    }
}
struct MIDIEndpointPair: Sendable {
    let input: MIDIEndpointIdentity
    let output: MIDIEndpointIdentity
    var model: DeviceModel { input.model! }
}
enum MIDIEndpointPairing {
    static func selectedPair(_ pairs: [MIDIEndpointPair], uniqueID: Int32?) -> MIDIEndpointPair? {
        guard let uniqueID else { return pairs.first }
        return pairs.first { $0.input.uniqueID == uniqueID }
    }
    static func pairs(_ endpoints: [MIDIEndpointIdentity]) -> [MIDIEndpointPair] {
        endpoints.filter { $0.isSource && $0.model != nil && $0.device != 0 && $0.entity != 0 }.compactMap { input in
            guard let output = endpoints.first(where: { !$0.isSource && $0.device == input.device && $0.entity == input.entity && $0.model == input.model }) else { return nil }
            return MIDIEndpointPair(input: input, output: output)
        }
    }
}
