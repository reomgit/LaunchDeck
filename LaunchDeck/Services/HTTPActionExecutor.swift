// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Redirects may not carry local secret headers to a different origin.
private final class HostRestrictedRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    let hosts: [String]
    let origin: URL?
    let allowsCatalog: Bool
    init(hosts: [String], origin: URL?, allowsCatalog: Bool = false) { self.hosts = hosts; self.origin = origin; self.allowsCatalog = allowsCatalog }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        guard let url = request.url else { completionHandler(nil); return }
        let sameOrigin = origin.map { $0.scheme == url.scheme && $0.host == url.host && $0.port == url.port } ?? true
        let allowed = allowsCatalog ? ContentCatalog.validRemoteURL(url) : HTTPRequestAction.isAllowed(url, hosts: hosts)
        completionHandler(allowed && sameOrigin ? request : nil)
    }
}
struct HTTPActionExecutor: Sendable {
    func execute(_ action: HTTPRequestAction, secrets: any SecretProviding = SecretStore()) async throws {
        try action.validate()
        guard let url = URL(string: action.url) else { throw EcosystemError("Invalid request URL.") }
        var request = URLRequest(url: url, timeoutInterval: TimeInterval(action.timeoutSeconds))
        request.httpMethod = action.method
        request.httpBody = action.body.map { Data($0.utf8) }
        for (header, value) in action.headers { request.setValue(value, forHTTPHeaderField: header) }
        for (header, reference) in action.secretHeaders {
            let value = try secrets.secret(reference: reference)
            guard !value.contains("\r"), !value.contains("\n") else { throw EcosystemError("Local secret contains invalid header characters.") }
            request.setValue(value, forHTTPHeaderField: header)
        }
        _ = try await BoundedHTTPClient.download(request, maxBytes: 1_000_000, hosts: action.allowedHosts)
    }
}
/// Shared bounded streaming transport for action responses and content downloads.
struct BoundedHTTPClient {
    static func download(_ request: URLRequest, maxBytes: Int, hosts: [String]? = nil) async throws -> Data {
        try Task.checkCancellation()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = request.timeoutInterval
        configuration.timeoutIntervalForResource = request.timeoutInterval
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        let delegate = HostRestrictedRedirectDelegate(hosts: hosts ?? [], origin: request.url, allowsCatalog: hosts == nil)
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw EcosystemError("HTTP request failed with status \(status).")
        }
        guard response.expectedContentLength <= Int64(maxBytes) else { throw EcosystemError("HTTP response exceeds the allowed size.") }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < maxBytes else { throw EcosystemError("HTTP response exceeds the allowed size.") }
            data.append(byte)
        }
        return data
    }
}
