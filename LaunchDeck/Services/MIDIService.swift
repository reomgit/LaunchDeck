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
    let generation: Int
}

private final class MIDIConnectionState: @unchecked Sendable {
    private let lock = NSLock()
    private var generation = 0

    func advance() -> Int {
        lock.lock()
        defer { lock.unlock() }
        generation += 1
        return generation
    }

    func snapshot() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return generation
    }
}

/// This object is deliberately independent of `MIDIService`: CoreMIDI invokes
/// its receive block on a non-main real-time thread.
private final class MIDIInputReceiver: @unchecked Sendable {
    private let callbackState: MIDIConnectionState
    private let continuation: AsyncStream<MIDIInputEvent>.Continuation

    init(callbackState: MIDIConnectionState, continuation: AsyncStream<MIDIInputEvent>.Continuation) {
        self.callbackState = callbackState
        self.continuation = continuation
    }

    func receive(_ eventList: UnsafePointer<MIDIEventList>) {
        var messages = [MIDI1Message]()
        let generation = callbackState.snapshot()
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
        continuation.yield(MIDIInputEvent(messages: messages, generation: generation))
    }
}

@MainActor
@Observable
final class MIDIService {
    private(set) var connectionName: String?
    private(set) var connectionGeneration = 0
    private(set) var statusMessage = "Searching for Launchpad Mini MK3"

    var onPadEvent: (@MainActor (PadEvent) -> Void)?
    var onConnectionChanged: (@MainActor (Bool) -> Void)?

    @ObservationIgnored private var client = MIDIClientRef()
    @ObservationIgnored private var inputPort = MIDIPortRef()
    @ObservationIgnored private var source = MIDIEndpointRef()
    @ObservationIgnored private var destination = MIDIEndpointRef()
    @ObservationIgnored nonisolated private let callbackState: MIDIConnectionState
    @ObservationIgnored nonisolated private let inputReceiver: MIDIInputReceiver
    @ObservationIgnored private var inputTask: Task<Void, Never>?

    init() {
        let callbackState = MIDIConnectionState()
        let (stream, continuation) = AsyncStream.makeStream(
            of: MIDIInputEvent.self,
            bufferingPolicy: .bufferingNewest(128)
        )
        self.callbackState = callbackState
        inputReceiver = MIDIInputReceiver(callbackState: callbackState, continuation: continuation)
        inputTask = Task { @MainActor [weak self] in
            for await event in stream {
                guard !Task.isCancelled, let self else { return }
                self.receive(event.messages, generation: event.generation)
            }
        }
    }

    deinit {
        inputTask?.cancel()
    }

    func start() {
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
        let portStatus = MIDIInputPortCreateWithProtocol(client, "LaunchDeck Input" as CFString, ._1_0, &inputPort) { eventList, _ in
            receiver.receive(eventList)
        }
        guard portStatus == noErr else {
            statusMessage = "CoreMIDI input unavailable (\(portStatus))"
            return
        }
        connectIfAvailable()
    }

    func stop() {
        disconnect(restoreLiveMode: true, status: "Disconnected")
    }

    func connectIfAvailable() {
        guard client != 0, inputPort != 0, source == 0 else { return }
        let input = endpoints(kind: .source).first(where: isMiniMK3MIDIEndpoint)
        let output = endpoints(kind: .destination).first(where: isMiniMK3MIDIEndpoint)
        guard let input, let output else {
            statusMessage = "Connect Launchpad Mini MK3 MIDI"
            return
        }

        guard MIDIPortConnectSource(inputPort, input, nil) == noErr else {
            statusMessage = "Unable to connect to Launchpad input"
            return
        }
        source = input
        destination = output
        connectionGeneration = callbackState.advance()
        connectionName = endpointName(input)
        statusMessage = "Connected to \(connectionName ?? "Launchpad Mini MK3")"
        sendSysEx(MiniMK3Adapter.deviceInquiry)
        sendSysEx(MiniMK3Adapter.programmerModeOn)
        onConnectionChanged?(true)
    }

    func sendSysEx(_ bytes: [UInt8]) {
        guard destination != 0, !bytes.isEmpty else { return }
        PendingSysEx(destination: destination, bytes: bytes).send()
    }

    private func receive(_ messages: [MIDI1Message], generation: Int) {
        for message in messages {
            guard let event = MiniMK3Adapter.padEvent(
                status: message.status,
                data1: message.data1,
                data2: message.data2,
                generation: generation
            ) else { continue }
            onPadEvent?(event)
        }
    }

    private func refreshConnection() {
        guard client != 0, inputPort != 0 else { return }
        if source != 0 {
            let inputStillAvailable = endpoints(kind: .source).contains(source)
            let outputStillAvailable = endpoints(kind: .destination).contains(destination)
            if !inputStillAvailable || !outputStillAvailable {
                disconnect(restoreLiveMode: false, status: "Launchpad disconnected")
            }
        }
        connectIfAvailable()
    }

    private func disconnect(restoreLiveMode: Bool, status: String) {
        guard source != 0 else { return }
        if restoreLiveMode { sendSysEx(MiniMK3Adapter.programmerModeOff) }
        MIDIPortDisconnectSource(inputPort, source)
        source = 0
        destination = 0
        connectionName = nil
        connectionGeneration = callbackState.advance()
        statusMessage = status
        onConnectionChanged?(false)
    }

    private enum EndpointKind { case source, destination }

    private func endpoints(kind: EndpointKind) -> [MIDIEndpointRef] {
        let count = kind == .source ? MIDIGetNumberOfSources() : MIDIGetNumberOfDestinations()
        return (0..<count).map { kind == .source ? MIDIGetSource($0) : MIDIGetDestination($0) }.filter { $0 != 0 }
    }

    private func isMiniMK3MIDIEndpoint(_ endpoint: MIDIEndpointRef) -> Bool {
        let name = endpointName(endpoint).lowercased()
        return name.contains("lpminimk3") && name.contains("midi") && !name.contains("daw")
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
