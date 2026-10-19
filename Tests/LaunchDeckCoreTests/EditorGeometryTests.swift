// SPDX-License-Identifier: GPL-3.0-only
import Testing
import Foundation
import CoreGraphics
@testable import LaunchDeckCore

struct EditorGeometryTests {
    @Test func deckUsesLargeViewportAndPreservesSquareCells() {
        let layout = DeckSurfaceGeometry(viewport: CGSize(width: 760, height: 760), rows: 9, columns: 9)
        #expect(layout.cellSide > 54)
        #expect(layout.boardSize.width <= 760)
        #expect(layout.boardSize.height <= 760)
        #expect(layout.boardSize.width == layout.boardSize.height)
    }
    @Test func smallViewportPreservesReadableControlsAndScrolls() {
        let layout = DeckSurfaceGeometry(viewport: CGSize(width: 300, height: 300), rows: 11, columns: 10)
        #expect(layout.cellSide == 44)
        #expect(layout.boardSize.width > 300)
        #expect(layout.boardSize.height > 300)
    }
    @Test func everyDeviceFitsWhenEnoughSpaceExists() {
        for model in DeviceModel.allCases {
            let controls = model.descriptor.controls
            let rows = controls.map(\.row).max()! - controls.map(\.row).min()! + 1
            let columns = controls.map(\.column).max()! - controls.map(\.column).min()! + 1
            let layout = DeckSurfaceGeometry(viewport: CGSize(width: 800, height: 800), rows: rows, columns: columns)
            #expect(layout.boardSize.width <= 800)
            #expect(layout.boardSize.height <= 800)
        }
    }
    @Test func windowStaysInsideSmallAndOffsetScreens() {
        for screen in [CGRect(x: 0, y: 40, width: 1440, height: 810), CGRect(x: -1920, y: 24, width: 1024, height: 650)] {
            #expect(screen.contains(EditorWindowGeometry.initialFrame(visibleFrame: screen)))
        }
    }
}
