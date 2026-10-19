// SPDX-License-Identifier: GPL-3.0-only
// Copyright © 2026 Reom Nagasaka

import CoreMIDI
import Foundation
import Observation

private struct MIDI1Message: Sendable {
    let status: UInt8
    let data1: UInt8
    let data2: UInt8
}

private struct MIDIInputEvent: Sendable {
    let messages: [MIDI1Message]
    let token: Int
}

/// This object is deliberately independent of `MIDIService`: CoreMIDI invokes
/// its receive block on a non-main real-time thread.
private final class MIDIInputReceiver: @unchecked Sendable {
    private let continuation: AsyncStream<MIDIInputEvent>.Continuation

    init(continuation: AsyncStream<MIDIInputEvent>.Continuation) {
        self.continuation = continuation
    }

    func receive(_ eventList: UnsafePointer<MIDIEventList>, token: Int) {
        var messages = [MIDI1Message]()
        var packet = withUnsafePointer(to: eventList.pointee.packet) {
            UnsafeRawPointer($0).assumingMemoryBound(to: MIDIEventPacket.self)
        }

        for _ in 0..<Int(eventList.pointee.numPackets) {
            let wordCount = Int(packet.pointee.wordCount)
            withUnsafePointer(to: packet.pointee.words) { tuple in
                tuple.withMemoryRebound(to: UInt32.self, capacity: wordCount) { words in
                    for index in 0..<wordCount {
                        let word = words[index]
                        guard (word & 0xF000_0000) == 0x2000_0000 else { continue }
                        messages.append(MIDI1Message(
                            status: UInt8((word >> 16) & 0xFF),
                            data1: UInt8((word >> 8) & 0x7F),
                            data2: UInt8(word & 0x7F)
                        ))
                    }
                }
            }
            packet = UnsafePointer(MIDIEventPacketNext(packet))
        }

        guard !messages.isEmpty else { return }
        continuation.yield(MIDIInputEvent(messages: messages, token: token))
    }
}

struct MIDIDeviceChoice: Identifiable, Hashable, Sendable {
    let id: Int32
    let name: String
    let model: DeviceModel
}

@MainActor
@Observable
final class MIDIService {
    private(set) var connectionName: String?
    private(set) var connectionGeneration = 0
    private(set) var statusMessage = "Searching for Launchpad"
    private(set) var devices: [MIDIDeviceChoice] = []
    private(set) var connectedDevices: [MIDIDeviceChoice] = []
    private(set) var selectedDeviceUniqueID: Int32?
    private(set) var connectedModel: DeviceModel?

    var onDevicePadEvent: (@MainActor (MIDIDeviceEvent) -> Void)?
    var onDevicesChanged: (@MainActor () -> Void)?

    var onPadEvent: (@MainActor (PadEvent) -> Void)?
    var onConnectionChanged: (@MainActor (Bool) -> Void)?

    @ObservationIgnored private var client = MIDIClientRef()
    @ObservationIgnored private var inputPort = MIDIPortRef()
    @ObservationIgnored private var connections = MIDIDeviceConnections()
    @ObservationIgnored private var facadeDeviceID: Int32?
    @ObservationIgnored nonisolated private let inputReceiver: MIDIInputReceiver
    @ObservationIgnored private var inputTask: Task<Void, Never>?
    @ObservationIgnored private var isEnabled = false

    init() {
        let (stream, continuation) = AsyncStream.makeStream(
            of: MIDIInputEvent.self,
            bufferingPolicy: .bufferingNewest(128)
        )
        inputReceiver = MIDIInputReceiver(continuation: continuation)
        inputTask = Task { @MainActor [weak self] in
            for await event in stream {
                guard !Task.isCancelled, let self else { return }
                self.receive(event.messages, token: event.token)
            }
        }
    }

    deinit {
        inputTask?.cancel()
    }

