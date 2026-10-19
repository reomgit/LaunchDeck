import Foundation
import Testing
import ImageIO
import CoreGraphics
@testable import LaunchDeckCore

struct DeviceModelTests {
    @Test func legacySchemaTwoIsBackedUpAndMigrated() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let old = Configuration(schemaVersion: 2, profiles: [Profile(name: "Global", bindings: [PadBinding(index: 79, label: "Last", color: .blue, action: .shortcut(.copy))])])
        let bytes = try JSONEncoder().encode(old)
        let store = ProfileStore(directory: directory)
        try bytes.write(to: store.fileURL)
        let migrated = try store.load()
        #expect(migrated.schemaVersion == 3)
        #expect(try Data(contentsOf: directory.appendingPathComponent("profiles.v2.backup.json")) == bytes)
        #expect(migrated.profiles[0].bindings == old.profiles[0].bindings)
    }
}

extension DeviceModelTests {
    @Test func protocolsPreserveMiniAndMapEveryProPerimeterControl() {
        for model in [DeviceModel.miniMK3, .launchpadX, .proMK3] {
            let adapter = DeviceAdapter(model: model)
            #expect(adapter.descriptor.controlCount == (model == .proMK3 ? 105 : 80))
            for control in adapter.descriptor.controls {
                let event = adapter.event(status: control.isGrid ? 0x90 : 0xB0, data1: control.midiNumber!, data2: 127, generation: 7)
                #expect(event == PadEvent(index: control.index, phase: .pressed, generation: 7))
                #expect(adapter.event(status: control.isGrid ? 0x90 : 0xB0, data1: control.midiNumber!, data2: 0, generation: 8) == PadEvent(index: control.index, phase: .released, generation: 8))
                if control.isGrid { #expect(adapter.event(status: 0x80, data1: control.midiNumber!, data2: 127, generation: 9)?.phase == .released) }
            }
            for index in 0..<80 { #expect(adapter.descriptor.controls[index].midiNumber == MiniMK3Adapter.controlNumber(forIndex: index)) }
        }
        let pro = DeviceAdapter(model: .proMK3)
        #expect(pro.descriptor.controls[104].midiNumber == 90)
        #expect(pro.descriptor.controls[104].name == "Shift")
        #expect(pro.event(status: 0xB0, data1: 99, data2: 127, generation: 0) == nil)
        #expect(pro.descriptor.controls[88].midiNumber == 101)
        #expect(pro.descriptor.controls[96].midiNumber == 1)
        #expect(pro.programmerModeOn == [0xF0,0,0x20,0x29,2,0x0E,0x0E,1,0xF7])
        #expect(DeviceAdapter(model: .launchpadX).rgbFrame(for: [0: .blue])[5] == 0x0C)
        #expect(DeviceModel.virtual.descriptor.controlCount == 64)
    }
    @Test func layoutsAreIndependentAndInheritanceUsesSameModel() throws {
        var global = Profile(name: "Global", bindings: [PadBinding(index: 0, label: "Mini", color: .blue, action: .shortcut(.copy))])
        global.modelOverridesEnabled = true
        global.setLayout(DeckModelLayout(pages: [DeckPage(bindings: [PadBinding(index: 0, label: "Pro", color: .green, action: .shortcut(.paste))])]), for: .proMK3)
        global.setLayout(DeckModelLayout(), for: .virtual)
        var app = Profile(name: "App", applicationBundleIdentifier: "test.app")
        app.modelOverridesEnabled = true
        let resolver = ProfileResolver()
        #expect(resolver.resolve(profiles: [global,app], bundleIdentifier: "test.app", revision: 1, model: .proMK3).binding(at: 0)?.label == "Pro")
        #expect(resolver.resolve(profiles: [global,app], bundleIdentifier: "test.app", revision: 1, model: .virtual).binding(at: 0) == nil)
        #expect(global.bindings.first?.label == "Mini")
        #expect(try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(global)) == global)
    }
    @Test func copyPreviewReportsUnsupportedAssignmentsAndRetainsSource() {
        var profile = Profile(name: "Global")
        profile.modelOverridesEnabled = true
        profile.setLayout(DeckModelLayout(pages: [DeckPage(bindings: [PadBinding(index: 104, label: "Shift", color: .blue, action: .shortcut(.copy)), PadBinding(index: 0, label: "Grid", color: .green, action: .shortcut(.paste))])]), for: .proMK3)
        let preview = ConfigurationOperations.previewCopy(profile: profile, global: nil, from: .proMK3, to: .virtual)
        #expect(preview.unmappedBindings.count == 1)
        #expect(preview.layout.pages[0].bindings.map(\.index) == [0])
        #expect(profile.layout(for: .proMK3).pages[0].bindings.count == 2)
    }
    @Test func pairsPortsWithinDeviceEntityAndRejectsDAW() {
        let ports = [MIDIEndpointIdentity(endpoint: 1, uniqueID: 10, device: 100, entity: 101, name: "LPProMK3 MIDI", isSource: true), MIDIEndpointIdentity(endpoint: 2, uniqueID: 20, device: 200, entity: 201, name: "LPProMK3 MIDI", isSource: false), MIDIEndpointIdentity(endpoint: 3, uniqueID: 30, device: 100, entity: 101, name: "LPProMK3 MIDI", isSource: false), MIDIEndpointIdentity(endpoint: 4, uniqueID: 40, device: 100, entity: 102, name: "LPProMK3 DAW", isSource: false)]
        let pairs = MIDIEndpointPairing.pairs(ports)
        #expect(pairs.count == 1)
        #expect(pairs[0].input.endpoint == 1 && pairs[0].output.endpoint == 3)
    }
}

extension DeviceModelTests {
    @Test func portablePackageMaterializesAllModelsAndRemapsAllArtwork() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = ProfilePackageStore(directory: directory)
        let context = try #require(CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let png = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(png, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
        #expect(CGImageDestinationFinalize(destination))
        let art = try store.importArtwork(data: png as Data)
        var global = Profile(name: "Global")
        global.modelOverridesEnabled = true
        global.setLayout(DeckModelLayout(pages: [DeckPage(bindings: [PadBinding(index: 104, label: "Pro", color: .blue, action: .shortcut(.copy), artworkID: art)])]), for: .proMK3)
        var app = Profile(name: "App", applicationBundleIdentifier: "test.app")
        app.modelOverridesEnabled = true
        app.setLayout(DeckModelLayout(pages: [DeckPage(bindings: [PadBinding(index: 0, label: "Virtual", color: .green, action: .shortcut(.paste), artworkID: art)])]), for: .virtual)
        let package = directory.appendingPathComponent("test.launchdeckprofile")
        try store.export(profile: app, global: global, to: package)
        let imported = try store.importProfile(from: package)
        #expect(imported.kind == .manual)
        #expect(imported.id != app.id)
        #expect(imported.layout(for: .proMK3).pages[0].bindings.first?.label == "Pro")
        #expect(imported.layout(for: .virtual).pages[0].bindings.first?.label == "Virtual")
        let importedArt = try #require(imported.layout(for: .proMK3).pages[0].bindings.first?.artworkID)
        #expect(importedArt != art)
        #expect(imported.layout(for: .virtual).pages[0].bindings.first?.artworkID == importedArt)
        #expect(FileManager.default.fileExists(atPath: store.artworkURL(for: importedArt).path))
        let json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: package)) as? [String:Any])
        #expect(json["schemaVersion"] as? Int == 2)
        #expect(json["configurationSchemaVersion"] as? Int == 3)
        #expect((json["deviceModels"] as? [String])?.contains("proMK3") == true)
    }
    @Test func rejectsOutOfModelRangeAndInvalidAdditionalModelFolder() throws {
        var profile = Profile(name: "Global")
        profile.setLayout(DeckModelLayout(pages: [DeckPage(bindings: [PadBinding(index: 104, label: "Bad", color: .blue, action: .shortcut(.copy))])]), for: .virtual)
        #expect(throws: (any Error).self) { try ProfileStore().validate(Configuration(profiles: [profile])) }
        profile.setLayout(DeckModelLayout(pages: [DeckPage(folderID: UUID())]), for: .virtual)
        #expect(throws: (any Error).self) { try ProfileStore().validate(Configuration(profiles: [profile])) }
    }
}

