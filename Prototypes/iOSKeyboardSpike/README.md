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

## Testfälle

1. In Notizen auf die BlitzSpike-Tastatur wechseln, „Session starten“: Öffnet sich die App?
2. Zurück per Wischgeste oder „◀ Notizen“: Steht dort „Session läuft“?
3. „Diktat starten“, sprechen, „Fertig“: Erscheint der gesprochene Text? Rechenzeit und
   Vorder-/Hintergrund stehen im Protokoll der App.
4. Wechsel in eine andere App, erneut diktieren: ohne App-Wechsel?
5. Akku-Verbrauch: Session 30 min offen lassen, in der App Akku Start/jetzt ablesen.
6. Auto-Stop: 5 min Leerlauf, danach zeigt die Tastatur „Keine Session“.
