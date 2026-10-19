// SPDX-License-Identifier: GPL-3.0-only
import Foundation

extension Profile {
    subscript(layout model: DeviceModel) -> DeckModelLayout {
        get { layoutForEditing(model) }
        set { setLayout(newValue, for: modelOverridesEnabled ? model : .miniMK3) }
    }
}
