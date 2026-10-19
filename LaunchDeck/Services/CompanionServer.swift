// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Network
import Observation
import Security
import Darwin

struct CompanionHTTPRequest: Sendable {
    var method: String
    var path: String
    var headers: [String: String]
    var body: Data
}

/// One bounded HTTP/1.1 request per connection; ambiguous framing is rejected.
struct CompanionHTTPParser: Sendable {
    static let maximumHeaderSize = 8_192
    static let maximumBodySize = 16_384
    private var data = Data()

    mutating func append(_ chunk: Data) throws -> CompanionHTTPRequest? {
        data.append(chunk)
        guard data.count <= Self.maximumHeaderSize + Self.maximumBodySize else { throw ParseError.invalid }
        guard let delimiter = data.range(of: Data("\r\n\r\n".utf8)) else {
            guard data.count <= Self.maximumHeaderSize else { throw ParseError.invalid }
            return nil
        }
        guard delimiter.lowerBound <= Self.maximumHeaderSize,
              let header = String(data: data[..<delimiter.lowerBound], encoding: .utf8) else { throw ParseError.invalid }
        let lines = header.components(separatedBy: "\r\n")
        let first = (lines.first ?? "").split(separator: " ", omittingEmptySubsequences: false)
        guard first.count == 3, first[2] == "HTTP/1.1", ["GET", "POST"].contains(String(first[0])),
              first[1].hasPrefix("/"), !first[1].hasPrefix("//"), !first[1].contains("#") else { throw ParseError.invalid }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":"), !line.hasPrefix(" "), !line.hasPrefix("\t") else { throw ParseError.invalid }
            let name = line[..<colon].lowercased()
            guard !name.isEmpty, name.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }), headers[name] == nil else { throw ParseError.invalid }
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard !value.unicodeScalars.contains(where: { $0.value < 32 && $0.value != 9 }) else { throw ParseError.invalid }
            headers[name] = value
        }
        guard headers["host"] != nil, headers["transfer-encoding"] == nil else { throw ParseError.invalid }
        let lengthText = headers["content-length"] ?? "0"
        guard !lengthText.isEmpty, lengthText.utf8.allSatisfy({ (48...57).contains($0) }),
              let length = Int(lengthText), length <= Self.maximumBodySize else { throw ParseError.invalid }
        let end = delimiter.upperBound + length
        guard data.count >= end else { return nil }
        guard data.count == end else { throw ParseError.invalid }
        return CompanionHTTPRequest(method: String(first[0]), path: String(first[1]), headers: headers, body: Data(data[delimiter.upperBound..<end]))
    }
    enum ParseError: Error { case invalid }
}

private struct CompanionHTTPResponse: Sendable {
    var status: Int
    var contentType = "application/json; charset=utf-8"
    var body: Data
    var wireData: Data {
        let reason = [200: "OK", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden", 404: "Not Found", 405: "Method Not Allowed", 409: "Conflict", 413: "Content Too Large", 429: "Too Many Requests", 503: "Service Unavailable"][status] ?? "Error"
        let header = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\nContent-Security-Policy: default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src 'self' blob:; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'\r\nConnection: close\r\n\r\n"
        return Data(header.utf8) + body
    }
    static func json(_ status: Int, _ values: [String: String]) -> Self {
        Self(status: status, body: (try? JSONSerialization.data(withJSONObject: values)) ?? Data("{}".utf8))
    }
}

/// Network callbacks never inherit MainActor isolation. Parsed requests cross once to the desktop actor.
private final class CompanionConnection: @unchecked Sendable {
    let id = UUID()
    let connection: NWConnection
    let queue: DispatchQueue
    var parser = CompanionHTTPParser()
    var completed = false
    let onRequest: @Sendable (CompanionHTTPRequest, CompanionConnection) -> Void
    let onClose: @Sendable (UUID) -> Void

    init(_ connection: NWConnection, queue: DispatchQueue,
         onRequest: @escaping @Sendable (CompanionHTTPRequest, CompanionConnection) -> Void,
         onClose: @escaping @Sendable (UUID) -> Void) {
        self.connection = connection; self.queue = queue; self.onRequest = onRequest; self.onClose = onClose
    }
    func start() {
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 5) { [weak self] in self?.close() }
        receive()
    }
    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4_096) { [weak self] data, _, ended, error in
            guard let self, !self.completed else { return }
            do {
                if let data, let request = try self.parser.append(data) {
                    self.completed = true
                    self.onRequest(request, self)
                } else if ended || error != nil { self.close() }
                else { self.receive() }
            } catch { self.send(.json(400, ["error": "Invalid or oversized request."])) }
        }
    }
    func send(_ response: CompanionHTTPResponse) {
        queue.async { [self] in
            completed = true
            connection.send(content: response.wireData, completion: .contentProcessed { [weak self] _ in self?.close() })
        }
    }
    func cancel() { queue.async { [self] in close() } }
    private func close() { completed = true; connection.cancel(); onClose(id) }
}