    func start() {
        isEnabled = true
        guard client == 0 else {
            connectIfAvailable()
            return
        }

        let clientStatus = MIDIClientCreateWithBlock("LaunchDeck" as CFString, &client) { [weak self] _ in
            Task { @MainActor in self?.refreshConnection() }
        }
        guard clientStatus == noErr else {
            statusMessage = "CoreMIDI client unavailable (\(clientStatus))"
            return
        }

        let receiver = inputReceiver
        let portStatus = MIDIInputPortCreateWithProtocol(
            client,
            "LaunchDeck Input" as CFString,
            ._1_0,
            &inputPort,
            MIDIService.inputReceiveBlock(for: receiver)
        )
        guard portStatus == noErr else {
            statusMessage = "CoreMIDI input unavailable (\(portStatus))"
            return
        }
        connectIfAvailable()
    }

    func stop() {
        isEnabled = false
        let port = inputPort
        connections.removeAll { connection in
            // Restore every live unit before disconnecting its source.
            PendingSysEx(
                destination: connection.pair.output.endpoint,
                bytes: DeviceAdapter(model: connection.pair.model).programmerModeOff
            ).send()
            MIDIPortDisconnectSource(port, connection.pair.input.endpoint)
        }
        publishConnections(status: "Disconnected")
    }

    func connectIfAvailable() {
        guard isEnabled, client != 0, inputPort != 0 else { return }
        let pairs = availablePairs()
        devices = pairs.map { MIDIDeviceChoice(id: $0.input.uniqueID, name: $0.input.name, model: $0.model) }
        let port = inputPort
        let changed = connections.update(pairs, connect: { connection in
            // CoreMIDI copies this opaque token for this specific source lifetime.
            // No callback may substitute the currently selected device's generation.
            guard MIDIPortConnectSource(
                port, connection.pair.input.endpoint,
                UnsafeMutableRawPointer(bitPattern: connection.token)
            ) == noErr else { return false }
            PendingSysEx(destination: connection.pair.output.endpoint, bytes: MiniMK3Adapter.deviceInquiry).send()
            PendingSysEx(
                destination: connection.pair.output.endpoint,
                bytes: DeviceAdapter(model: connection.pair.model).programmerModeOn
            ).send()
            return true
        }, disconnect: { connection in
            MIDIPortDisconnectSource(port, connection.pair.input.endpoint)
        })
        publishConnections(notifyDevicesChanged: changed)
    }

    func selectDevice(_ uniqueID: Int32?) {
        guard selectedDeviceUniqueID != uniqueID else { return }
        selectedDeviceUniqueID = uniqueID
        updateSelectedFacade()
    }

    func sendSysEx(_ bytes: [UInt8]) {
        guard let deviceID = facadeDeviceID else { return }
        sendSysEx(bytes, to: deviceID)
    }

    func sendSysEx(_ bytes: [UInt8], to deviceID: Int32) {
        guard let connection = connections.connection(for: deviceID), !bytes.isEmpty else { return }
        PendingSysEx(destination: connection.pair.output.endpoint, bytes: bytes).send()
    }

    func generation(for deviceID: Int32) -> Int? {
        connections.connection(for: deviceID)?.generation
    }

    private func receive(_ messages: [MIDI1Message], token: Int) {
        guard isEnabled else { return }
        for message in messages {
            guard let routed = connections.event(token: token, status: message.status, data1: message.data1, data2: message.data2) else { continue }
            onDevicePadEvent?(routed)
            if routed.deviceID == facadeDeviceID, routed.event.generation == connectionGeneration {
                onPadEvent?(routed.event)
            }
        }
    }

    nonisolated private static func inputReceiveBlock(for receiver: MIDIInputReceiver) -> MIDIReceiveBlock {
        { eventList, sourceContext in
            guard let sourceContext else { return }
            receiver.receive(eventList, token: Int(bitPattern: sourceContext))
        }
    }

    private func refreshConnection() {
        connectIfAvailable()
    }

