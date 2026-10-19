// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import CoreGraphics

/// Pads remain readable in small viewports; the containing scroll view handles overflow.
struct DeckSurfaceGeometry {
    let cellSide: CGFloat
    let boardSize: CGSize
    static let spacing: CGFloat = 7
    static let padding: CGFloat = 14

    init(viewport: CGSize, rows: Int, columns: Int) {
        let rows = max(1, rows), columns = max(1, columns)
        let horizontal = (viewport.width - Self.padding * 2 - Self.spacing * CGFloat(columns - 1)) / CGFloat(columns)
        let vertical = (viewport.height - Self.padding * 2 - Self.spacing * CGFloat(rows - 1)) / CGFloat(rows)
        cellSide = max(44, min(96, horizontal, vertical).rounded(.down))
        boardSize = CGSize(width: CGFloat(columns) * cellSide + Self.spacing * CGFloat(columns - 1) + Self.padding * 2,
                           height: CGFloat(rows) * cellSide + Self.spacing * CGFloat(rows - 1) + Self.padding * 2)
    }
}

struct EditorWindowGeometry {
    static func initialFrame(visibleFrame: CGRect, preferredSize: CGSize = CGSize(width: 1280, height: 860)) -> CGRect {
        let size = CGSize(width: min(preferredSize.width, max(1, visibleFrame.width - 32)),
                          height: min(preferredSize.height, max(1, visibleFrame.height - 32)))
        return CGRect(x: visibleFrame.midX - size.width / 2, y: visibleFrame.midY - size.height / 2, width: size.width, height: size.height)
    }
}
