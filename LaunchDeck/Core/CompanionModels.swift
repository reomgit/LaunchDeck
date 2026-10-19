// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Presentation-only contract. No bookmark data, command source or credentials leave the desktop.
struct CompanionSnapshot: Codable, Sendable {
    var revision: Int
    var profileID: UUID?
    var profileName: String
    var mode: String
    var pageID: UUID
    var pageName: String
    var model: String
    var rows: Int
    var columns: Int
    var controls: [CompanionControl]
    var profiles: [CompanionProfile]
    var feedback: String?
    var animated: Bool?

    init(revision: Int, profileID: UUID? = nil, profileName: String, mode: String,
         pageID: UUID, pageName: String, model: String = "virtual", rows: Int = 8,
         columns: Int = 8, controls: [CompanionControl] = [], profiles: [CompanionProfile] = [], feedback: String? = nil, animated: Bool = false) {
        self.revision = revision; self.profileID = profileID; self.profileName = profileName
        self.mode = mode; self.pageID = pageID; self.pageName = pageName; self.model = model
        self.rows = rows; self.columns = columns; self.controls = controls
        self.profiles = profiles; self.feedback = feedback; self.animated = animated ? true : nil
    }
}

struct CompanionControl: Codable, Sendable {
    var index: Int
    var row: Int
    var column: Int
    var label: String
    var action: String
    var color: String
    var symbolName: String?
    var artworkID: String?
    var feedback: String?
    var enabled: Bool

    init(index: Int, row: Int, column: Int, label: String, action: String, color: String,
         symbolName: String? = nil, artworkID: String? = nil, feedback: String? = nil, enabled: Bool = true) {
        self.index = index; self.row = row; self.column = column; self.label = label
        self.action = action; self.color = color; self.symbolName = symbolName
        self.artworkID = artworkID; self.feedback = feedback; self.enabled = enabled
    }
}

struct CompanionProfile: Codable, Sendable, Identifiable {
    var id: UUID
    var name: String
    init(id: UUID, name: String) { self.id = id; self.name = name }
}

struct CompanionClient: Identifiable, Sendable {
    var id: UUID
    var name: String
    var pairedAt: Date
    var lastSeen: Date
}
