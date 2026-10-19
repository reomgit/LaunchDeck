// SPDX-License-Identifier: GPL-3.0-only
import Testing
@testable import LaunchDeckCore

struct MIDIDeviceConnectionsTests {
    private func pair(_ id: Int32, input: UInt32, output: UInt32, name: String = "LPProMK3 MIDI") -> MIDIEndpointPair {
        MIDIEndpointPair(
            input: MIDIEndpointIdentity(endpoint: input, uniqueID: id, device: UInt32(id), entity: UInt32(id), name: name, isSource: true),
            output: MIDIEndpointIdentity(endpoint: output, uniqueID: id + 1_000, device: UInt32(id), entity: UInt32(id), name: name, isSource: false)
        )
    }

    @Test func identicalModelsRouteIndependentlyToTheirOwnOutputs() throws {
        var devices = MIDIDeviceConnections()
        let pairs = [pair(10, input: 1, output: 2), pair(20, input: 3, output: 4)]
        let changed = devices.update(pairs, connect: { _ in true }, disconnect: { _ in })
        #expect(changed)
        #expect(devices.connections.map(\.deviceID) == [10, 20])
        let first = try #require(devices.connection(for: 10))
        let second = try #require(devices.connection(for: 20))
        #expect(first.pair.output.endpoint == 2)
        #expect(second.pair.output.endpoint == 4)
        #expect(first.token != second.token)
        #expect(devices.event(token: first.token, status: 0x90, data1: 11, data2: 127) == MIDIDeviceEvent(deviceID: 10, event: PadEvent(index: 0, phase: .pressed, generation: first.generation)))
        #expect(devices.event(token: second.token, status: 0xB0, data1: 90, data2: 0) == MIDIDeviceEvent(deviceID: 20, event: PadEvent(index: 104, phase: .released, generation: second.generation)))
    }

    @Test func removingOneDeviceKeepsOtherGenerationAndRejectsRemovedInput() throws {
        var devices = MIDIDeviceConnections()
        let first = pair(10, input: 1, output: 2)
        let second = pair(20, input: 3, output: 4)
        devices.update([first, second], connect: { _ in true }, disconnect: { _ in })
        let oldFirst = try #require(devices.connection(for: 10))
        let oldSecond = try #require(devices.connection(for: 20))
        var removed: [Int32] = []
        devices.update([second], connect: { _ in Issue.record("Existing device must not reconnect"); return true }, disconnect: { removed.append($0.deviceID) })
        #expect(removed == [10])
        #expect(devices.connection(for: 20)?.token == oldSecond.token)
        #expect(devices.event(token: oldFirst.token, status: 0x90, data1: 11, data2: 127) == nil)
        #expect(devices.event(token: oldSecond.token, status: 0x90, data1: 11, data2: 127)?.deviceID == 20)
    }

    @Test func repluggingStableUniqueIDRejectsDelayedOldConnectionToken() throws {
        var devices = MIDIDeviceConnections()
        devices.update([pair(10, input: 1, output: 2)], connect: { _ in true }, disconnect: { _ in })
        let previous = try #require(devices.connection(for: 10))
        devices.update([pair(10, input: 5, output: 6)], connect: { _ in true }, disconnect: { _ in })
        let current = try #require(devices.connection(for: 10))
        #expect(current.generation > previous.generation)
        #expect(devices.event(token: previous.token, status: 0x90, data1: 11, data2: 127) == nil)
        #expect(devices.event(token: current.token, status: 0x90, data1: 11, data2: 127)?.event.generation == current.generation)
        #expect(current.pair.output.endpoint == 6)
    }

    @Test func failedConnectionIsAbsentAndCanRetryWithoutDisturbingLiveDevice() throws {
        var devices = MIDIDeviceConnections()
        let pairs = [pair(10, input: 1, output: 2), pair(20, input: 3, output: 4)]
        devices.update(pairs, connect: { $0.deviceID == 10 }, disconnect: { _ in })
        #expect(devices.connection(for: 20) == nil)
        let firstToken = try #require(devices.connection(for: 10)?.token)
        let changed = devices.update(pairs, connect: { $0.deviceID == 20 }, disconnect: { _ in })
        #expect(changed)
        #expect(devices.connections.count == 2)
        #expect(devices.connection(for: 10)?.token == firstToken)
        let unchanged = devices.update(pairs, connect: { _ in false }, disconnect: { _ in })
        #expect(!unchanged)
    }

    @Test func stopDisconnectsEveryDeviceAndNeverReusesTokensOnRestart() throws {
        var devices = MIDIDeviceConnections()
        let pairs = [pair(10, input: 1, output: 2), pair(20, input: 3, output: 4)]
        devices.update(pairs, connect: { _ in true }, disconnect: { _ in })
        let previous = devices.connections
        var stopped: [Int32] = []
        devices.removeAll { stopped.append($0.deviceID) }
        #expect(stopped == [10, 20])
        #expect(devices.connections.isEmpty)
        devices.update(pairs, connect: { _ in true }, disconnect: { _ in })
        for connection in previous {
            #expect(devices.event(token: connection.token, status: 0x90, data1: 11, data2: 127) == nil)
            #expect(try #require(devices.connection(for: connection.deviceID)).generation > connection.generation)
        }
    }
}
