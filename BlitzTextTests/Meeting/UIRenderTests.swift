import AppKit
import SwiftUI
import Testing
@testable import BlitzText

/// Rendert Bausteine der Oberfläche als Bild, um Gestaltung ohne laufende App zu prüfen.
/// Nur mit TEST_RUNNER_BLITZTEXT_RENDER_DIR.
@MainActor
struct UIRenderTests {
    nonisolated static let dir = ProcessInfo.processInfo.environment["BLITZTEXT_RENDER_DIR"]

    @Test("Zusammenfassung und Reiter als Bild", .enabled(if: dir != nil))
    func renders() throws {
        let md = """
        ### Zusammenfassung
        - Das Team stimmt den Testumfang für die Migration ab.
        - Die **Folie** soll den Teststatus je Bereich zeigen.
        ### Entscheidungen
        - Screenshot des Status kommt auf die erste Seite.
        ### Aufgaben
        - [ ] Ich: Folie bis Freitag anpassen
        - [x] Anna: Testfälle in X-Ray anlegen
        ### Offene Fragen
        - Reicht der Platz auf der ersten Seite?
        """
        let view = VStack(alignment: .leading, spacing: 18) {
            CapsuleToggle(options: [(0, "Zusammenfassung"), (1, "Meine Notizen"), (2, "Transkript")], selection: .constant(0))
            SummaryText(markdown: md)
        }
        .padding(28)
        .frame(width: 760)
        .background(MeetingTheme.backgroundTertiary)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try #require(renderer.nsImage)
        let tiff = try #require(image.tiffRepresentation)
        let png = try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: try #require(Self.dir)).appendingPathComponent("summary.png"))
    }
}
