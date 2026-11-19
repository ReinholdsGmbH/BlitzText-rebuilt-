# BlitzSpike (iOS-Machbarkeits-Spike, Wegwerfcode)

Prüft, ob Haupt-App mit Hintergrund-Audio, Tastatur-Erweiterung und App Group mit einem
kostenlosen Personal Team signiert und auf dem iPhone läuft. Keine Transkription: Das
"Diktat" fügt nur Dauer und Spitzenpegel der Aufnahme als Text ein.

## Bauen

1. `cp Local.xcconfig.example Local.xcconfig`, Team-ID eintragen.
2. `xcodegen generate`
3. `BlitzSpike.xcodeproj` in Xcode öffnen, iPhone wählen, Run.

## Auf dem iPhone einrichten

1. Einstellungen > Allgemein > Tastatur > Tastaturen > Tastatur hinzufügen > BlitzSpike.
2. BlitzSpike antippen > „Vollen Zugriff erlauben“.
3. App einmal öffnen, Mikrofon erlauben.

## Testfälle

1. In Notizen auf die BlitzSpike-Tastatur wechseln, „Session starten“: Öffnet sich die App?
2. Zurück per Wischgeste oder „◀ Notizen“: Steht dort „Session läuft“?
3. „Diktat starten“, sprechen, „Fertig“: Erscheint `[Spike x,x s, Spitze -yy dB]` im Text?
4. Wechsel in eine andere App, erneut diktieren: ohne App-Wechsel?
5. Akku-Verbrauch: Session 30 min offen lassen, in der App Akku Start/jetzt ablesen.
6. Auto-Stop: 5 min Leerlauf, danach zeigt die Tastatur „Keine Session“.
