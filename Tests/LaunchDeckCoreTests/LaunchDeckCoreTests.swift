// SPDX-License-Identifier: GPL-3.0-only
// Copyright © 2026 Reom Nagasaka

import Foundation
import Testing
@testable import LaunchDeckCore

struct LaunchDeckCoreTests {
    @Test("A new configuration starts with an empty Global preset")
    func defaultConfigurationHasNoBindings() {
        let configuration = Configuration.default

        #expect(configuration.profiles.count == 1)
        #expect(configuration.profiles[0].isGlobal)
        #expect(configuration.profiles[0].bindings.isEmpty)
    }

    @Test("An app profile overrides only its assigned pads")
    func resolvesApplicationProfileOverGlobalFallback() {
        let global = Profile(
            name: "Global",
            applicationBundleIdentifier: nil,
            bindings: [
                PadBinding(index: 0, label: "Copy", color: .blue, action: .shortcut(.copy)),
                PadBinding(index: 1, label: "Paste", color: .green, action: .shortcut(.paste)),
            ]
        )
        let safari = Profile(
            name: "Safari",
            applicationBundleIdentifier: "com.apple.Safari",
            bindings: [
                PadBinding(index: 0, label: "New Tab", color: .orange, action: .shortcut(.newTab)),
            ]
        )

        let layout = ProfileResolver().resolve(
            profiles: [global, safari],
            bundleIdentifier: "com.apple.Safari",
            revision: 4
        )

        #expect(layout.revision == 4)
        #expect(layout.binding(at: 0)?.label == "New Tab")
        #expect(layout.binding(at: 1)?.label == "Paste")
    }

    @Test("A disabled app binding suppresses its inherited global action")
    func disabledBindingSuppressesGlobalFallback() {
        let global = Profile(name: "Global", applicationBundleIdentifier: nil, bindings: [
            PadBinding(index: 12, label: "Copy", color: .blue, action: .shortcut(.copy)),
        ])
        let app = Profile(name: "App", applicationBundleIdentifier: "dev.reom.App", bindings: [
            PadBinding(index: 12, label: "Disabled", color: .off, action: .disabled),
        ])

        let layout = ProfileResolver().resolve(profiles: [global, app], bundleIdentifier: "dev.reom.App", revision: 1)

        #expect(layout.binding(at: 12) == nil)
        #expect(layout.pad(at: 12)?.isDisabled == true)
    }

    @Test("LED SysEx encodes an RGB pad update")
    func encodesRGBLEDUpdate() {
        let frame = MiniMK3Adapter.rgbFrame(for: [
            0: .init(red: 127, green: 16, blue: 0),
        ])

        #expect(frame == [0xF0, 0x00, 0x20, 0x29, 0x02, 0x0D, 0x03, 0x03, 0x0B, 127, 16, 0, 0xF7])
    }

    @Test("Device inquiry uses the universal identity request")
    func createsDeviceInquiry() {
        #expect(MiniMK3Adapter.deviceInquiry == [0xF0, 0x7E, 0x7F, 0x06, 0x01, 0xF7])
    }

    @Test("MIDI note messages decode pad presses and releases")
    func decodesPadEvents() {
        let press = MiniMK3Adapter.padEvent(status: 0x90, data1: 0x0B, data2: 100, generation: 2)
        let release = MiniMK3Adapter.padEvent(status: 0x90, data1: 0x0B, data2: 0, generation: 2)

        #expect(press == PadEvent(index: 0, phase: .pressed, generation: 2))
        #expect(release == PadEvent(index: 0, phase: .released, generation: 2))
        #expect(MiniMK3Adapter.padEvent(status: 0xB0, data1: 0x0B, data2: 100, generation: 2) == nil)
    }

    @Test("All 64 physical pad mappings round-trip with documented corners")
    func mapsEveryPad() {
        #expect(MiniMK3Adapter.midi1Note(forPadIndex: 0) == 0x0B)
        #expect(MiniMK3Adapter.midi1Note(forPadIndex: 7) == 0x12)
        #expect(MiniMK3Adapter.midi1Note(forPadIndex: 56) == 0x51)
        #expect(MiniMK3Adapter.midi1Note(forPadIndex: 63) == 0x58)

        for index in 0..<64 {
            let note = MiniMK3Adapter.midi1Note(forPadIndex: index)
            #expect(note.flatMap(MiniMK3Adapter.padIndex(forMIDI1Note:)) == index)
        }
    }

    @Test("Configuration persists and loads from the application support store")
    func persistsConfiguration() throws {
        let directory = URL(filePath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }

        let expected = Configuration(profiles: [
            Profile(name: "Global", applicationBundleIdentifier: nil, bindings: [
                PadBinding(index: 7, label: "Close", color: .amber, action: .shortcut(.copy)),
            ]),
        ])
        let store = ProfileStore(directory: directory)

        try store.save(expected)
        let loaded = try store.load()

        #expect(loaded == expected)
    }

    @Test("The store rejects unsupported schema versions and invalid MIDI RGB values")
    func rejectsMalformedConfiguration() throws {
        let directory = URL(filePath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProfileStore(directory: directory)

        let unsupported = Configuration(schemaVersion: 99, profiles: [Profile(name: "Global", applicationBundleIdentifier: nil)])
        #expect(throws: Error.self) { try store.save(unsupported) }

        let invalidColor = Configuration(profiles: [Profile(name: "Global", applicationBundleIdentifier: nil, bindings: [
            PadBinding(index: 0, label: "Invalid", color: .init(red: 200, green: 0, blue: 0), action: .shortcut(.copy)),
        ])])
        #expect(throws: Error.self) { try store.save(invalidColor) }
    }

    @Test("Actions expand into an ordered executable sequence")
    func expandsMacroActions() {
        let action = BindingAction.macro([.shortcut(.copy), .delay(milliseconds: 120), .shortcut(.paste)])

        #expect(ActionPlanner.steps(for: action) == [.shortcut(.copy), .delay(milliseconds: 120), .shortcut(.paste)])
        #expect(ActionPlanner.steps(for: .disabled).isEmpty)
    }
}
