# BlitzText für iOS

Diktat-Tastatur und Meeting-Aufnahme fürs iPhone, Gegenstück zur Mac-App. Transkription auf dem
Gerät mit Parakeet TDT v3 (FluidAudio), Notizen mit Apple Intelligence, Übergabe an den Mac über
OneDrive. Entstanden aus einer Machbarkeitsprüfung, siehe
`.planning/phases/999.1-ios-ipados-port/999.1-MACHBARKEIT.md`.

## Bauen

1. `cp Local.xcconfig.example Local.xcconfig`, Team-ID eintragen (kostenloses Personal Team reicht).
2. `xcodegen generate`
3. `BlitzText-iOS.xcodeproj` in Xcode öffnen, iPhone wählen, Run.
4. Auf dem iPhone einmal unter Einstellungen › Allgemein › VPN & Geräteverwaltung dem Entwickler vertrauen.

Die Signatur des Personal Teams gilt 7 Tage, danach neu bauen und installieren.
Das App-Symbol entsteht mit `swift Scripts/make-icon.swift App/Assets.xcassets/AppIcon.appiconset/AppIcon.png`.

## Auf dem iPhone einrichten

1. Einstellungen › Allgemein › Tastatur › Tastaturen › Tastatur hinzufügen › BlitzText.
2. BlitzText antippen › „Vollen Zugriff erlauben“ (nötig für das Mikro in der Tastatur).
3. App öffnen, Mikrofon erlauben. Beim ersten Start baut die App das Swipe-Wörterbuch (rund eine Minute).
4. Einstellungen › OneDrive › „Mit OneDrive verbinden …“ (persönliches Microsoft-Konto).

## Funktionen

- **Tastatur**: QWERTZ mit Umlauten, ß und Ziffern per langem Druck, Ziffern- und Zeichenebene,
  Großschreibung am Satzanfang, Doppel-Leerzeichen setzt einen Punkt, Rücktaste löscht nach 2 s
  ganze Wörter, Leertaste halten und ziehen bewegt den Cursor.
- **Vorschläge**: Apples Rechtschreibprüfung plus eigene Wörter und Kontaktnamen; ein unbekanntes
  Wort steht in „…“ zur Wahl und wird beim Antippen gemerkt.
- **Swipe**: Formvergleich der Spur mit der idealen Linie jedes Wortes (SHARK2) und Wörterbuch
  mit Rangfolge aus Apples Rechtschreibprüfung.
- **Diktat**: Mikro in der Vorschlagsleiste (links oder rechts wählbar). Eine Session hält das
  Mikrofon offen, danach diktierst du in jeder App ohne App-Wechsel. „Herz Emoji“ wird ❤️.
- **Meetings**: Aufnahme im Hintergrund, Fortsetzen, Transkript mit Sprechern, eigene und
  automatische Notizen, Kopieren, Teilen, Umbenennen, Löschen.
- **Übergabe an den Mac**: fertige Meetings und das Wörterbuch über OneDrive
  („Anwendungen/BlitzText iPhone“); die Mac-App übernimmt sie unverändert.

## Kennungen

- App `de.reinholds.blitztext.ios`, Tastatur `de.reinholds.blitztext.ios.keyboard`
- App Group `group.de.reinholds.blitztext`, URL-Schema `blitztext://`
- OneDrive-Anmeldung: Umleitungs-URI `msauth.de.reinholds.blitztext.ios://auth` in der
  Entra-App-Registrierung „BlitzText iPhone“
