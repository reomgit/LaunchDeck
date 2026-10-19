// SPDX-License-Identifier: GPL-3.0-only
import Foundation

enum LightingStatusResolver {
    static func applicationStates(layout: ResolvedLayout, runningBundleIDs: Set<String>, frontmostBundleID: String?) -> [Int: ApplicationLightState] {
        guard layout.lighting.showsApplicationStatus else { return [:] }
        var result: [Int: ApplicationLightState] = [:]
        for index in 0..<layout.controlCount {
            guard case let .step(.launchApplication(bundleIdentifier)) = layout.binding(at: index)?.action,
                  runningBundleIDs.contains(bundleIdentifier) else { continue }
            result[index] = bundleIdentifier == frontmostBundleID ? .frontmost : .running
        }
        return result
    }
}
