// SPDX-License-Identifier: GPL-3.0-only
import Foundation

struct EcosystemError: LocalizedError, Equatable {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}

struct ExtensionInvocation: Codable, Hashable, Sendable {
    var extensionID: String
    var actionID: String
    var parameters: [String: String]
    init(extensionID: String, actionID: String, parameters: [String: String] = [:]) {
        self.extensionID = extensionID; self.actionID = actionID; self.parameters = parameters
    }
}

enum ExtensionParameterType: String, Codable, CaseIterable, Hashable, Sendable {
    case string, choice, boolean, number, url, secretReference
}
struct ExtensionParameter: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    var type: ExtensionParameterType
    var required: Bool = false
    var defaultValue: String? = nil
    var choices: [String] = []
    func validate(value: String) throws {
        switch type {
        case .string: break
        case .choice: guard choices.contains(value) else { throw EcosystemError("Choose a supported value for \(name).") }
        case .boolean: guard ["true", "false"].contains(value) else { throw EcosystemError("\(name) must be true or false.") }
        case .number: guard let number = Double(value), number.isFinite else { throw EcosystemError("\(name) must be a finite number.") }
        case .url: guard let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased()), url.host != nil, url.user == nil, url.password == nil else { throw EcosystemError("\(name) must be a web URL without credentials.") }
        case .secretReference: guard !value.isEmpty, value.count <= 200 else { throw EcosystemError("\(name) needs a local secret reference.") }
        }
        guard value.count <= 32_768 else { throw EcosystemError("\(name) is too long.") }
    }
}
struct ExtensionAction: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    var parameters: [ExtensionParameter] = []
    var recipe: [MacroStep]
}
struct ExtensionManifest: Codable, Hashable, Identifiable, Sendable {
    var schemaVersion: Int = 1
    var id: String
    var name: String
    var version: String
    var author: String
    var license: String
    var supportedApplications: [String] = []
    var supportedServices: [String] = []
    var allowedHosts: [String] = []
    var actions: [ExtensionAction]
    var symbolName: String? = nil
}
struct InstalledExtension: Codable, Hashable, Identifiable, Sendable {
    var id: String { manifest.id }
    var manifest: ExtensionManifest
    var enabled: Bool
}

struct HTTPRequestAction: Codable, Hashable, Sendable {
    var url: String
    var method: String
    var headers: [String: String]
    var body: String?
    var allowedHosts: [String]
    var secretHeaders: [String: String]
    var timeoutSeconds: Int
    init(url: String, method: String = "GET", headers: [String: String] = [:], body: String? = nil, allowedHosts: [String], secretHeaders: [String: String] = [:], timeoutSeconds: Int = 30) {
        self.url = url; self.method = method; self.headers = headers; self.body = body
        self.allowedHosts = allowedHosts; self.secretHeaders = secretHeaders; self.timeoutSeconds = timeoutSeconds
    }
    func validate() throws {
        guard let target = URL(string: url), Self.isAllowed(target, hosts: allowedHosts) else { throw EcosystemError("HTTP request must use a declared host over HTTPS (HTTP is allowed only for loopback).") }
        guard ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"].contains(method), (1...300).contains(timeoutSeconds) else { throw EcosystemError("Unsupported HTTP method or timeout.") }
        guard allowedHosts.count <= 32, allowedHosts.allSatisfy(Self.validHost), Set(allowedHosts.map { $0.lowercased() }).count == allowedHosts.count else { throw EcosystemError("Declare exact HTTP service host names without schemes or wildcards.") }
        guard headers.count + secretHeaders.count <= 64, (body?.utf8.count ?? 0) <= 1_000_000 else { throw EcosystemError("HTTP request is too large.") }
        let names = headers.keys.map { $0.lowercased() } + secretHeaders.keys.map { $0.lowercased() }
        guard Set(names).count == names.count, names.allSatisfy({ !["host", "content-length", "connection"].contains($0) }), headers.allSatisfy({ !["authorization", "proxy-authorization", "cookie", "x-api-key"].contains($0.key.lowercased()) && Self.validHeaderName($0.key) && !$0.value.contains("\r") && !$0.value.contains("\n") }), secretHeaders.allSatisfy({ Self.validHeaderName($0.key) && !$0.value.isEmpty && $0.value.count <= 200 }) else { throw EcosystemError("Invalid or duplicate HTTP headers.") }
    }
    static func validHost(_ host: String) -> Bool {
        !host.isEmpty && host.count <= 253 && !host.contains("..") && host.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-:").contains($0) } && !host.hasPrefix(".") && !host.hasSuffix(".")
    }
    static func isAllowed(_ url: URL, hosts: [String]) -> Bool {
        guard url.user == nil, url.password == nil, let host = url.host?.lowercased(), hosts.map({ $0.lowercased() }).contains(host), url.fragment == nil else { return false }
        return url.scheme?.lowercased() == "https" || (url.scheme?.lowercased() == "http" && ["localhost", "127.0.0.1", "[::1]", "::1"].contains(host))
    }
    static func validHeaderName(_ name: String) -> Bool {
        !name.isEmpty && name.utf8.allSatisfy { (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }
    }
}
