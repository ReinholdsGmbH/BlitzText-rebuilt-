import Foundation
import FoundationModels

/// `@Generable`-Schema für den Deeskalations-Output von `blitztextRant`.
/// Constrained Decoding garantiert Schema-Validität auf Token-Ebene und
/// verhindert "Hier ist die entschärfte Version: …"-Präambeln.
/// Schema bleibt minimal (1 Feld), siehe RESEARCH.md Pitfall 5.
@Generable
struct DeescalatedOutput {
    @Guide(description: "Der entschärfte Text in deutscher Sprache, sachlich-freundlich, ohne Vorbemerkungen oder Anführungszeichen.")
    var neutralText: String
}
