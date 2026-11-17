# Meeting-Aufnahme

Stand: 17.11.2026. Beschreibt die Capture-Schicht in `BlitzText/Meeting/` und warum sie so
gebaut ist. Die Verdrahtung in die Bedienoberfläche fehlt noch.

## Warum Core Audio Taps und nicht ScreenCaptureKit

Beide Wege kommen an das Systemaudio. Entschieden wurde für Core Audio Process Taps
(`AudioHardwareCreateProcessTap`, ab macOS 14.2):

| | Core Audio Tap | ScreenCaptureKit |
|---|---|---|
| Berechtigung | Systemaudio-Aufnahme, kein Bildschirmzugriff | Bildschirm- & Systemaudioaufnahme |
| Erneute Nachfrage | nein | periodisch, berichtet werden 30 Tage |
| Aufnahme-Indikator | nein | ja, in der Menüleiste |
| Einzelne Prozesse | ja, über PID | nein, nur ganzes System oder Fenster |

Für eine Diktier-App ist die engere Berechtigung das Argument. Eine App, die Text einfügt,
sollte nicht nebenbei nach Bildschirmaufnahme fragen.

Die Beschränkung auf einzelne Prozesse ist der zweite Grund: Nur die Konferenz-App wird
mitgeschnitten, nicht Musik, Systemtöne oder ein paralleles Gespräch. Das ist nachgemessen,
siehe unten.

## Aufbau

```
MeetingRecorder                  orchestriert beide Spuren
├── AudioRecorder (bestehend)    eigenes Mikrofon  → 16 kHz mono WAV
└── SystemAudioTap               Ausgabe der Apps  → 16 kHz mono WAV
MeetingDetector                  welche Apps sind Meeting-Quellen
```

Zwei getrennte Spuren statt eines Mixdowns. Damit fällt die Trennung „ich" gegen „alle
anderen" ohne Diarisierung ab: Die eigene Stimme kommt über das Mikrofon, die der anderen
über den Rückkanal, und beide vermischen sich nie.

Die Kette im Tap: PID → `AudioObjectID` → `CATapDescription` → Tap → privates
Aggregate-Device → IOProc. Ein Tap allein liefert keine Samples; erst ein Aggregate-Device,
das ihn in seiner Tap-Liste führt, lässt sich auslesen.

## Zwei Fallstricke, die Zeit gekostet haben

**Stille statt Fehler.** Fehlt `NSAudioCaptureUsageDescription` in der Info.plist, verweigert
TCC den Zugriff, ohne das zu melden: `AudioHardwareCreateProcessTap` liefert weiter Erfolg,
die Callbacks kommen, und sie enthalten nur Nullen. Von echter Stille ist das nicht zu
unterscheiden. Deshalb misst `SystemAudioTap` den Peak und meldet `wasSilent` nach oben,
statt eine leere Datei als gelungenen Mitschnitt durchzureichen. Der Key steht in
`BlitzText/Info.plist` **und** in `project.yml` — sonst überschreibt ihn der nächste
XcodeGen-Lauf.

**Formatfehler -50.** Das Format, das der Tap meldet, lässt sich nicht unverändert als
Dateiformat an `AVAudioFile` geben; jeder Schreibversuch endet mit `-50`. Die Spur wird
deshalb im Callback nach 16 kHz mono Int16 konvertiert, denselben Weg, den
`AudioRecorder.write` ohnehin geht. Nebeneffekt: beide Spuren haben dasselbe Format und sind
direkt transkribierbar.

## Nachgemessen

Prüf-Harness: `SystemAudioTap` plus Info.plist in ein signiertes Mini-Bundle gepackt, damit
TCC greift.

| Fall | Ergebnis |
|---|---|
| Globaler Tap, Ton läuft | Peak 0,359, 195 572 Bytes für 6 s (rechnerisch 192 000 + Header) |
| Tap auf einen sprechenden Prozess | Peak 0,604 |
| Tap auf stillen Prozess, während parallel ein lauter läuft | Peak 0,000 |
| Globaler Tap im selben Moment | Peak 0,570 |

Die letzten beiden Zeilen sind der Isolationsbeweis: Was nicht getappt wird, landet nicht in
der Aufnahme.

## Meeting-Erkennung

Zwei Wege, beide ohne Netzzugriff und ohne Kalender.

Native Apps über die Bundle-ID: Zoom (`us.zoom.xos`), Teams (`com.microsoft.teams`,
`.teams2`, `.teams2.modulehost`), Webex (`com.cisco.webexmeetingsapp`).

