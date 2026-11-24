# Sunset

Schlanke macOS-Menüleisten-App für die Bluetooth-Lampe **SSL-253FEB**. Ab Version 1.4 gibt es kein Dock-Symbol, kein App-Menü und kein Fenster mehr – Sunset lebt ausschließlich als Sonnenuntergang-Symbol in der Menüleiste.

## Starten und bedienen

Die installierte App befindet sich unter **Programme → Sunset** (`/Applications/Sunset.app`). Nach dem Start erscheint nur das Symbol in der Menüleiste. Beim ersten Start gegebenenfalls Bluetooth erlauben. Wird Sunset erneut aus Programme geöffnet, während es schon läuft, klappt das Menü auf.

Ein Klick auf das Symbol öffnet das Menü mit allen Bedienelementen:

- **Kopf:** App-Version, Gerätename und Verbindungsstatus (z. B. „Verbunden“, „Verbinde mit SSL-253FEB …“). Ist die Lampe nicht verbunden, erscheint das Symbol abgeblendet und die Lichtsteuerung ist ausgegraut.
- **Einschalten / Ausschalten** und ein **Helligkeitsregler** von 1–100 %. Der Wert wird beim Ziehen kurz entprellt (0,15 s) und dann gesendet.
- **Sechs Farbpresets** mit Farbpunkt: Sunset, Gold, Rosé, Violett, Ozean, Warmweiß. Die aktive Auswahl ist abgehakt, sobald der Lampenzustand bekannt ist.
- **Eigene Farbe …** öffnet die systemeigene macOS-Farbauswahl (wird erst bei Bedarf geladen).
- **Sanfte Farbwechsel** (Untermenü): „7 Farben überblenden“ und „3 Farben überblenden“. Die Überblendung läuft in der Lampe selbst; der Mac hält dafür keinen Timer.
- **Erneut verbinden** und **Verbindung freigeben**. Freigeben trennt Bluetooth, ohne die Lampe auszuschalten; danach kann die iPhone-App übernehmen.
- **Sunset beenden** (⌘Q bei geöffnetem Menü) beendet die App wirklich und trennt Bluetooth. Die Lampe behält ihre aktuelle Einstellung.

Weiterhin gilt:

- Kein automatischer Systemstart. Beim Start verbindet sich Sunset, verändert aber die Beleuchtung nicht. Letzte Farbe und Helligkeit werden gespeichert. Der aktuelle Lampenzustand ist nach einem Neustart zunächst unbekannt, bis ein Befehl oder eine Zustandsmeldung vorliegt.
- Die iPhone-App muss für die Mac-Verbindung vollständig geschlossen sein. Bei Verbindungsabbruch verbindet sich Sunset automatisch erneut: nach einem einzelnen Abbruch sofort, nur bei wiederholten echten Fehlern mit wachsender Pause von höchstens acht Sekunden (seit v1.1). Eine Verbindungsanfrage zur bekannten Lampe bleibt beim Bluetooth-System angemeldet und kostet im Leerlauf nichts. Nicht gesendete Befehle werden bei einem Fehler verworfen.
- Neu in 1.4: Ist noch keine Lampe bekannt (oder hat sie eine neue Kennung) und wird sie nicht gefunden, sucht Sunset nur fünf Runden lang (etwa zwei Minuten) per Bluetooth-Scan und zeigt dann „Lampe nicht gefunden · „Erneut verbinden“ wählen“. So scannt das Funkmodul nicht endlos.
- Die Bundle-ID bleibt `local.sunsetmac`; Bluetooth-Freigabe und gespeicherte Farben bleiben bei Updates erhalten.

Die Lampensteuerung benötigt weder Internet noch Home Assistant.

## Diagnoseprotokoll

Sunset schreibt nach `/tmp/sunsetmac.log` – nur bei Verbindungsereignissen, nie periodisch. Das Protokoll wird bei jedem Start geleert und ab 256 KB gekürzt.

```sh
defaults write local.sunsetmac logLevel -string basic     # Standard: Verbindung, Status, Fehler
defaults write local.sunsetmac logLevel -string verbose   # zusätzlich jedes Bluetooth-Paket (TX/RX)
defaults write local.sunsetmac logLevel -string off       # gar nicht protokollieren
```

