import Testing
@testable import BlitzText

struct SpeechSegmenterTests {

    /// 30-ms-Frames: Stille 0.001, Sprache 0.2.
    private func frames(_ pattern: [(seconds: Double, loud: Bool)]) -> [Float] {
        pattern.flatMap { part in
            Array(repeating: part.loud ? Float(0.2) : Float(0.001), count: Int((part.seconds / 0.03).rounded()))
        }
    }

    @Test("Reine Stille ergibt keine Abschnitte")
    func silenceYieldsNothing() {
        #expect(SpeechSegmenter().spans(frameRMS: frames([(10, false)])).isEmpty)
    }

    @Test("Ein Sprechblock ergibt einen Abschnitt mit Zugabe an beiden Enden")
    func singleBurst() throws {
        let spans = SpeechSegmenter().spans(frameRMS: frames([(2, false), (3, true), (2, false)]))
        let span = try #require(spans.first)
        #expect(spans.count == 1)
        #expect(abs(span.start - 1.8) < 0.05)
        #expect(abs(span.end - 5.2) < 0.05)
    }

    @Test("Lange Pause trennt, kurze Pause nicht")
    func pausesSplitOnlyWhenLong() {
        let segmenter = SpeechSegmenter()
        let split = segmenter.spans(frameRMS: frames([(1, false), (2, true), (1.5, false), (2, true), (1, false)]))
        let joined = segmenter.spans(frameRMS: frames([(1, false), (2, true), (0.3, false), (2, true), (1, false)]))
        #expect(split.count == 2)
        #expect(joined.count == 1)
    }

    @Test("Klicks unter der Mindestlänge fallen weg")
    func dropsClicks() {
        #expect(SpeechSegmenter().spans(frameRMS: frames([(2, false), (0.1, true), (2, false)])).isEmpty)
    }

    @Test("Durchgehende Rede wird spätestens nach maxSegment geteilt")
    func longSpeechIsCapped() {
        let segmenter = SpeechSegmenter()
        let spans = segmenter.spans(frameRMS: frames([(70, true)]))
        #expect(spans.count >= 3)
        for span in spans {
            #expect(span.duration <= segmenter.maxSegment + 2 * segmenter.padding + 0.05)
        }
    }
}
