// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import AppKit
import CoreImage.CIFilterBuiltins

struct CompanionSettingsView: View {
    @Bindable var server: CompanionServer
    @State private var error: String?
    @State private var selectedURL: URL?

    var body: some View {
        GeometryReader { geometry in
        let isCompact = geometry.size.width < 640
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                let headerLayout = isCompact ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 16))
                headerLayout {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Browser Companion").font(.title2.weight(.semibold))
                        Text("Use your phone or tablet as a synchronized deck.").foregroundStyle(.secondary)
                    }
                    if !isCompact { Spacer() }
                    if server.isRunning {
                        Button("Stop Companion", role: .destructive) { server.stop() }
                    } else {
                        Button("Start Companion") {
                            do { try server.start(); error = nil } catch { self.error = error.localizedDescription }
                        }.buttonStyle(.borderedProminent)
                    }
                }
                Label(server.status, systemImage: server.isRunning ? "network" : "network.slash").font(.callout).foregroundStyle(.secondary)
                if let error { Text(error).foregroundStyle(.red) }
                if server.isRunning {
                    GroupBox("1. Open on your phone or tablet") {
                        let connectionLayout = isCompact ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16)) : AnyLayout(HStackLayout(alignment: .top, spacing: 20))
                        connectionLayout {
                            if let url = connectionURL {
                                CompanionQRCodeView(url: url)
                            }
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Connect both devices to the same trusted network, then scan the QR code or open an address below.").font(.callout)
                                ForEach(server.urls, id: \.self) { url in
                                    HStack(alignment: .top) {
                                        Button { selectedURL = url } label: {
                                            Image(systemName: connectionURL == url ? "largecircle.fill.circle" : "circle")
                                        }.buttonStyle(.plain).help("Show this address as a QR code").accessibilityLabel("Show QR code for \(url.absoluteString)")
                                        Link(destination: url) { Text(url.absoluteString).fixedSize(horizontal: false, vertical: true) }
                                            .font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).layoutPriority(1)
                                        Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(url.absoluteString, forType: .string) } label: { Image(systemName: "doc.on.doc") }.buttonStyle(.plain).help("Copy address").accessibilityLabel("Copy address")
                                    }
                                }
                                Text("127.0.0.1 connects only from this Mac. Use a network address on your other device.").font(.caption).foregroundStyle(.secondary)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                    }
                    GroupBox("2. Pair this browser") {
                        let pairingLayout = isCompact ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 22))
                        pairingLayout {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(server.pairingCode).font(.system(size: 34, weight: .semibold, design: .monospaced)).textSelection(.enabled).accessibilityLabel("Pairing code \(server.pairingCode)")
                                if let expiry = server.pairingExpiresAt {
                                    TimelineView(.periodic(from: .now, by: 1)) { context in
                                        Text(context.date < expiry ? "Expires \(expiry.formatted(date: .omitted, time: .shortened))" : "Code expired. Generate a new code.")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            if !isCompact { Spacer() }
                            Button("New Pairing Code") { server.renewPairingCode() }
                        }.padding(8)
                        Text("Each paired browser gets its own access. Stop revokes every session and cancels companion actions. HTTP stays on your trusted local network; avoid public Wi-Fi.").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(8)
                    }
                    GroupBox("Paired browsers") {
                        if server.clients.isEmpty {
                            Text("No browsers paired yet.").foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(8)
                        } else {
                            VStack(spacing: 12) {
                                ForEach(server.clients) { client in
                                    HStack {
                                        Image(systemName: "ipad.and.iphone")
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(client.name.isEmpty ? "Browser" : client.name).fontWeight(.medium).fixedSize(horizontal: false, vertical: true)
                                            TimelineView(.periodic(from: .now, by: 5)) { context in
                                                Text(context.date.timeIntervalSince(client.lastSeen) < 10 ? "Connected" : "Last seen \(client.lastSeen.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                                            }
                                        }
                                        Spacer()
                                        Button("Revoke", role: .destructive) { server.revokeClient(id: client.id) }
                                    }
                                }
                            }.padding(8)
                        }
                    }
                } else {
                    Text("Start the companion to get a network address and pairing code. Your virtual layout is available in the editor even without MIDI hardware.").foregroundStyle(.secondary)
                }
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }
        }
    }
    private var connectionURL: URL? {
        if let selectedURL, server.urls.contains(selectedURL) { return selectedURL }
        return server.urls.first
    }
}

private struct CompanionQRCodeView: View {
    let url: URL
    @State private var image: NSImage?
    var body: some View {
        Group {
            if let image { Image(nsImage: image).interpolation(.none).resizable() }
            else { ProgressView().controlSize(.small) }
        }.frame(width: 140, height: 140).padding(8).background(.white).clipShape(RoundedRectangle(cornerRadius: 10))
            .accessibilityLabel("QR code for \(url.absoluteString)")
            .task(id: url) { image = CompanionQRCodeCache.image(for: url) }
    }
}

@MainActor
private enum CompanionQRCodeCache {
    private static let context = CIContext()
    private static let images: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 16
        return cache
    }()

    static func image(for url: URL) -> NSImage? {
        let key = url.absoluteString as NSString
        if let cached = images.object(forKey: key) { return cached }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 6, y: 6)),
              let image = context.createCGImage(output, from: output.extent) else { return nil }
        let result = NSImage(cgImage: image, size: NSSize(width: output.extent.width, height: output.extent.height))
        images.setObject(result, forKey: key)
        return result
    }
}