extension DeviceModelTests {
    @Test @MainActor func reconnectRepaintSendsEveryOffEntryForDynamicDevice() {
        var messages: [[UInt8]] = []
        var model = DeviceModel.proMK3
        let renderer = LEDRenderer(model: { model }, send: { messages.append($0) })
        let pads = Array(repeating: ResolvedPad(binding: nil, sourceProfileID: nil, isDisabled: false), count: 105)
        renderer.render(ResolvedLayout(revision: 1, pads: pads, model: .proMK3), paused: false)
        messages.removeAll()
        renderer.repaint()
        #expect(messages.count == 1)
        #expect(messages[0].count == 8 + 105 * 5)
        #expect(messages[0][5] == 0x0E)
        model = .launchpadX
        renderer.repaint()
        #expect(messages[1].count == 8 + 80 * 5)
        #expect(messages[1][5] == 0x0C)
    }
}

extension DeviceModelTests {
    @Test func portableActionsSerializeAndValidateWithoutExecuting() throws {
        let script = ScriptAction(source: .inline("exit 7"), language: .shell)
        let actions: [MacroStep] = [.script(script), .extensionAction(ExtensionInvocation(extensionID: "example.tools", actionID: "hello")), .httpRequest(HTTPRequestAction(url: "https://example.com/status", allowedHosts: ["example.com"]))]
        #expect(try JSONDecoder().decode([MacroStep].self, from: JSONEncoder().encode(actions)) == actions)
        let profile = Profile(name: "Global", bindings: [PadBinding(index: 0, label: "Actions", color: .blue, action: .macro(actions))])
        try ProfileStore().validate(Configuration(profiles: [profile]))
        var invalid = profile
        invalid.bindings[0].action = .step(.extensionAction(ExtensionInvocation(extensionID: "", actionID: "hello")))
        #expect(throws: (any Error).self) { try ProfileStore().validate(Configuration(profiles: [invalid])) }
        invalid.bindings[0].action = .step(.script(ScriptAction(source: .inline(""), language: .shell)))
        #expect(throws: (any Error).self) { try ProfileStore().validate(Configuration(profiles: [invalid])) }
    }
}