Browser über den Fenstertitel: macOS hängt an ein Fenster, dessen Tab Mikrofon oder Kamera
nutzt, einen Statuszusatz an („ — Microphone recording"). Nur Mikrofon- und Kamerazusätze
zählen; „Audio playing" allein ist Musik oder ein Video. Der Walk läuft über die
Accessibility-API, die BlitzText für den Auto-Insert ohnehin hat. Ohne diese Berechtigung
bleibt die Browser-Erkennung still aus, statt zu raten.

Welcher Tab es ist und wie das Meeting heißt, steht bewusst nicht drin. Das bräuchte einen
tieferen Accessibility-Walk und kostet Laufzeit. Für die Auswahl der zu tappenden Prozesse
reicht die PID.

## Rechtliches

Die Aufnahmeschicht fragt niemanden um Erlaubnis. Wer in einem Meeting mitschneidet, braucht
das Einverständnis der anderen; bei vertraulich gesprochenem Wort greift in Deutschland
§ 201 StGB, und das ist keine Formalie.

Wispr Flow löst das so: Bevor aufgenommen wird, schreibt die App über die
Accessibility-API eine Hinweisnachricht in den Chat des Meetings. Es gibt eigene Strategien
für Zoom, Teams, Google Meet und Slack, einen Fallback über die Zwischenablage, wenn das
direkte Setzen des Textfelds nicht greift, und eine Prüfung, ob die Nachricht tatsächlich
abgeschickt wurde. Der Aufwand zeigt, wie ernst der Punkt genommen wird.

Entscheidung für BlitzText (17.11.2026): keine automatische Chat-Nachricht. BlitzText wird
nur vom Entwickler selbst genutzt, die Aufnahme startet ausschließlich auf Klick, und die
Teilnehmenden zu informieren bleibt Sache des Nutzers. An der Rechtslage für die anderen im
Meeting ändert das nichts.

## Bedienung

Gestartet wird nur von Hand: im Menü-Popover über die Zeile „Meeting" oder über den Knopf in der Meeting-Pille. Die Pille sitzt unten in der Bildschirmmitte, unterhalb des Diktat-HUDs, und erscheint von selbst, sobald eine Konferenz-App das Mikrofon benutzt (Hinweis „Teams-Meeting erkannt" mit „Aufnehmen"). Ein bloß geöffnetes Teams löst den Hinweis nicht aus. Die Erkennung prüft alle fünf Sekunden `kAudioProcessPropertyIsRunningInput` der Core-Audio-Prozessliste, bei Browsern den Mikrofon-Zusatz im Fenstertitel.

Während der Aufnahme zeigt die Pille die Laufzeit und „Stopp", das Menüleisten-Icon ist rot. Danach zeigt sie den Fortschritt („Transkribiere 12 von 40", „Schreibe Protokoll") und am Ende „Protokoll fertig" mit „Öffnen". Einen Chat-Hinweis an die Teilnehmenden verschickt BlitzText bewusst nicht; die Entscheidung, ob und wie die anderen informiert werden, liegt beim Nutzer.

## Vom Mitschnitt zum Protokoll

1. Beide Spuren wandern sofort nach dem Stopp nach `~/Documents/BlitzText Meetings/<Datum Uhrzeit Quelle>/` (`mikrofon.wav`, `gegenseite.wav`). Das passiert vor der Transkription, weil BlitzText `blitztext-*` im Temp-Ordner beim Beenden löscht.
2. `SpeechSegmenter` zerlegt jede Spur anhand des Pegels in Sprechabschnitte (Pause ab 0,8 s trennt, spätestens nach 25 s wird an der leisesten Stelle geteilt). Das liefert die Startzeiten fürs Verschränken und hält den Speicher bei langen Meetings klein.
3. Jeder Abschnitt geht einzeln durch Parakeet, immer lokal und ohne Diarisierung, unabhängig vom Diktat-Backend.
4. `TranscriptMerger` sortiert beide Spuren nach Zeit, entfernt Echos (die Gegenseite, die ohne Kopfhörer über das Mikrofon wieder hereinkommt) und fasst aufeinanderfolgende Beiträge zusammen.
5. `protokoll.md` wird sofort mit dem Transkript geschrieben, danach um die Zusammenfassung ergänzt. Fällt Ollama aus, bleibt das Transkript stehen und die Pille meldet den Grund.
6. Die Zusammenfassung läuft standardmäßig über Ollamas native `/api/chat` mit `num_ctx` 32 768. Die OpenAI-kompatible Schnittstelle nimmt `num_ctx` nicht an, und ohne den Wert kürzt Ollama lange Eingaben still. Transkripte über 60 000 Zeichen werden in Teilen zusammengefasst und dann vereint.

Gemessen mit echter Sprache (zwei `say`-Sätze, Parakeet und `phi4-mini`): beide Sätze wörtlich korrekt, „Ich" und „Andere" richtig zugeordnet, Entscheidung und Aufgabe im Protokoll, 18 Sekunden gesamt. Der Test liegt in `MeetingLiveTests` und läuft nur mit `TEST_RUNNER_BLITZTEXT_LIVE_DIR=<Ordner mit me.wav und other.wav>`.

## Anbieter für die Zusammenfassung

Einstellungen → Meetings wählt, wer die Zusammenfassung schreibt. Die Transkription bleibt in jedem Fall lokal.

| Anbieter | Endpunkt | Standardmodell | Daten |
|---|---|---|---|
| Ollama (Standard) | `<ollamaBaseURL>/api/chat`, `num_ctx` 32 768 | Diktat-Rewrite-Modell | bleiben auf dem Mac |
| OpenRouter | `https://openrouter.ai/api/v1/chat/completions` | `anthropic/claude-haiku-5.5` | Transkript geht an OpenRouter und weiter an den jeweiligen Modellanbieter |
| Requesty | `https://router.requesty.ai/v1/chat/completions` | `bedrock/claude-haiku-5-5@eu-central-1` | Transkript geht an Requesty, Verarbeitung im Standard in der AWS-Region Frankfurt |

Beide Cloud-Anbieter sprechen das OpenAI-Format (`OpenAICompatibleChat`). Die Modelllisten kommen öffentlich ohne Schlüssel von `/models` (Stand 17.11.2026: 474 bei OpenRouter, 756 bei Requesty, davon nur `api: "chat"` angezeigt). Die Schlüssel liegen im Schlüsselbund (`openrouter-api-key`, `requesty-api-key`) und werden wie der OpenAI-Schlüssel nur im Hintergrund gelesen. Ein unbekannter Anbieterwert aus einem späteren Build fällt auf Ollama zurück, nie still in die Cloud.

## Sprecher erkennen und lernen

Die Gegenseite läuft vor der Transkription durch die Sprechertrennung von FluidAudio, einmal über die ganze Spur. Ihre Sprecherwechsel sind zugleich die Schnittgrenzen für Parakeet, damit jeder Redebeitrag genau einer Stimme gehört. Namen kommen aus drei Quellen:

1. Gespeicherte Profile: Vor jeder Trennung werden die benannten Profile geladen. Passt eine Stimme, trägt sie den Namen, und FluidAudio mittelt die neuen Stimmproben gleitend ins Profil ein (`updateMainEmbedding`, EMA). Jedes Meeting macht das Profil genauer.
2. Die Meeting-App: Wie Wispr Flows `MeetingSpeakerPoller` liest `ActiveSpeakerPoller` während der Aufnahme jede Sekunde per Accessibility, wen Teams oder Zoom als Sprecher markiert („Anna Müller, spricht"). Für Chromium-basierte Apps setzt er vorher `AXManualAccessibility`. `SpeakerNameSuggester` ordnet die Namen den Stimmen zu, wenn einer klar dominiert (mindestens drei Belege und 60 Prozent). Die genauen Beschriftungen in Teams und Zoom sind noch nicht in einem echten Meeting geprüft.
3. Von Hand: In der Meeting-Bibliothek steht bei unbekannten Stimmen „Sprecher zuordnen" mit einem Zitat und der Sprechzeit. Der Name wird übernommen, und aus bis zu 60 Sekunden dieser Stimme entsteht ein Profil oder ein gleichnamiges wird nachgeschärft.

Unbenannte Stimmen werden nie gespeichert. Stimmprofile sind biometrische Daten (DSGVO Art. 9), hier von Kolleginnen und Kollegen. Ein Profil entsteht erst mit einem Namen, Namen aus der Meeting-App gelten bis zur Bestätigung nur als Vorschlag.

Gemessen mit echten MacWhisper-Aufnahmen (17.11.2026, Wegwerf-Profilspeicher): Profil aus 94 s Mikrofon gelernt, danach im Mikrofon einer anderen Aufnahme 89 Prozent der Sprechzeit richtig erkannt, auf der Gegenseite derselben Aufnahme 0 Prozent Verwechslung. Eine 293-s-Mischspur ergab drei Stimmen, die eigene mit Namen, Verarbeitung in 20 s. Der Test liegt in `MeetingSpeakerLiveTests`.

## Import

„Importieren" im Popover oder in der Bibliothek nimmt eine Mischspur oder ein Paar aus Mikrofon und Gegenseite. MacWhisper legt Aufnahmen als `…_mic-audio_…`, `…_app-audio_…` und `…_merged-audio_…` unter `~/Library/Application Support/MacWhisper/Database/ExternalMedia/` ab. Ein Paar wird an `mic-audio` erkannt, egal in welcher Reihenfolge es gewählt wird. Jede von AVFoundation lesbare Datei wird blockweise nach 16 kHz mono gewandelt.

## Oberfläche nach Wispr Flow

Grundlage sind Wispr Flows eigene Design-Tokens aus `app.asar` (v1.6.1483) und ein Blick auf das laufende Notetaker-Fenster. Übernommen in `MeetingTheme`: die Paletten `sand` (warmes Off-White), `vast` (warmes Dunkelgrau), `dawn` (Lavendel, Primärfarbe) und `glow`, dieselben semantischen Zuordnungen für hell und dunkel. Im App-Fenster setzt Wispr Überschriften in Sans-Serif (Figtree), die Serifenschrift EB Garamond nur auf der Website; BlitzText nimmt deshalb die Systemschrift.

- Pille: schwarze Kapsel wie Wispr Flows Aufnahmeleiste, während der Aufnahme nur Pegelbalken, Laufzeit und grünes Stopp-Quadrat. Bei sehr kurzen Mitschnitten (unter 12 Wörtern) fragt sie wie Wispr „Versehentlich gestartet? Verwerfen / Behalten“.
- Bibliothek: Navigation auf Sand, weiße Inhaltskarte, Meetings nach Tagen gruppiert mit grüner Wellenform und Dauer, „…“-Menü beim Überfahren (Finder, Kopieren, Löschen in den Papierkorb), Notizen und Transkript per Kapsel-Umschalter, Transkript als Sprechblasen mit farbigem Namen.
- Zuordnen: Karte „Wer spricht hier?“ mit Hörprobe (längster Beitrag, höchstens 12 Sekunden) und Abspielknopf an jeder Sprechblase.

Startparameter für Tests: `--meetings` öffnet die Bibliothek, `--import-meeting <Datei> [<Datei>]` importiert direkt.

## Ablage im Wissensordner

`VaultExporter` legt jedes Meeting direkt im Baalda-Vault ab (`~/Documents/Baalda Vaults/Raba IT/Wissen`, einstellbar unter System), mit den Bereichsregeln und dem Dateiformat von `mw-route`: `<Bereich>/transkripte/TT.MM.JJ_hh.mm_Titel.md`, Überschrift `TT.MM.JJ_hh:mm_Titel`, Kopfzeilen `**Datum:**`, `**AI-Titel:**`, `**Projekt:**`. Den Titel schreibt das Zusammenfassungsmodell in die erste Zeile (`TITEL: …`). Jede Korrektur in der Bibliothek überschreibt die Datei; ein Bereichswechsel verschiebt sie. Die `log.md` des Bereichs bekommt beim ersten Ablegen eine Zeile. Über den Baalda-MCP ist der Vault von anderen Rechnern lesbar; ein eigener MCP-Server ist deshalb vorerst nicht nötig.

## Audio-Hilfsprozesse

Chrome und Teams geben Ton über Hilfsprozesse mit eigener PID aus (`com.google.Chrome.helper`, `com.microsoft.teams2.modulehost`). Ein Tap nur auf die Haupt-PID nimmt dann Stille auf. `MeetingAudioMatcher` sammelt deshalb aus der Core-Audio-Prozessliste alle Prozesse mit derselben Bundle-ID oder einer Unter-ID ein, bei Zoom, Teams und Webex die ganze App-Familie. PIDs ohne Audio-Objekt überspringt der Tap.

## Was noch fehlt

- Hotkey für Start und Stopp
- Die AX-Beschriftungen von Teams und Zoom in einem echten Meeting prüfen und die Marker in `SpeakerLabelParser` nachziehen
- Die eigene Stimme aus der Mikrofonspur ins eigene Profil einlernen
- Startet eine Konferenz-App erst während der Aufnahme einen neuen Audio-Prozess, fehlt dieser im Tap. Der Tap wird nur beim Start zusammengestellt.
- Die Zusammenfassung hängt am Ollama-Modell. `phi4-mini` reicht für kurze Meetings; für längere ist ein größeres Modell sinnvoll.
