// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Network
import Darwin
import Testing
@testable import LaunchDeckCore

@MainActor
struct CompanionTests {
    private func ready(_ server: CompanionServer) async throws -> URL {
        try server.start(loopbackOnly: true)
        for _ in 0..<100 {
            if let url = server.urls.first { return url }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw NSError(domain: "CompanionTest", code: 1)
    }

    private func request(_ base: URL, _ path: String, method: String = "GET", token: String? = nil,
                         body: [String: Any]? = nil, origin: String? = nil) async throws -> (Data, Int) {
        var request = URLRequest(url: base.appending(path: path))
        request.httpMethod = method
        request.timeoutInterval = 3
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let origin { request.setValue(origin, forHTTPHeaderField: "Origin") }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as! HTTPURLResponse).statusCode)
    }

    private func pair(_ server: CompanionServer, _ base: URL, name: String = "Test phone") async throws -> String {
        let (data, status) = try await request(base, "api/pair", method: "POST", body: ["code": server.pairingCode, "name": name])
        #expect(status == 200)
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        return try #require(object["token"] as? String)
    }

    @Test("Loopback pairing protects snapshots and gives independently revocable sessions")
    func pairingAndRevocation() async throws {
        let server = CompanionServer()
        defer { server.stop() }
        let pageID = UUID()
        server.onSnapshot = { CompanionSnapshot(revision: 42, profileName: "Writing", mode: "Auto", pageID: pageID, pageName: "Main", controls: [CompanionControl(index: 0, row: 0, column: 0, label: "Save", action: "Keyboard shortcut", color: "#ff0000")]) }
        let base = try await ready(server)
        let unauthenticated = try await request(base, "api/snapshot")
        #expect(unauthenticated.1 == 401)
        #expect(!String(decoding: unauthenticated.0, as: UTF8.self).contains("Writing"))
        let badPair = try await request(base, "api/pair", method: "POST", body: ["code": "wrong"])
        #expect(badPair.1 == 401)
        let first = try await pair(server, base)
        let firstID = try #require(server.clients.first?.id)
        let second = try await pair(server, base, name: "Tablet")
        #expect(first != second)
        let snapshot = try await request(base, "api/snapshot", token: first)
        #expect(snapshot.1 == 200)
        let decoded = try JSONDecoder().decode(CompanionSnapshot.self, from: snapshot.0)
        #expect(decoded.revision == 42)
        #expect(decoded.controls.first?.label == "Save")
        server.onSnapshot = { CompanionSnapshot(revision: 43, profileName: "Updated deck", mode: "Manual", pageID: pageID, pageName: "Main") }
        let updated = try await request(base, "api/snapshot", token: first)
        #expect(try JSONDecoder().decode(CompanionSnapshot.self, from: updated.0).revision == 43)
        var cancellationCount = 0
        server.onStop = { cancellationCount += 1 }
        server.revokeClient(id: firstID)
        #expect(cancellationCount == 1)
        #expect(try await request(base, "api/snapshot", token: first).1 == 401)
        #expect(try await request(base, "api/snapshot", token: second).1 == 200)
        server.stop()
        #expect(cancellationCount == 2)
        #expect(server.clients.isEmpty)
        #expect(server.urls.isEmpty)
        #expect(!server.isRunning)
    }

    @Test("Expired pairing and foreign origins fail before callbacks; stale presses return conflict")
    func expiryOriginsAndCallbacks() async throws {
        var now = Date()
        let server = CompanionServer(now: { now }, pairingLifetime: 1)
        defer { server.stop() }
        let pageID = UUID()
        server.onSnapshot = { CompanionSnapshot(revision: 3, profileName: "Deck", mode: "Manual", pageID: pageID, pageName: "Page") }
        let base = try await ready(server)
        now = now.addingTimeInterval(2)
        #expect(try await request(base, "api/pair", method: "POST", body: ["code": server.pairingCode]).1 == 401)
        server.renewPairingCode()
        let token = try await pair(server, base)
        #expect(try await request(base, "api/snapshot", token: token, origin: "https://evil.example").1 == 403)
        var presses = [Int]()
        server.onPress = { index, revision, page in
            guard revision == 3, page == pageID else { return "Deck changed. Refresh." }
            presses.append(index)
            return nil
        }
        let stale = try await request(base, "api/press", method: "POST", token: token, body: ["index": 0, "revision": 2, "pageID": pageID.uuidString])
        #expect(stale.1 == 409)
        #expect(presses.isEmpty)
        #expect(try await request(base, "api/press", method: "POST", token: token, body: ["index": 4, "revision": 3, "pageID": pageID.uuidString]).1 == 200)
        #expect(presses == [4])
        var activated: UUID?
        server.onActivate = { activated = $0; return nil }
        let profileID = UUID()
        #expect(try await request(base, "api/activate", method: "POST", token: token, body: ["profileID": profileID.uuidString]).1 == 200)
        #expect(activated == profileID)
        #expect(try await request(base, "api/activate", method: "POST", token: token, body: [:]).1 == 200)
        #expect(activated == nil)
        server.onArtwork = { $0 == "safe" ? Data([137, 80, 78, 71]) : nil }
        #expect(try await request(base, "api/artwork/safe", token: token).0 == Data([137, 80, 78, 71]))
        #expect(try await request(base, "api/artwork/safe").1 == 401)
    }

    @Test("HTTP parser accepts fragmented bounded bodies and rejects ambiguity")
    func parserBounds() throws {
        var parser = CompanionHTTPParser()
        #expect(try parser.append(Data("POST /api/pair HTTP/1.1\r\nHost: localhost:123\r\nContent-Length: 2\r\n".utf8)) == nil)
        #expect(try parser.append(Data("\r\n{".utf8)) == nil)
        let completed = try parser.append(Data("}".utf8))
        let request = try #require(completed)
        #expect(request.body == Data("{}".utf8))
        var duplicate = CompanionHTTPParser()
        #expect(throws: (any Error).self) { try duplicate.append(Data("POST / HTTP/1.1\r\nHost: localhost\r\nContent-Length: 0\r\nContent-Length: 2\r\n\r\n".utf8)) }
        var chunks = CompanionHTTPParser()
        #expect(throws: (any Error).self) { try chunks.append(Data("POST / HTTP/1.1\r\nHost: localhost\r\nTransfer-Encoding: chunked\r\n\r\n".utf8)) }
        var oversized = CompanionHTTPParser()
        #expect(throws: (any Error).self) { try oversized.append(Data("POST / HTTP/1.1\r\nHost: localhost\r\nContent-Length: 100000\r\n\r\n".utf8)) }
    }

    @Test("Actual TCP fragments are assembled; foreign hosts and duplicate lengths are rejected")
    func fragmentedTCP() async throws {
        let server = CompanionServer()
        defer { server.stop() }
        let base = try await ready(server)
        let port = try #require(base.port)
        let payload = "{\"code\":\"\(server.pairingCode)\",\"name\":\"Fragmented phone\"}"
        let result = try await rawRequest(port: port, fragments: ["POST /api/pair HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\n", "Content-Length: \(payload.utf8.count)\r\n", "\r\n", String(payload.prefix(5)), String(payload.dropFirst(5))])
        #expect(result.hasPrefix("HTTP/1.1 200"))
        #expect(server.clients.first?.name == "Fragmented phone")
        let foreign = try await rawRequest(port: port, fragments: ["GET / HTTP/1.1\r\nHost: evil.example:\(port)\r\n\r\n"])
        #expect(foreign.hasPrefix("HTTP/1.1 403"))
        let duplicate = try await rawRequest(port: port, fragments: ["POST /api/pair HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\nContent-Length: 0\r\nContent-Length: 1\r\n\r\n"])
        #expect(duplicate.hasPrefix("HTTP/1.1 400"))
    }

    @Test("Pairing attempts are rate limited; stop and restart invalidate old browser credentials")
    func rateAndRestart() async throws {
        let server = CompanionServer()
        defer { server.stop() }
        server.onSnapshot = { CompanionSnapshot(revision: 0, profileName: "Deck", mode: "Auto", pageID: UUID(), pageName: "Main") }
        let base = try await ready(server)
        let token = try await pair(server, base)
        for _ in 0..<9 { #expect(try await request(base, "api/pair", method: "POST", body: ["code": "wrong"]).1 == 401) }
        #expect(try await request(base, "api/pair", method: "POST", body: ["code": "wrong"]).1 == 429)
        server.stop()
        let restarted = try await ready(server)
        #expect(try await request(restarted, "api/snapshot", token: token).1 == 401)
        let fresh = try await pair(server, restarted)
        #expect(try await request(restarted, "api/snapshot", token: fresh).1 == 200)
    }

    @Test("A selected loopback port starts without conflicting endpoint configuration")
    func selectedPort() async throws {
        let server = CompanionServer()
        defer { server.stop() }
        // Stay outside macOS's automatic outbound-port range: parallel URLSession
        // tests can otherwise claim the port between this probe and listener startup.
        let port = try availableTCPPort()
        try server.start(port: port, loopbackOnly: true)
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            if let url = server.urls.first {
                #expect(url.port == Int(port))
                #expect(try await request(url, "").1 == 200)
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("The companion did not bind its selected port: \(server.status)")
    }

    private func availableTCPPort() throws -> UInt16 {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        defer { Darwin.close(descriptor) }
        for _ in 0..<100 {
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            let port = UInt16.random(in: 20_000...30_000)
            address.sin_port = port.bigEndian
            let result = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                    Darwin.bind(descriptor, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            if result == 0 { return port }
            guard errno == EADDRINUSE else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        }
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(EADDRINUSE))
    }

    private func rawRequest(port: Int, fragments: [String]) async throws -> String {
        try await Task.detached {
            let socketID = socket(AF_INET, SOCK_STREAM, 0)
            guard socketID >= 0 else { throw NSError(domain: "CompanionTestSocket", code: Int(errno)) }
            defer { Darwin.close(socketID) }
            var timeout = timeval(tv_sec: 3, tv_usec: 0)
            setsockopt(socketID, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            var noSignal: Int32 = 1
            setsockopt(socketID, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = UInt16(port).bigEndian
            inet_pton(AF_INET, "127.0.0.1", &address.sin_addr)
            let connected = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(socketID, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
            }
            guard connected == 0 else { throw NSError(domain: "CompanionTestSocket", code: Int(errno)) }
            for fragment in fragments {
                let data = Data(fragment.utf8)
                let count = data.withUnsafeBytes { Darwin.send(socketID, $0.baseAddress, data.count, 0) }
                guard count == data.count else { throw NSError(domain: "CompanionTestSocket", code: Int(errno)) }
                usleep(2_000)
            }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4_096)
            while true {
                let count = recv(socketID, &buffer, buffer.count, 0)
                if count == 0 { break }
                guard count > 0 else { throw NSError(domain: "CompanionTestSocket", code: Int(errno)) }
                data.append(contentsOf: buffer.prefix(count))
            }
            return String(decoding: data, as: UTF8.self)
        }.value
    }
}