Einmalig per Startargument: `open -n /Applications/Sunset.app --args --log-verbose` bzw. `--log-off`.

## Ressourcenverbrauch

Gemessen am 24. November 2026 auf einem Mac mit Apple Silicon (arm64), macOS 27.2.1, Lampe verbunden, im Leerlauf ohne Bedienung. Werkzeuge: `top -stats pid,cpu,mem,idlew,power` (5-s-Intervalle; IDLEW ist ein kumulativer Zähler, ausgewertet als Differenz), CPU-Zeit-Differenz aus `ps` und `footprint`. `powermetrics` war ohne Administratorrechte nicht verfügbar.

| Zustand | CPU-Zeit im Messfenster | Ø CPU | Idle-Wakeups | Footprint (Spitze) | RSS | Threads | Mach-Ports |
|---|---|---|---|---|---|---|---|
| 1.3.0, Fenster ausgeblendet (Hintergrund), 120 s | 0,02 s | 0,008 % | 1 (0,008/s) | 39 MB (50 MB) | 15,7 MB | 5 | 310 |
| 1.3.0, Fenster geöffnet, 60 s | 0,63 s | ~1 % (Schübe bis 4,3 %) | 0 | 39 MB (50 MB) | 22,0 MB | 4 | 300 |
| **1.4.0, frisch gestartet, Menü noch nicht geöffnet, 120 s** | **0,00 s** | **0,000 %** | **0** | **14 MB (15 MB)** | 70 MB* | **3** | **194** |
| **1.4.0, nach einmaligem Öffnen des Menüs, 120 s** | **0,00 s** | **0,000 %** | **0** | **23 MB (24 MB)** | 66 MB* | **3** | **203** |

\* RSS zählt unter macOS auch geteilte, gerade geladene Systembibliotheken mit und ist bei frisch gestarteten Prozessen deshalb hoch; die 1.3.0-Instanz lief zum Messzeitpunkt bereits 16 Minuten, ihre Seiten waren teilweise ausgelagert bzw. komprimiert. Aussagekräftig für den tatsächlichen Speicherbedarf ist der Footprint: **etwa 40–64 % weniger** als bei 1.3.0. Der Energieeinfluss (`top`-Spalte POWER) liegt bei 1.4.0 im Leerlauf bei 0,0.

Was dazu beiträgt: kein Fenster und kein Layout im Speicher, Menü und Farbauswahl werden erst beim ersten Öffnen erzeugt, keine Polling-Timer (Timer laufen nur während eines Verbindungsaufbaus bzw. 0,15 s beim Ziehen des Helligkeitsreglers), begrenzter Bluetooth-Scan, Paketprotokoll nur auf Wunsch.

## Bauen

Mit den installierten Xcode-Entwicklerwerkzeugen:

```sh
zsh build.sh
```

Protokoll- und Logikprüfungen:

```sh
zsh test.sh
```

## Repository und Updates

