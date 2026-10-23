# Sunset

Lokale macOS-App mit eigenem Fenster, Dock-Symbol und zusätzlicher Menüleistensteuerung für die Bluetooth-Lampe **SSL-253FEB**.

## Starten und bedienen

Die installierte App befindet sich unter **Programme → Sunset** (`/Applications/Sunset.app`). Doppelklicken öffnet das Steuerfenster. Beim ersten Start gegebenenfalls Bluetooth erlauben. Alternativ kann die lokal gebaute Version unter `build/Sunset.app` gestartet werden.

Sunset besitzt ein eigenes App-Symbol und erscheint im Dock sowie zusätzlich als Sonnenuntergang-Symbol in der Menüleiste. Schließen des Fensters lässt die Bluetooth-Steuerung weiterlaufen. **⌘Q**, „Sunset beenden“ und „Beenden“ im Dock blenden Fenster und Dock-Symbol aus; die App bleibt mit ihrer Bluetooth-Verbindung in der Menüleiste aktiv. Ein erneuter Aufruf aus Programme oder „Sunset öffnen …“ in der Menüleiste öffnet das Fenster und zeigt das Dock-Symbol wieder.

Nur **„Vollständig beenden“** (in der Menüleiste oder im App-Menü, **⌥⌘Q**) beendet den Prozess und trennt Bluetooth. Beim Abmelden, Ausschalten oder Neustarten darf macOS die App weiterhin regulär beenden.

- An/Aus, sechs Farbpresets, freie Farbauswahl und Helligkeit von 1–100 %.
- Unter „Sanfte Farbwechsel“ stehen zwei langsame Überblendungen bereit.
- „Verbindung freigeben“ trennt Bluetooth, ohne die Lampe auszuschalten. Danach kann die iPhone-App wieder übernehmen. „Erneut verbinden“ verbindet den Mac wieder.
- Die App verbindet sich beim Start, verändert dabei aber die Beleuchtung nicht. Die letzte Farbe und Helligkeit werden für die nächste Auswahl gespeichert. Der aktuelle Lampenzustand ist nach einem Neustart zunächst unbekannt, bis ein Befehl oder eine Zustandsmeldung vorliegt.
- Die iPhone-App muss für die Mac-Verbindung vollständig geschlossen sein. Bei Verbindungsabbruch versucht Sunset automatisch, sich erneut zu verbinden. Nicht gesendete Befehle werden bei einem Fehler verworfen.
- Version 1.1 verbindet sich nach einem einzelnen Abbruch sofort erneut. Eine laufende Verbindungssuche zur bekannten Lampe bleibt beim Bluetooth-System angemeldet, statt alle 20 Sekunden abgebrochen zu werden. „Erneut verbinden“ behält eine gesunde Verbindung bei; ein ausdrücklich angeforderter Neuaufbau setzt direkt nach dem Trennen fort. Nur wiederholte tatsächliche Verbindungsfehler führen zu einer wachsenden Pause von höchstens acht Sekunden.

Die Lampensteuerung benötigt weder Internet noch Home Assistant. Es wird kein automatischer Systemstart eingerichtet. Auch beim vollständigen Beenden bleibt die Lampe in ihrer aktuellen Einstellung.

## Bauen

Mit den installierten Xcode-Entwicklerwerkzeugen:

```sh
zsh build.sh
```

Protokollprüfungen:

```sh
zsh test.sh
```

## Repository und Updates

Öffentliches Repository: [rndmgizmo/sunset-mac](https://github.com/rndmgizmo/sunset-mac). Der Hauptbranch heißt `main`. Die bisherige Version ist als `v1.2.0` gesichert.

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

Version 1.2 wurde am selben Tag unter `/Applications/Sunset.app` installiert und von dort gestartet. Fensterlayout und verfügbare Bedienelemente wurden visuell und über die Bedienungshilfen geprüft. Schließen mit ⌘W und erneutes Öffnen wurden bestätigt; die Bluetooth-Verbindung blieb bestehen. Das App-Bundle einschließlich Symbol und Signatur wurde geprüft. Die vorhandenen Protokoll- und Wiederverbindungstests bestehen weiterhin.

Diagnoselog der laufenden App: `/tmp/sunsetmac.log`. Der separate Prüfer unter `Tools/BluetoothProbe.swift` liest ausschließlich Dienste aus.
