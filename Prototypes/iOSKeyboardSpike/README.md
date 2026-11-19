# BlitzSpike (iOS-Machbarkeits-Spike, Wegwerfcode)

Prüft, ob Haupt-App mit Hintergrund-Audio, Tastatur-Erweiterung und App Group mit einem
kostenlosen Personal Team signiert und auf dem iPhone läuft. Transkription mit Parakeet TDT v3
über FluidAudio; das Modell wird beim Session-Start vorgeladen (erster Start lädt es herunter).

## Bauen

1. `cp Local.xcconfig.example Local.xcconfig`, Team-ID eintragen.
2. `xcodegen generate`
3. `BlitzSpike.xcodeproj` in Xcode öffnen, iPhone wählen, Run.

## Auf dem iPhone einrichten

1. Einstellungen > Allgemein > Tastatur > Tastaturen > Tastatur hinzufügen > BlitzSpike.
2. BlitzSpike antippen > „Vollen Zugriff erlauben“.
3. App einmal öffnen, Mikrofon erlauben.

## Funktionen

- **Diktat-Tastatur (QWERTZ)**: Umlaute in den Reihen, ß per langem Druck auf s, Ziffern- und
  Zeichenebene, Großschreibung am Satzanfang, Doppel-Leerzeichen setzt einen Punkt.
  Wortvorschläge und Swipe über Apples Rechtschreibprüfung (UITextChecker, Deutsch).
- **Diktat**: Mikro-Knopf links in der Vorschlagsleiste. Ohne Session öffnet er die App,
  mit Session startet und stoppt er die Aufnahme; Parakeet transkribiert in der App.
- **App**: Wortzähler (Diktate und Meetings), Verlauf zum Kopieren und Löschen,
  Meetings mit Transkript, Sprechertrennung, eigenen und automatischen Notizen
  (Apple Intelligence auf dem Gerät), Einstellungen mit Protokoll.

## Testfälle

1. Tastatur: tippen, Umlaute, ß (lange auf s), 123-Ebene, Doppel-Leerzeichen, Vorschlag antippen.
2. Swipe: „hallo“, „danke“, „morgen“ wischen; Alternativen in der Leiste; Rücktaste löscht das ganze Wort.
3. Diktat in Notizen und in einer zweiten App; Eintrag erscheint im Verlauf, Zähler steigt.
4. Meeting 2 bis 3 Minuten mit zwei Stimmen; Transkript mit „Sprecher 1/2“, Notizen, Titel.
5. Notizen kopieren, Transkript kopieren, Umbenennen, Löschen.
6. Akku: Session 30 min ohne Kabel, Auto-Stop „aus“, Akku-Zeilen im Protokoll.
