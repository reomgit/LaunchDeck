// SPDX-License-Identifier: GPL-3.0-only
// Copyright © 2026 Reom Nagasaka

import Foundation

/// Stateless analysis only: callers retain no PCM after computing the scalar result.
enum AudioLevel {
    nonisolated static func rms<S: Sequence>(_ samples: S) -> Double where S.Element == Float {
        var sum = 0.0
        var count = 0
        for sample in samples {
            let value = sample.isFinite ? Double(sample) : 0
            sum += value * value
            count += 1
        }
        return count > 0 ? sqrt(sum / Double(count)) : 0
    }

    /// Map -60…0 dBFS onto 0…1, keeping silence and invalid samples at zero.
    nonisolated static func normalized(rms: Double) -> Double {
        guard rms.isFinite, rms > 0 else { return 0 }
        return min(1, max(0, (20 * log10(rms) + 60) / 60))
    }
}