    private func publishConnections(status: String? = nil, notifyDevicesChanged: Bool = true) {
        connectedDevices = connections.connections.map {
            MIDIDeviceChoice(id: $0.deviceID, name: $0.pair.input.name, model: $0.pair.model)
        }
        updateSelectedFacade(status: status)
        // Consumers see the complete new connection table and selected facade.
        if notifyDevicesChanged { onDevicesChanged?() }
    }

    private func updateSelectedFacade(status: String? = nil) {
        let selected = selectedDeviceUniqueID.flatMap { connections.connection(for: $0) }
            ?? (selectedDeviceUniqueID == nil ? connections.connections.first : nil)
        let oldID = facadeDeviceID
        let oldGeneration = connectionGeneration
        facadeDeviceID = selected?.deviceID
        connectionName = selected?.pair.input.name
        connectedModel = selected?.pair.model
        connectionGeneration = selected?.generation ?? 0
        statusMessage = status ?? (connectionName.map { "Connected to \($0)" }
            ?? (selectedDeviceUniqueID == nil ? "Connect a supported Launchpad MIDI port" : "Selected Launchpad is unavailable"))
        if oldID != facadeDeviceID || oldGeneration != connectionGeneration {
            if oldID != nil { onConnectionChanged?(false) }
            if facadeDeviceID != nil { onConnectionChanged?(true) }
        }
    }

    private enum EndpointKind { case source, destination }

    private func endpoints(kind: EndpointKind) -> [MIDIEndpointRef] {
        let count = kind == .source ? MIDIGetNumberOfSources() : MIDIGetNumberOfDestinations()
        return (0..<count).map { kind == .source ? MIDIGetSource($0) : MIDIGetDestination($0) }.filter { $0 != 0 }
    }

    private func availablePairs() -> [MIDIEndpointPair] {
        let identities = [EndpointKind.source, .destination].flatMap { kind in
            endpoints(kind: kind).map { endpoint in
                var entity = MIDIEntityRef(); var device = MIDIDeviceRef(); var uniqueID: Int32 = 0
                MIDIEndpointGetEntity(endpoint, &entity)
                if entity != 0 { MIDIEntityGetDevice(entity, &device) }
                MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &uniqueID)
                return MIDIEndpointIdentity(endpoint: endpoint, uniqueID: uniqueID, device: device, entity: entity, name: endpointName(endpoint), isSource: kind == .source)
            }
        }
        return MIDIEndpointPairing.pairs(identities)
    }

    private func endpointName(_ endpoint: MIDIEndpointRef) -> String {
        var name: Unmanaged<CFString>?
        guard MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &name) == noErr else { return "Launchpad Mini MK3" }
        return name?.takeRetainedValue() as String? ?? "Launchpad Mini MK3"
    }
}

private final class PendingSysEx {
    private let buffer: UnsafeMutablePointer<UInt8>
    private let bufferCount: Int
    private var request: MIDISysexSendRequest

    init(destination: MIDIEndpointRef, bytes: [UInt8]) {
        bufferCount = bytes.count
        buffer = .allocate(capacity: bytes.count)
        buffer.initialize(from: bytes, count: bytes.count)
        request = MIDISysexSendRequest(
            destination: destination,
            data: UnsafePointer(buffer),
            bytesToSend: UInt32(bytes.count),
            complete: false,
            reserved: (0, 0, 0),
            completionProc: PendingSysEx.complete,
            completionRefCon: nil
        )
    }

    deinit {
        buffer.deinitialize(count: bufferCount)
        buffer.deallocate()
    }

    func send() {
        request.completionRefCon = Unmanaged.passRetained(self).toOpaque()
        if MIDISendSysex(&request) != noErr {
            Unmanaged<PendingSysEx>.fromOpaque(request.completionRefCon!).release()
        }
    }

    private static let complete: MIDICompletionProc = { request in
        guard let refCon = request.pointee.completionRefCon else { return }
        Unmanaged<PendingSysEx>.fromOpaque(refCon).release()
    }
}