@MainActor @Observable
final class CompanionServer {
    private(set) var isRunning = false
    private(set) var urls: [URL] = []
    private(set) var pairingCode = ""
    private(set) var pairingExpiresAt: Date?
    private(set) var clients: [CompanionClient] = []
    private(set) var status = "Stopped"
    var onSnapshot: (() -> CompanionSnapshot)?
    var onPress: ((Int, Int, UUID) -> String?)?
    var onActivate: ((UUID?) -> String?)?
    var onArtwork: ((String) -> Data?)?
    var onStop: (() -> Void)?

    @ObservationIgnored private var listener: NWListener?
    @ObservationIgnored private var connections: [UUID: CompanionConnection] = [:]
    @ObservationIgnored private var tokens: [String: UUID] = [:]
    @ObservationIgnored private var limits: [String: (Date, Int)] = [:]
    @ObservationIgnored private var allowedHosts = Set<String>()
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private let queue = DispatchQueue(label: "org.launchdeck.companion")
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let pairingLifetime: TimeInterval

    init(now: @escaping () -> Date = Date.init, pairingLifetime: TimeInterval = 300) {
        self.now = now; self.pairingLifetime = pairingLifetime
    }
    isolated deinit { listener?.cancel(); for connection in connections.values { connection.cancel() } }

