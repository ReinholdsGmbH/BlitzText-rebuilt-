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
    private let ledger: CandidateLedger
    private var queue: [String] = []
    private var timer: Timer?

    init(settings: SettingsStore, ledger: CandidateLedger = CandidateLedger()) {
        self.settings = settings
        self.ledger = ledger
    }

    func enqueue(_ words: [String]) {
        let queued = Set(queue.map { $0.lowercased() })
        var toShow: [String] = []

        for word in words {
            let lower = word.lowercased()

            // 1. Exakt bereits bekannt → ignorieren.
            if settings.properNounTexts.contains(where: { $0.lowercased() == lower }) { continue }
            // schon in der Queue oder aktuell sichtbar → ignorieren.
            if queued.contains(lower) || current?.word.lowercased() == lower { continue }

            // 2. Fuzzy-Variante eines bestehenden Eintrags → als Alias mergen, nicht vorschlagen.
            if let term = settings.properNouns.first(where: { t in
                t.allForms.contains(where: { StringSimilarity.isFuzzyMatch($0, word) })
            }) {
                settings.addAlias(word, toTermID: term.id)
                settings.bumpOccurrence(termID: term.id)
                Log.write("Eigenname-Variante als Alias gemergt: \(word) → \(term.text)")
                continue
            }

            // 3. Brandneuer Kandidat → erst ab Schwelle (≥2×) vorschlagen.
            if ledger.record(word) {
                toShow.append(word)
            }
        }

        guard !toShow.isEmpty else { return }
        queue.append(contentsOf: toShow)
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
        if let word = current?.word,
           !settings.properNounTexts.contains(where: { $0.lowercased() == word.lowercased() }) {
            settings.properNouns.append(ProperNoun(text: word, occurrenceCount: 2, lastSeenAt: Date()))
            ledger.reset(word)
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
