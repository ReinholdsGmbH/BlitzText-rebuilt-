import Foundation

/// Sliding-Window-ETA-Estimator über `DownloadProgress.fractionCompleted ∈ [0, 1]`.
/// Pure data — kein MainActor, isoliert testbar. Rückgabe `nil` bedeutet
/// "Geschwindigkeit wird ermittelt …" (UI-SPEC § Copywriting).
struct ETAEstimator {
    private struct Sample {
        let time: Date
        let fraction: Double
    }

    private var samples: [Sample] = []
    private let windowSeconds: TimeInterval

    init(windowSeconds: TimeInterval = 5.0) {
        self.windowSeconds = windowSeconds
    }

    mutating func reset() {
        samples.removeAll()
    }

    /// Liefert geschätzte Restsekunden, oder `nil` wenn noch nicht genug Datenpunkte
    /// (Anlaufphase, oder Stagnation in der CoreML-Compile-Phase).
    mutating func tick(fraction: Double, now: Date = Date()) -> Double? {
        samples.append(.init(time: now, fraction: fraction))
        let cutoff = now.addingTimeInterval(-windowSeconds)
        samples.removeAll { $0.time < cutoff }

        guard let first = samples.first, samples.count >= 2 else {
            return nil
        }
        let elapsed = now.timeIntervalSince(first.time)
        let progressDelta = fraction - first.fraction
        guard elapsed > 0.5, progressDelta > 0.001 else { return nil }
        let rate = progressDelta / elapsed
        let remaining = max(0, 1.0 - fraction)
        return remaining / rate
    }
}
