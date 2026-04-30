import Foundation
import Combine

/// Verwaltet eine Queue von Eigennamen-Vorschlägen, die nacheinander als Toast
/// gezeigt werden. Jeder Vorschlag hat einen Countdown — läuft er ab, wird der
/// Begriff in `SettingsStore.properNouns` aufgenommen.
@MainActor
final class SuggestionPresenter: ObservableObject {

    struct Suggestion: Identifiable, Equatable {
        let id = UUID()
        let word: String
    }

    @Published var current: Suggestion?
    @Published var remainingSeconds: Int = 0

    let countdownDuration: Int = 5

    private let settings: SettingsStore
    private var queue: [String] = []
    private var timer: Timer?

    init(settings: SettingsStore) {
        self.settings = settings
    }

    func enqueue(_ words: [String]) {
        // Dedup gegen schon vorhandene + Queue + Stoppwörter
        let existing = Set(settings.properNouns.map { $0.lowercased() })
        let queued = Set(queue.map { $0.lowercased() })
        let new = words
            .filter { !existing.contains($0.lowercased()) }
            .filter { !queued.contains($0.lowercased()) }
            .filter { current?.word.lowercased() != $0.lowercased() }
        guard !new.isEmpty else { return }
        queue.append(contentsOf: new)
        if current == nil { showNext() }
    }

    /// User verwirft den aktuellen Vorschlag.
    func dismiss() {
        timer?.invalidate()
        timer = nil
        current = nil
        showNext()
    }

    /// Auto-Save nach Countdown.
    private func acceptCurrent() {
        timer?.invalidate()
        timer = nil
        if let word = current?.word, !settings.properNouns.contains(word) {
            settings.properNouns.append(word)
            Log.write("Eigenname automatisch übernommen: \(word)")
        }
        current = nil
        showNext()
    }

    private func showNext() {
        guard let word = queue.first else { current = nil; return }
        queue.removeFirst()
        current = Suggestion(word: word)
        remainingSeconds = countdownDuration
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.remainingSeconds -= 1
                if self.remainingSeconds <= 0 {
                    self.acceptCurrent()
                }
            }
        }
    }
}
