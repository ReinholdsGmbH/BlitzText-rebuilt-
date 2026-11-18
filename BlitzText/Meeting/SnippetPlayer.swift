import AVFoundation
import Combine
import Foundation

/// Spielt einen Ausschnitt einer Meeting-Spur ab: die Stimmprobe beim Zuordnen oder einen
/// einzelnen Redebeitrag im Transkript. Immer nur ein Ausschnitt gleichzeitig.
@MainActor
final class SnippetPlayer: ObservableObject {
    /// Kennung des gerade laufenden Ausschnitts, damit genau ein Knopf „Stopp“ zeigt.
    @Published private(set) var playingID: String?

    private var player: AVAudioPlayer?
    private var stopTimer: Timer?

    func toggle(id: String, url: URL, start: TimeInterval, end: TimeInterval) {
        if playingID == id { stop(); return }
        stop()
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.currentTime = max(0, start)
            player.play()
            self.player = player
            playingID = id
            let timer = Timer(timeInterval: max(0.2, end - start), repeats: false) { [weak self] _ in
                DispatchQueue.main.async { self?.stop() }
            }
            RunLoop.main.add(timer, forMode: .common)
            stopTimer = timer
        } catch {
            Log.write("SnippetPlayer: \(url.lastPathComponent) nicht abspielbar — \(error.localizedDescription)")
        }
    }

    func stop() {
        stopTimer?.invalidate()
        stopTimer = nil
        player?.stop()
        player = nil
        playingID = nil
    }
}

extension MeetingDocument {
    /// Spur, in der ein Beitrag zu hören ist: eigenes Mikrofon oder die getrennte Spur.
    func trackFile(for line: TranscriptLine) -> String {
        line.speaker == .me && diarizedTrack != MeetingArchive.mixedTrackFile
            ? MeetingArchive.microphoneTrackFile
            : diarizedTrack
    }

    /// Hörprobe einer Stimme: ein einzelner Beitrag, der als Text UND als Ton gezeigt wird.
    ///
    /// Bevorzugt Beiträge zwischen 4 und 20 Sekunden (lang genug zum Erkennen, kurz genug
    /// zum Anhören), davon den längsten. Abgespielt wird der Beitrag ganz, damit Text und
    /// Ton genau übereinstimmen. Früher zeigte die Karte den ersten Beitrag und spielte den
    /// längsten, gekappt auf 12 Sekunden, also zwei verschiedene Stellen.
    func sampleLine(of speakerID: String) -> TranscriptLine? {
        let candidates = lines.filter { $0.speakerID == speakerID }
        let comfortable = candidates.filter { (4...20).contains($0.end - $0.start) }
        let pool = comfortable.isEmpty ? candidates : comfortable
        return pool.max { ($0.end - $0.start) < ($1.end - $1.start) }
    }
}
