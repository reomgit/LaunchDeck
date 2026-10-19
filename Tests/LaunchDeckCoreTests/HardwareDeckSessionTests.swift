import Foundation
import Observation
import Testing
@testable import LaunchDeckCore

@MainActor
struct HardwareDeckSessionTests {
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