Öffentliches Repository: [rndmgizmo/sunset-mac](https://github.com/rndmgizmo/sunset-mac). Der Hauptbranch heißt `main`. Veröffentlichte Versionen: `v1.2.0` und `v1.3.0` (GitHub-Release). Version 1.4.0 (Build 5) ist lokal gebaut und noch nicht getaggt.

Den neuesten Stand aus Git holen, prüfen, bauen und nach Programme installieren:

```sh
zsh update.sh
```

Lokale Änderungen installieren, ohne vorher von GitHub zu laden:

```sh
zsh install.sh
```

Der Installer prüft das neue App-Bundle vor dem Austausch, beendet ausschließlich die laufenden Sunset-Prozesse und sichert die vorherige Version unter `build/backups/`. Bei einem Fehler beim Austausch wird die alte Version wiederhergestellt. Die gespeicherten Farben und die Bluetooth-Freigabe verwenden weiterhin dieselbe App-ID. Der Update-Befehl verweigert einen Pull bei ungesicherten Änderungen und erlaubt ausschließlich Fast-forward-Updates auf `main`.

`zsh release.sh` erzeugt ein ZIP mit Architektur und Version im Namen sowie eine SHA-256-Prüfsumme. GitHub Actions prüft und baut Änderungen auf `main` und Pull Requests. Ein gepushter Tag im Format `v1.3.0`, passend zur Version in `Info.plist`, erstellt automatisch ein öffentliches Release mit dem App-Archiv. Tag und App-Version müssen übereinstimmen.

Die Pakete werden ad-hoc signiert. Developer-ID-Notarisierung und automatische Updates direkt innerhalb der App sind noch nicht eingerichtet.

## Protokoll und Prüfung am Gerät

Die native Implementierung verwendet CoreBluetooth und CommonCrypto. Als Protokollreferenz dienen die [iStrip+-Dokumentation](https://github.com/vakintosh/istrip_plus_HA/blob/main/docs/ble-protocol.md) und der dort dokumentierte AES-Schlüssel. Der Steuerkanal ist AC52 im Dienst AC50; der Firmware-Kanal AE01 wird nicht verwendet. Vor den Lichtbefehlen werden Benachrichtigungen aktiviert und der Gruppen-Handshake gesendet.

Am 20. Oktober 2026 mit SSL-253FEB auf diesem Mac geprüft: Geräteerkennung, Dienstermittlung, Verbindung, bestätigter Gruppen-Handshake und ein Orangeton (RGB 255/80/8 bei 40 % Helligkeit). Die sichtbare Farbänderung wurde vom Nutzer bestätigt. Die übrigen Bedienelemente sind implementiert; ein vollständiger interaktiver UI-Test steht aus. AES-Pakete wurden unabhängig mit OpenSSL verglichen.

Am 21. Oktober 2026 wurde Version 1.1 am Gerät geprüft: Startverbindung sowie zwei erzwungene Neuverbindungen, jeweils mit bestätigtem Handshake, in 0,478 / 0,468 / 0,471 Sekunden ab dem Verbindungsaufruf. Beim manuellen Neuaufbau setzte die App ohne die vorherige Acht-Sekunden-Pause fort. Der Test veränderte die Beleuchtung nicht. Diese Messungen gelten für eine erreichbare, freie Lampe; bei schwachem Empfang oder einer belegten Verbindung kann es länger dauern. Testlauf über `open -n build/Sunset.app --args --test-reconnect` bei zuvor beendeter App.

Version 1.2 wurde am selben Tag unter `/Applications/Sunset.app` installiert und von dort gestartet. Fensterlayout und verfügbare Bedienelemente wurden visuell und über die Bedienungshilfen geprüft.

Am 24. November 2026 wurde Version 1.4.0 mit `zsh install.sh` installiert (Vorversion unter `build/backups/`) und geprüft:

- Getestet: Prozess läuft als `UIElement` (`lsappinfo`), kein Dock-Symbol (Bildschirmfoto des Docks), Sonnenuntergang-Symbol in der Menüleiste, keine App-Fenster. Menü per `--test-menu` geöffnet und abfotografiert (alle Einträge, Farbpunkte, Status „Verbunden“, Bedienelemente aktiv) – das Menü schließt sich dabei nach drei Sekunden selbst. Normales Beenden (Quit-Ereignis) beendet die App wirklich und trennt Bluetooth sauber; danach Neustart. Startverbindungen in 0,34–0,91 s, jeweils ohne Lichtbefehl. `--test-reconnect`: Start plus zwei erzwungene Neuverbindungen in 0,403 / 0,650 / 0,711 s, jeweils direkt nach dem Trennen ohne Pause. Die Beleuchtung wurde bei keinem Test verändert. Haupt-Queue-Blöcke (Helligkeits-Entprellung, Bluetooth-Rückrufe) laufen auch bei geöffnetem Menü weiter (separates Testprogramm).
- Per Unit-Test geprüft: Protokoll, Wiederverbindungs-Backoff, Begrenzung des Bluetooth-Scans, Log-Stufen, Menüzustand (Haken, Titel), Dekodierung der Zustandsmeldung.
- Nicht am Gerät getestet: Klicks auf Presets, Helligkeitsregler, Farbwechsel, An/Aus und die freie Farbauswahl (würden das Licht verändern), ⌘Q-Kürzel bei geöffnetem Menü und Tastenkürzel in der Farbauswahl, Verhalten bei unerreichbarer Lampe bzw. Scan-Abbruch nach fünf Runden, Bluetooth aus/an, Abmelden/Neustart.

Diagnoselog der laufenden App: `/tmp/sunsetmac.log`. Der separate Prüfer unter `Tools/BluetoothProbe.swift` liest ausschließlich Dienste aus.
