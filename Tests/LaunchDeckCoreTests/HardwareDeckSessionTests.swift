import Foundation
import Observation
import Testing
@testable import LaunchDeckCore

@MainActor
struct HardwareDeckSessionTests {
    @Test func appProfilesAndLiveInheritedEditsRefreshMultipleDevices() {
        var frames: [Int32: [Int: PadColor]] = [:]
        let mini = HardwareDeckSession(deviceID: 10, model: .miniMK3, generation: 1, send: { _ in })
        let pro = HardwareDeckSession(deviceID: 20, model: .proMK3, generation: 2, send: { _ in })
        mini.renderer.onFrame = { frames[10] = $0 }
        pro.renderer.onFrame = { frames[20] = $0 }
        defer { for session in [mini, pro] { session.renderer.stop(clear: false) } }
        var global = Profile(name: "Global", bindings: [PadBinding(index: 0, label: "Copy", color: .blue, action: .shortcut(.copy))])
        let first = Profile(name: "First", applicationBundleIdentifier: "test.first", bindings: [PadBinding(index: 0, label: "Paste", color: .orange, action: .shortcut(.paste))])
        let second = Profile(name: "Second", applicationBundleIdentifier: "test.second")
        for session in [mini, pro] {
            session.update(profiles: [global, first, second], bundleIdentifier: "test.first", profileID: nil, revision: 1, paused: false)
            #expect(session.layout.binding(at: 0)?.action == .shortcut(.paste))
            #expect(frames[session.deviceID]?[0] == .orange)
            session.update(profiles: [global, first, second], bundleIdentifier: "test.second", profileID: nil, revision: 2, paused: false)
            #expect(session.layout.binding(at: 0)?.action == .shortcut(.copy))
            #expect(frames[session.deviceID]?[0] == .blue)
        }
        global.bindings[0].color = .green
        for session in [mini, pro] {
            session.update(profiles: [global, first, second], bundleIdentifier: "test.second", profileID: nil, revision: 3, paused: false)
            #expect(frames[session.deviceID]?[0] == .green)
            session.update(profiles: [global, first, second], bundleIdentifier: "test.other", profileID: nil, revision: 4, paused: false)
            #expect(session.layout.binding(at: 0)?.label == "Copy")
            #expect(frames[session.deviceID]?[0] == .green)
        }
    }

    @Test func unchangedDeviceLayoutKeepsItsOwnInFlightLighting() {
        var frame: [Int: PadColor] = [:]
        let session = HardwareDeckSession(deviceID: 10, model: .miniMK3, generation: 1, send: { _ in })
        session.renderer.onFrame = { frame = $0 }
        var profile = Profile(name: "Global", bindings: [PadBinding(index: 0, label: "One", color: .blue, action: .shortcut(.copy))])
        session.update(profiles: [profile], bundleIdentifier: nil, profileID: profile.id, revision: 1, paused: false)
        session.renderer.flash(index: 0, color: .orange, durationNanoseconds: 1_000_000_000)
        #expect(frame[0] == .orange)
        session.update(profiles: [profile], bundleIdentifier: nil, profileID: profile.id, revision: 2, paused: false)
        #expect(frame[0] == .orange)
        #expect(session.layout.revision == 1)
        profile.bindings[0].color = .green
        session.update(profiles: [profile], bundleIdentifier: nil, profileID: profile.id, revision: 3, paused: false)
        #expect(frame[0] == .green)
        #expect(session.layout.revision == 3)
        session.renderer.stop(clear: false)
    }

    private final class Changes: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func record() { lock.lock(); count += 1; lock.unlock() }
        var observed: Bool { lock.lock(); defer { lock.unlock() }; return count > 0 }
    }

    @Test func deviceNavigationNotifiesTheRuntimeHeader() {
        let session = HardwareDeckSession(deviceID: 10, model: .miniMK3, generation: 1, send: { _ in })
        let second = DeckPage(id: UUID(), name: "Second")
        let profile = Profile(name: "Global", pages: [DeckPage(), second])
        session.update(profiles: [profile], bundleIdentifier: nil, profileID: profile.id, revision: 1, paused: false)
        let changes = Changes()
        withObservationTracking { _ = session.pageID } onChange: { changes.record() }
        #expect(session.navigate(.nextPage))
        #expect(changes.observed)
    }

    @Test func twoDevicesKeepNavigationAndHeldPadsIndependent() {
        let first = HardwareDeckSession(deviceID: 10, model: .miniMK3, generation: 1, send: { _ in })
        let second = HardwareDeckSession(deviceID: 20, model: .launchpadX, generation: 2, send: { _ in })
        let extra = DeckPage(id: UUID(), name: "Second")
        let profile = Profile(name: "Global", pages: [DeckPage(), extra])
        for session in [first, second] { session.update(profiles: [profile], bundleIdentifier: nil, profileID: profile.id, revision: 1, paused: false) }
        #expect(first.navigate(.nextPage))
        #expect(first.pageID == extra.id)
        #expect(second.pageID == DeckPage.homeID)
        #expect(first.accept(PadEvent(index: 0, phase: .pressed, generation: 1)))
        #expect(second.accept(PadEvent(index: 0, phase: .pressed, generation: 2)))
        #expect(!first.accept(PadEvent(index: 0, phase: .pressed, generation: 1)))
        #expect(!second.accept(PadEvent(index: 1, phase: .pressed, generation: 1)))
        #expect(!first.accept(PadEvent(index: 0, phase: .released, generation: 1)))
        #expect(first.accept(PadEvent(index: 0, phase: .pressed, generation: 1)))
    }

    @Test func paintingOneDeviceDoesNotSendAnotherModelsProtocol() {
        var firstMessages: [[UInt8]] = []
        var secondMessages: [[UInt8]] = []
        let first = HardwareDeckSession(deviceID: 10, model: .miniMK3, generation: 1, send: { firstMessages.append($0) })
        let second = HardwareDeckSession(deviceID: 20, model: .proMK3, generation: 2, send: { secondMessages.append($0) })
        let profile = Profile(name: "Global", bindings: [PadBinding(index: 0, label: "Common", color: .green, action: .shortcut(.copy))])
        first.update(profiles: [profile], bundleIdentifier: nil, profileID: profile.id, revision: 1, paused: false)
        second.update(profiles: [profile], bundleIdentifier: nil, profileID: profile.id, revision: 1, paused: false)
        #expect(firstMessages.count == 1 && firstMessages[0][5] == 0x0D)
        #expect(secondMessages.count == 1 && secondMessages[0][5] == 0x0E)
        #expect(first.layout.binding(at: 0)?.label == "Common")
        #expect(second.layout.binding(at: 0)?.label == "Common")
        firstMessages.removeAll(); secondMessages.removeAll()
        first.renderer.repaint()
        #expect(firstMessages.count == 1)
        #expect(secondMessages.isEmpty)
    }
}
