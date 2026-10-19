import XCTest
@testable import LaunchDeckCore

private final class EcosystemHTTPFixture {
    let directory: URL
    let process: Process
    let port: Int
    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        let source = #"""
import http.server, socketserver, sys, time, os
os.chdir(sys.argv[1])
class Handler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args): pass
    def do_GET(self):
        if self.path == '/slow':
            time.sleep(3)
            self.send_response(200); self.end_headers(); return
        if self.path == '/fail':
            self.send_response(403); self.end_headers(); return
        if self.path == '/redirect':
            self.send_response(302); self.send_header('Location', 'http://localhost:%d/ok' % self.server.server_address[1]); self.end_headers(); return
        if self.path == '/authorized':
            self.send_response(200 if self.headers.get('Authorization') == 'Bearer local-only' else 401); self.end_headers(); return
        if self.path == '/ok':
            self.send_response(200); self.end_headers(); self.wfile.write(b'ok'); return
        super().do_GET()
class Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
server = Server(('127.0.0.1', 0), Handler)
print(server.server_address[1], flush=True)
server.serve_forever()
"""#
        process.arguments = ["-u", "-c", source, directory.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let output = pipe.fileHandleForReading.availableData
        guard let value = Int(String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) else {
            process.terminate(); throw EcosystemError("Local HTTP fixture failed to start.")
        }
        port = value
    }
    func url(_ path: String) -> URL { URL(string: "http://127.0.0.1:\(port)/\(path)")! }
    deinit {
        if process.isRunning { process.terminate(); process.waitUntilExit() }
        try? FileManager.default.removeItem(at: directory)
    }
}
private struct FixtureSecrets: SecretProviding {
    func secret(reference: String) throws -> String {
        guard reference == "local-reference" else { throw EcosystemError("Missing credential.") }
        return "Bearer local-only"
    }
}
final class EcosystemTransportTests: XCTestCase {
    func testLoopbackHTTPStatusRedirectAndLocalCredentialInjection() async throws {
        let server = try EcosystemHTTPFixture()
        let executor = HTTPActionExecutor()
        try await executor.execute(HTTPRequestAction(url: server.url("authorized").absoluteString, allowedHosts: ["127.0.0.1"], secretHeaders: ["Authorization": "local-reference"]), secrets: FixtureSecrets())
        for path in ["fail", "redirect"] {
            do {
                try await executor.execute(HTTPRequestAction(url: server.url(path).absoluteString, allowedHosts: ["127.0.0.1", "localhost"]))
                XCTFail("Expected request failure for \(path)")
            } catch { XCTAssertFalse(error.localizedDescription.contains("local-only")) }
        }
    }
    func testHTTPTimeoutAndCancellation() async throws {
        let server = try EcosystemHTTPFixture()
        do {
            try await HTTPActionExecutor().execute(HTTPRequestAction(url: server.url("slow").absoluteString, allowedHosts: ["127.0.0.1"], timeoutSeconds: 1))
            XCTFail("Expected timeout")
        } catch { XCTAssertEqual((error as? URLError)?.code, .timedOut) }
        let task = Task {
            try await HTTPActionExecutor().execute(HTTPRequestAction(url: server.url("slow").absoluteString, allowedHosts: ["127.0.0.1"]))
        }
        try await Task.sleep(for: .milliseconds(40))
        task.cancel()
        do { try await task.value; XCTFail("Expected cancellation") } catch {
            XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled)
        }
    }
    @MainActor func testRealHTTPCatalogInstallationUpdateAndChecksumRollback() async throws {
        let server = try EcosystemHTTPFixture()
        let registry = try ExtensionRegistry(directory: server.directory.appendingPathComponent("Storage"))
        let service = try ContentLibraryService(directory: server.directory.appendingPathComponent("Storage"), registry: registry)
        var manifest = ExtensionManifest(id: "org.test.extension", name: "Test", version: "1.0.0", author: "Test", license: "MIT", actions: [ExtensionAction(id: "text", name: "Text", recipe: [.text("First")])])
        func publish(_ manifest: ExtensionManifest, corruptDigest: Bool = false) throws -> ContentCatalogEntry {
            let bytes = try JSONEncoder().encode(manifest)
            try bytes.write(to: server.directory.appendingPathComponent("test.launchdeckextension"), options: .atomic)
            let entry = ContentCatalogEntry(id: manifest.id, type: .extensionPackage, name: manifest.name, author: "Test", license: "MIT", description: "Test", version: manifest.version, artifactURL: server.url("test.launchdeckextension").absoluteString, size: bytes.count, sha256: corruptDigest ? String(repeating: "0", count: 64) : ContentCatalog.digest(bytes))
            try JSONEncoder().encode(ContentCatalog(entries: [entry])).write(to: server.directory.appendingPathComponent("catalog.json"), options: .atomic)
            return entry
        }
        let first = try publish(manifest)
        try await service.fetchCatalog(from: server.url("catalog.json"))
        XCTAssertEqual(service.entries, [first])
        try await service.install(first) { _ in XCTFail("Unexpected profile import") }
        manifest.version = "1.1.0"; manifest.actions[0].recipe = [.text("Updated")]
        let update = try publish(manifest)
        try await service.fetchCatalog(from: server.url("catalog.json"))
        XCTAssertTrue(service.hasUpdate(update))
        try await service.install(update) { _ in XCTFail("Unexpected profile import") }
        XCTAssertEqual(try registry.expandSteps([.extensionAction(ExtensionInvocation(extensionID: manifest.id, actionID: "text"))]), [.text("Updated")])
        manifest.version = "1.2.0"
        let corrupt = try publish(manifest, corruptDigest: true)
        try await service.fetchCatalog(from: server.url("catalog.json"))
        do { try await service.install(corrupt) { _ in }; XCTFail("Expected checksum rejection") } catch {}
        XCTAssertEqual(service.installedVersion(for: corrupt), "1.1.0")
        XCTAssertNotNil(service.errorMessage)
    }
}

extension EcosystemTransportTests {
    @MainActor func testRealHTTPCatalogInstallsProfileAndIconsWithoutOverwritingExistingProfile() async throws {
        let server = try EcosystemHTTPFixture()
        let storage = server.directory.appendingPathComponent("Storage")
        let registry = try ExtensionRegistry(directory: storage)
        let service = try ContentLibraryService(directory: storage, registry: registry)
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let samples = root.appendingPathComponent("Samples/Ecosystem")
        var catalog = try JSONDecoder().decode(ContentCatalog.self, from: Data(contentsOf: samples.appendingPathComponent("catalog.json")))
        for index in catalog.entries.indices {
            let file = URL(string: catalog.entries[index].artifactURL)!.lastPathComponent
            try Data(contentsOf: samples.appendingPathComponent(file)).write(to: server.directory.appendingPathComponent(file))
            catalog.entries[index].artifactURL = server.url(file).absoluteString
        }
        try JSONEncoder().encode(catalog).write(to: server.directory.appendingPathComponent("catalog.json"))
        try await service.fetchCatalog(from: server.url("catalog.json"))
        let original = Profile(name: "Existing", kind: .manual)
        var profiles = [original]
        for entry in service.entries { try await service.install(entry) { profiles.append($0) } }
        let profileEntry = try XCTUnwrap(service.entries.first { $0.type == .profile })
        try await service.install(profileEntry) { profiles.append($0) }
        XCTAssertEqual(profiles.first, original)
        XCTAssertEqual(profiles.count, 3)
        XCTAssertNotEqual(profiles[1].id, profiles[2].id)
        XCTAssertEqual(service.iconPacks.installedIcons.count, 3)
    }
}
