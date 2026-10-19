// SPDX-License-Identifier: GPL-3.0-only

struct MIDIDeviceEvent: Sendable, Equatable {
    let deviceID: Int32
    let event: PadEvent
}

struct MIDIDeviceConnection: Sendable {
    let pair: MIDIEndpointPair
    /// Copied into CoreMIDI's source context, never dereferenced as a pointer.
    let token: Int
    var deviceID: Int32 { pair.input.uniqueID }
    var generation: Int { token }

    func matches(_ candidate: MIDIEndpointPair) -> Bool {
        deviceID == candidate.input.uniqueID
            && pair.input.endpoint == candidate.input.endpoint
            && pair.output.endpoint == candidate.output.endpoint
            && pair.output.uniqueID == candidate.output.uniqueID
            && pair.model == candidate.model
    }
}

/// Main-actor-owned connection bookkeeping, independent of CoreMIDI calls.
/// A token identifies one connection lifetime; endpoint IDs identify the device
/// across reconnections. Both input decoding and output targeting use this table.
struct MIDIDeviceConnections {
    private(set) var connections: [MIDIDeviceConnection] = []
    private var nextToken = 0

    func connection(for deviceID: Int32) -> MIDIDeviceConnection? {
        connections.first { $0.deviceID == deviceID }
    }

    @discardableResult
    mutating func update(
        _ pairs: [MIDIEndpointPair],
        connect: (MIDIDeviceConnection) -> Bool,
        disconnect: (MIDIDeviceConnection) -> Void
    ) -> Bool {
        let removed = connections.filter { connection in !pairs.contains(where: connection.matches) }
        connections.removeAll { connection in removed.contains { $0.token == connection.token } }
        for connection in removed { disconnect(connection) }
        var changed = !removed.isEmpty
        for pair in pairs where connection(for: pair.input.uniqueID) == nil {
            nextToken += 1
            let connection = MIDIDeviceConnection(pair: pair, token: nextToken)
            guard connect(connection) else { continue }
            connections.append(connection)
            changed = true
        }
        return changed
    }

    mutating func removeAll(disconnect: (MIDIDeviceConnection) -> Void) {
        let previous = connections
        connections.removeAll()
        for connection in previous { disconnect(connection) }
    }

    func event(token: Int, status: UInt8, data1: UInt8, data2: UInt8) -> MIDIDeviceEvent? {
        guard let connection = connections.first(where: { $0.token == token }),
              let event = DeviceAdapter(model: connection.pair.model).event(
                status: status, data1: data1, data2: data2, generation: connection.generation
              ) else { return nil }
        return MIDIDeviceEvent(deviceID: connection.deviceID, event: event)
    }
}