    func start(port: UInt16 = 0, loopbackOnly: Bool = false) throws {
        guard listener == nil else { return }
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = false
        if loopbackOnly { parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!) }
        let listener = try loopbackOnly ? NWListener(using: parameters) : NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
        self.listener = listener
        generation = UUID()
        let generation = generation
        status = "Starting…"
        renewPairingCode()
        listener.stateUpdateHandler = Self.stateHandler(server: self, generation: generation, loopbackOnly: loopbackOnly)
        listener.newConnectionHandler = Self.connectionHandler(server: self, generation: generation)
        listener.start(queue: queue)
    }

    private nonisolated static func stateHandler(server: CompanionServer, generation: UUID, loopbackOnly: Bool) -> @Sendable (NWListener.State) -> Void {
        { [weak server] state in
            Task { @MainActor in
                guard let server, server.generation == generation, server.listener != nil else { return }
                switch state {
                case .ready:
                    guard let port = server.listener?.port?.rawValue else { return }
                    let hosts = loopbackOnly ? ["127.0.0.1"] : Self.localIPv4Addresses()
                    server.urls = hosts.compactMap { URL(string: "http://\($0):\(port)/") }
                    server.allowedHosts = Set(hosts.map { "\($0):\(port)" })
                    server.isRunning = true; server.status = "Listening on port \(port)"
                case .failed(let error):
                    server.stop(); server.status = error.localizedDescription
                default: break
                }
            }
        }
    }
    private nonisolated static func connectionHandler(server: CompanionServer, generation: UUID) -> @Sendable (NWConnection) -> Void {
        { [weak server] connection in
            Task { @MainActor in
                guard let server, server.isRunning, server.generation == generation, server.connections.count < 64 else { connection.cancel(); return }
                let client = CompanionConnection(connection, queue: server.queue, onRequest: { [weak server] request, client in
                    Task { @MainActor in
                        guard let server, server.isRunning, server.generation == generation else { client.cancel(); return }
                        client.send(server.respond(request, remote: "\(connection.endpoint)"))
                    }
                }, onClose: { [weak server] id in Task { @MainActor in server?.connections.removeValue(forKey: id) } })
                server.connections[client.id] = client
                client.start()
            }
        }
    }
    func stop() {
        let wasStarted = listener != nil
        generation = UUID(); listener?.cancel(); listener = nil
        for connection in connections.values { connection.cancel() }
        connections.removeAll(); tokens.removeAll(); clients.removeAll(); limits.removeAll(); allowedHosts.removeAll()
        urls = []; pairingCode = ""; pairingExpiresAt = nil; isRunning = false; status = "Stopped"
        if wasStarted { onStop?() }
    }
    func renewPairingCode() {
        let bytes = Self.randomBytes(count: 8)
        pairingCode = bytes.map { String(Int($0) % 10) }.joined()
        pairingExpiresAt = now().addingTimeInterval(pairingLifetime)
    }
    func revokeClient(id: UUID) {
        let existed = clients.contains { $0.id == id }
        tokens = tokens.filter { $0.value != id }
        clients.removeAll { $0.id == id }
        if existed { onStop?() }
    }

    private func respond(_ request: CompanionHTTPRequest, remote: String) -> CompanionHTTPResponse {
        guard let host = request.headers["host"], allowedHosts.contains(host.lowercased()) else { return .json(403, ["error": "Unknown host."]) }
        if let origin = request.headers["origin"], origin != "http://\(host)" { return .json(403, ["error": "Origin rejected."]) }
        if request.headers["sec-fetch-site"] == "cross-site" { return .json(403, ["error": "Cross-site request rejected."]) }
        // Bound rate and memory independently of session identity. Ephemeral TCP ports are omitted.
        let remoteHost = remote.split(separator: ":").first.map(String.init) ?? remote
        let current = now()
        limits = limits.filter { current.timeIntervalSince($0.value.0) < 10 }
        let rateKey = request.path == "/api/pair" ? "pair:\(remoteHost)" : remoteHost
        let limit = request.path == "/api/pair" ? 10 : 200
        let count = limits[rateKey]?.1 ?? 0
        guard count < limit, limits.count < 256 || limits[rateKey] != nil else { return .json(429, ["error": "Too many requests. Try again shortly."]) }
        limits[rateKey] = (limits[rateKey]?.0 ?? current, count + 1)
        guard request.path == "/" || (request.path.hasPrefix("/api/") && !request.path.contains("?")) else { return .json(404, ["error": "Not found."]) }
        if request.path == "/" {
            guard request.method == "GET" else { return .json(405, ["error": "Use GET."]) }
            return CompanionHTTPResponse(status: 200, contentType: "text/html; charset=utf-8", body: Data(CompanionHTML.page.utf8))
        }
        if request.path == "/api/pair" {
            guard request.method == "POST" else { return .json(405, ["error": "Use POST."]) }
            guard let object = object(request), let code = object["code"] as? String,
                  code == pairingCode, let expiry = pairingExpiresAt, current < expiry,
                  clients.count < 32 else { return .json(401, ["error": "Pairing code invalid or expired. Generate a new code on your Mac."]) }
            let token = Self.randomBytes(count: 32).map { String(format: "%02x", $0) }.joined()
            let client = CompanionClient(id: UUID(), name: String((object["name"] as? String ?? "Browser").prefix(80)), pairedAt: current, lastSeen: current)
            tokens[token] = client.id; clients.append(client)
            return .json(200, ["token": token, "clientID": client.id.uuidString])
        }
        guard let authorization = request.headers["authorization"], authorization.hasPrefix("Bearer "),
              let clientID = tokens[String(authorization.dropFirst(7))], let clientIndex = clients.firstIndex(where: { $0.id == clientID }) else { return .json(401, ["error": "Pair this browser on your Mac."]) }
        clients[clientIndex].lastSeen = current
        if request.path == "/api/snapshot" {
            guard request.method == "GET" else { return .json(405, ["error": "Use GET."]) }
            guard let snapshot = onSnapshot?(), let data = try? JSONEncoder().encode(snapshot) else { return .json(503, ["error": "Deck unavailable."]) }
            return CompanionHTTPResponse(status: 200, body: data)
        }
        if request.path.hasPrefix("/api/artwork/") {
            guard request.method == "GET" else { return .json(405, ["error": "Use GET."]) }
            let id = String(request.path.dropFirst("/api/artwork/".count))
            guard id.count <= 100, !id.isEmpty, id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }),
                  let data = onArtwork?(id), data.count <= 8_388_608 else { return .json(404, ["error": "Artwork unavailable."]) }
            return CompanionHTTPResponse(status: 200, contentType: "image/png", body: data)
        }
        guard request.method == "POST" else { return .json(405, ["error": "Use POST."]) }
        guard let values = object(request) else { return .json(400, ["error": "Invalid JSON."]) }
        if request.path == "/api/press" {
            guard let index = values["index"] as? Int, (0..<256).contains(index), let revision = values["revision"] as? Int,
                  let page = values["pageID"] as? String, let pageID = UUID(uuidString: page) else { return .json(400, ["error": "Invalid control."]) }
            guard let onPress else { return .json(503, ["error": "Deck unavailable."]) }
            if let error = onPress(index, revision, pageID) { return .json(409, ["error": error]) }
            return .json(200, ["status": "accepted"])
        }
        if request.path == "/api/activate" {
            var profileID: UUID?
            if let raw = values["profileID"], !(raw is NSNull) {
                guard let value = raw as? String, let id = UUID(uuidString: value) else { return .json(400, ["error": "Invalid profile."]) }
                profileID = id
            }
            guard let onActivate else { return .json(503, ["error": "Deck unavailable."]) }
            if let error = onActivate(profileID) { return .json(409, ["error": error]) }
            return .json(200, ["status": "accepted"])
        }
        return .json(404, ["error": "Not found."])
    }
    private func object(_ request: CompanionHTTPRequest) -> [String: Any]? { (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any] }
    private nonisolated static func randomBytes(count: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: count)
        precondition(SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess, "Secure random generation failed")
        return bytes
    }
    private nonisolated static func localIPv4Addresses() -> [String] {
        var addresses = [String]()
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0 else { return ["127.0.0.1"] }
        defer { freeifaddrs(interfaces) }
        var item = interfaces
        while let current = item {
            defer { item = current.pointee.ifa_next }
            guard let address = current.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  current.pointee.ifa_flags & UInt32(IFF_UP) != 0 else { continue }
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 {
                let host = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
                if host != "127.0.0.1" { addresses.append(host) }
            }
        }
        return Array(Set(addresses)).sorted() + ["127.0.0.1"]
    }
}