extension DeviceModelTests {
    @Test func rejectsDuplicateLocalBindingsEvenWhenOverlayMergesThem() {
        let binding = PadBinding(index: 0, label: "Duplicate", color: .blue, action: .shortcut(.copy))
        let global = Profile(name: "Global", bindings: [binding])
        var app = Profile(name: "App", applicationBundleIdentifier: "test.app")
        app.setLayout(DeckModelLayout(pages: [DeckPage(bindings: [binding, binding])]), for: .launchpadX)
        #expect(throws: (any Error).self) { try ProfileStore().validate(Configuration(profiles: [global, app])) }
    }
    @Test func applicationInheritsGlobalModelOrderUnlessOverridden() {
        let first = DeckPage(id: UUID(), name: "First")
        let second = DeckPage(id: UUID(), name: "Second")
        var global = Profile(name: "Global")
        global.modelOverridesEnabled = true
        global.setLayout(DeckModelLayout(pages: [DeckPage(), first, second], pageOrder: [DeckPage.homeID, second.id, first.id]), for: .virtual)
        let app = Profile(name: "App", applicationBundleIdentifier: "test.app")
        #expect(ProfileResolver().effectivePages(profile: app, global: global, model: .virtual).map(\.id) == [DeckPage.homeID, second.id, first.id])
    }
}

