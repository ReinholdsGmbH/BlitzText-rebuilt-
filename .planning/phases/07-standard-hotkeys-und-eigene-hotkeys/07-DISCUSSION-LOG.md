# Phase 999.6 Discussion Log

**Date:** 2026-04-30
**Workflow:** /gsd-discuss-phase 999.6
**Mode:** default (4 Bereiche, single-question turns)

## Bereichsauswahl

**Frage:** Welche Bereiche möchtest du für Phase 999.6 diskutieren?
**Optionen:** Trigger-Architektur · Default-Set & Migration · UI für Vergabe · Konflikt- & Reset-Verhalten
**Auswahl:** alle vier

## Bereich 1: Trigger-Architektur

**Frage 1:** Welches Trigger-Schema soll Custom-Hotkeys unterstützen?
- Optionen: Nur fn+Modifier · Freie Tastenkombos · Hybrid
- **Auswahl:** Hybrid (fn-Schnellpfad für Hold, freie Kombos pro Mode für Toggle)

**Frage 2:** Wie soll der Code-Pfad für freie Tastenkombos umgesetzt werden?
- Optionen: Carbon RegisterEventHotKey · MASShortcut/HotKey-Package · NSEvent.addGlobalMonitor
- **Auswahl:** MASShortcut / HotKey Swift-Package (externe SPM-Dep mit Recorder-View out-of-the-box)

## Bereich 2: Default-Set & Migration

**Frage:** Welche Defaults werden bei Erst-Installation und Reset ausgeliefert?
- Optionen: Aktuelle fn-Kombos behalten · Neue ergonomischere Defaults · fn für Hold + ⌘-Defaults für Toggle
- **Auswahl:** Aktuelle fn-Kombos behalten (Toggle-Pfad initial leer; bestehende Nutzer spüren keine Änderung)

## Bereich 3: UI für Vergabe

**Frage:** Wo und wie wird die Hotkey-Konfiguration im Settings-Fenster präsentiert?
- Optionen: Eigener Tab "Hotkeys" · Inline im "Modi"-Tab · Section im "Allgemein"-Tab
- **Auswahl:** Eigener Tab "Hotkeys"

## Bereich 4: Konflikt- & Reset-Verhalten

**Frage 1:** Wie soll die App auf Hotkey-Konflikte reagieren?
- Optionen: Strikt (Fehler) · Nachsichtig (Warn-Banner) · Nur In-App-Konflikte prüfen
- **Auswahl:** Nachsichtig — registrieren mit Warn-Banner

**Frage 2:** Wie wird der Reset auf Standard-Hotkeys ausgelöst?
- Optionen: Pro-Hotkey-Button · Globaler Reset · Beides
- **Auswahl:** "Auf Standard zurücksetzen"-Button pro Hotkey

## Deferred Ideas

_Keine — Diskussion blieb scope-konform._

## Notes

- Phase ist BACKLOG (999.x). Plans existieren noch nicht; Plan-Phase wird erst nach Promotion via `/gsd-review-backlog` aufgesetzt.
- Researcher hat zwei offene technische Fragen einzulösen: (a) Swift-6-Concurrency-Kompatibilität von HotKey/MASShortcut, (b) zuverlässige System-Hotkey-Konflikt-Detection (sonst kuratierte Fallback-Liste).
