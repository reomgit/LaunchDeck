// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

struct ArtworkThumbnail: View {
    let url: URL
    let side: CGFloat
    @Environment(\.displayScale) private var displayScale
    @State private var thumbnail: ArtworkThumbnailImage?
    private var pixels: Int { Int((side * displayScale).rounded(.up)) }
    private var requestID: String { url.path + "#\(pixels)" }

    var body: some View {
        Group {
            if let thumbnail { Image(decorative: thumbnail.image, scale: displayScale).resizable().scaledToFit() }
            else { Image(systemName: "photo").foregroundStyle(.secondary) }
        }
        .frame(width: side, height: side)
        .task(id: requestID) {
            thumbnail = nil
            let result = await ArtworkThumbnailStore.shared.thumbnail(at: url, pixels: pixels)
            guard !Task.isCancelled else { return }
            thumbnail = result
        }
    }
}