extension DeviceModelTests {
    @Test func oldVersionTwoRetainsIDsOrderingActivationAndRejectsConflictingBackup() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let folder = DeckFolder(name: "Tools")
        let page = DeckPage(id: UUID(), name: "Second", folderID: folder.id, bindings: [PadBinding(index: 79, label: "Last", color: .green, action: .navigation(.home))])
        let global = Profile(name: "Global", pages: [DeckPage(),page], folders: [folder], pageOrder: [DeckPage.homeID,page.id], folderOrder: [folder.id])
        let configuration = Configuration(schemaVersion: 2, profiles: [global], selectedDeviceUniqueID: 1234, manuallyActivatedProfileID: global.id)
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(configuration)) as? [String:Any])
        var profiles = try #require(json["profiles"] as? [[String:Any]])
        profiles[0].removeValue(forKey: "modelLayouts"); json["profiles"] = profiles
        let oldBytes = try JSONSerialization.data(withJSONObject: json)
        let store = ProfileStore(directory: directory)
        try oldBytes.write(to: store.fileURL)
        let backup = directory.appendingPathComponent("profiles.v2.backup.json")
        try Data("Earlier original".utf8).write(to: backup)
        #expect(throws: (any Error).self) { try store.load() }
        #expect(try Data(contentsOf: store.fileURL) == oldBytes)
        try FileManager.default.removeItem(at: backup)
        let migrated = try store.load()
        #expect(migrated.profiles[0] == global)
        #expect(migrated.manuallyActivatedProfileID == global.id)
        #expect(migrated.selectedDeviceUniqueID == 1234)
        #expect(try Data(contentsOf: backup) == oldBytes)
    }
}

extension DeviceModelTests {
    @Test func explicitlySelectedMissingHardwareNeverFallsBack() {
        let input = MIDIEndpointIdentity(endpoint: 1, uniqueID: 10, device: 100, entity: 101, name: "LPX MIDI", isSource: true)
        let output = MIDIEndpointIdentity(endpoint: 2, uniqueID: 20, device: 100, entity: 101, name: "LPX MIDI", isSource: false)
        let pairs = MIDIEndpointPairing.pairs([input, output])
        #expect(MIDIEndpointPairing.selectedPair(pairs, uniqueID: nil)?.input.uniqueID == 10)
        #expect(MIDIEndpointPairing.selectedPair(pairs, uniqueID: 10)?.input.uniqueID == 10)
        #expect(MIDIEndpointPairing.selectedPair(pairs, uniqueID: 999) == nil)
    }
}

extension DeviceModelTests {
    @Test func importedScriptsReceiveFreshConsistentConsentIDsAcrossModels() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let script = ScriptAction(source: .inline("echo approval"), language: .shell)
        var profile = Profile(name: "Portable", bindings: [PadBinding(index: 0, label: "Script", color: .blue, action: .step(.script(script)))], kind: .manual)
        profile.modelOverridesEnabled = true
        profile.setLayout(DeckModelLayout(pages: [DeckPage(bindings: [PadBinding(index: 0, label: "Macro", color: .blue, action: .macro([.script(script), .delay(milliseconds: 1), .script(script)]))])]), for: .virtual)
        let store = ProfilePackageStore(directory: directory)
        let package = directory.appendingPathComponent("scripts.launchdeckprofile")
        try store.export(profile: profile, global: nil, to: package)
        let first = try store.importProfile(from: package)
        let second = try store.importProfile(from: package)
        guard case let .step(.script(firstScript)) = first.bindings[0].action,
              case let .step(.script(secondScript)) = second.bindings[0].action,
              case let .macro(steps) = first.layout(for: .virtual).pages[0].bindings[0].action,
              case let .script(macroFirst) = steps[0], case let .script(macroLast) = steps[2] else { Issue.record("Imported actions lost their structure"); return }
        #expect(firstScript.id != script.id)
        #expect(secondScript.id != firstScript.id)
        #expect(macroFirst.id == firstScript.id && macroLast.id == firstScript.id)
        #expect(firstScript.source == script.source)
        #expect(firstScript.arguments == script.arguments)
    }
}
