// SPDX-License-Identifier: GPL-3.0-only
import Foundation
struct DeckNavigation: Sendable {
    private(set) var pageID = DeckPage.homeID
    private(set) var history: [UUID] = []
    mutating func reset(pages: [DeckPage]) { history = []; pageID = pages.first(where: { $0.id == DeckPage.homeID })?.id ?? pages.first?.id ?? DeckPage.homeID }
    mutating func reconcile(pages: [DeckPage]) {
        history.removeAll { id in !pages.contains { $0.id == id } }
        if !pages.contains(where: { $0.id == pageID }) { reset(pages: pages) }
    }
    @discardableResult mutating func perform(_ action: NavigationAction, pages: [DeckPage], folders: [DeckFolder]) -> Bool {
        reconcile(pages: pages)
        let destination: UUID?
        switch action {
        case .home:
            history = []
            destination = pages.first { $0.id == DeckPage.homeID && $0.folderID == nil }?.id
        case .back: destination = history.popLast()
        case let .openFolder(id):
            guard folders.contains(where: { $0.id == id }) else { return false }
            destination = pages.first { $0.folderID == id }?.id
        case .previousPage, .nextPage:
            let current = pages.first { $0.id == pageID }
            let siblings = pages.filter { $0.folderID == current?.folderID }
            guard let index = siblings.firstIndex(where: { $0.id == pageID }) else { return false }
            destination = siblings[safe: index + (action == .nextPage ? 1 : -1)]?.id
        }
        guard let destination, destination != pageID else { return false }
        if action == .home { history = [] }
        else if case .openFolder = action { history.append(pageID) }
        pageID = destination; return true
    }
}
