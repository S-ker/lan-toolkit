# LAN Toolkit — lokales Netzwerk Windows ⇄ Linux ⇄ Android + Minecraft

[Русский](README.md) · [English](README_EN.md) · **Deutsch** · [Español](README_ES.md) · [中文](README_ZH.md)

Eine Sammlung von Skripten, die Computer und Telefon in einem lokalen Netzwerk verbindet:
gemeinsamer Ordner (SMB), Sichtbarkeit im Netzwerk, SSH, Dateiaustausch über den Browser,
mobiler Hotspot und Minecraft-Server (Java und Bedrock).

> Es müssen keine Befehle eingegeben werden: Die Dateien werden per Doppelklick gestartet,
> alle Aktionen lassen sich über Zahlen in einem russischsprachigen Menü auswählen.

---

## Neues in Version 1.6

- **Verschachteltes Menü.** Die Hauptpunkte (Netzwerk, Adresse, Freigabe, Verbinden mit einem fremden
  Ordner, Hotspot) stehen oben; Minecraft, Dateien/Welten, SSH-Partner, Aktualisierung und Dienst
  befinden sich in eigenen Abschnitten. Alle Aktionen laufen **im selben Fenster** — ohne zusätzliche
  Fenster und ohne erneutes „Eingabetaste drücken" nach jeder Aktion.
- **Fenster schließen sich nicht mehr zu schnell.** Informationen (IP, Status) bleiben bis zum
  Drücken der Eingabetaste sichtbar; in der Kommandozeile ist das der Schalter `-Pause`.
- **SSH-Partner wird automatisch eingerichtet.** „SSH-Partner → 1" erstellt den Schlüssel, installiert
  ihn auf dem zweiten Gerät (fragt einmal nach dem Passwort), lädt die Skripte hoch, aktiviert den
  Empfang und prüft die Verbindung. Früher geschah das manuell.
- **Welten-Transfer mit automatischer Auswahl.** „Minecraft → Welt übertragen" zeigt gefundene Welten
  und bietet an, die Welt sowie das Ziel (eigener Ordner oder `\\IP\LAN`) zu wählen.
- **Netzwerk wird gesichert und wiederhergestellt.** `setup` erstellt einen Snapshot der
  Netzwerkkonfiguration (Profile, Dienste, Freigaben), `remove` stellt sie wieder her.
- **Minecraft-Server lädt sich selbst.** Fehlt `server.jar`, bietet das Menü an, Vanilla / Paper /
  Fabric herunterzuladen (einstellbar über `-ServerType`).
- **Automatische Protokollierung.** Alle Aktionen werden in `~/.lan-toolkit/lan.log` geschrieben;
  das Protokoll liegt im Abschnitt „Dienst".
- **Funktioniert als DSH-Plugin.** In `dsh-plugin/` gibt es ein fertiges Host-Plugin mit
  `lan_toolkit_*`-Werkzeugen und dem `lan-toolkit`-Agenten-Skill.

---

## Schnellstart

### Windows

1. Starten Sie `НАЧАТЬ-Windows.bat` (oder `START-Windows.bat`) per Doppelklick.
2. Bestätigen Sie die Abfrage der Benutzerkontensteuerung („Dieser App erlauben, Änderungen vorzunehmen") mit „Ja".
3. Wählen Sie im geöffneten Menü den Punkt **`1`** und drücken Sie die Eingabetaste: das Netzwerk ist vorbereitet.
   Minecraft ist der Abschnitt **`6`** (Server, Freundesadresse, Welten-Transfer).

### Linux

1. Legen Sie die Dateien `start-linux.sh`, `lan-linux.sh` und `НАЧАТЬ-Linux.desktop` in ein Verzeichnis.
2. Starten Sie `НАЧАТЬ-Linux.desktop` per Doppelklick; erlauben Sie auf Nachfrage die Ausführung der Datei.
3. Geben Sie das Administratorkennwort ein und wählen Sie im Menü den Punkt **`1`**.

Falls der Doppelklick nicht funktioniert: Öffnen Sie das Verzeichnis im Terminal und führen Sie `bash start-linux.sh` aus.

### Android (Termux)

1. Installieren Sie Termux aus **F-Droid**: Die Version aus dem Play Store ist veraltet.
2. Kopieren Sie das Verzeichnis `lan-toolkit` auf das Gerät (oder laden Sie es über den Browser herunter).
3. Führen Sie in Termux einmalig aus:

   ```
   cd ~/storage/downloads/lan-toolkit && bash lan-android.sh
   ```

   Danach erfolgt die Auswahl über die Menüpunkte.

> Ein direktes Einbinden eines Windows-Ordners ist auf Android ohne Root nicht möglich. Für den
> Dateizugriff über SMB wird ein externer Dateimanager verwendet, beispielsweise Cx File Explorer
> (Netzwerk → Neue Verbindung → SMB, Adresse `smb://<IP_des_PC>/LAN`). Alle übrigen Möglichkeiten
> stehen über SSH und den Browser zur Verfügung — sie sind im Menü enthalten.

---

## Lieferumfang

| Datei | Zweck | Start |
|---|---|---|
| `НАЧАТЬ-Windows.bat` / `START-Windows.bat` | Menü für Windows | Doppelklick |
| `lan-win.ps1` | Engine für Windows (auch manuell nutzbar) | `.\lan-win.ps1 setup` |
| `start-linux.sh` | Menü für Linux | Doppelklick / `bash start-linux.sh` |
| `НАЧАТЬ-Linux.desktop` | Verknüpfung für den Doppelklick unter Linux | Doppelklick |
| `lan-linux.sh` | Engine für Linux | `sudo bash lan-linux.sh setup` |
| `lan-android.sh` | Menü und Engine für Android (Termux) | `bash lan-android.sh` |
| `mcping.py` | Minecraft-Ping, Subnetz-Scan, LAN-Spielsuche (Linux/Android) | wird von den Skripten aufgerufen |
| `VERSION` | aktuelle Version (wird im Menü angezeigt) | — |
| `MANIFEST.txt` | Prüfsummen aller Dateien (Prüfung der Aktualisierung) | — |
| `README.md` | Dokumentation | — |

## Aktualisierung

Die aktuelle Version wird in der Kopfzeile des Menüs angezeigt. Ist im Repository eine neuere
Version veröffentlicht, gibt das Menü `>>> ДОСТУПНО ОБНОВЛЕНИЕ <<<` aus; die Aktualisierung wird
über Abschnitt **9 → 1** (Windows), **17** (Linux) oder **14** (Android) gestartet. Über die Kommandozeile:

```powershell
.\lan-win.ps1 update-check     # nur prüfen
.\lan-win.ps1 update           # herunterladen, prüfen und installieren
.\lan-win.ps1 rollback         # vorherige Version aus dem Backup zurückholen
.\lan-win.ps1 no-update        # Prüfung beim Start des Menüs deaktivieren
```
```bash
sudo bash lan-linux.sh update-check
sudo bash lan-linux.sh update
sudo bash lan-linux.sh rollback
```

Ablauf der Aktualisierung — **es wird nichts ersetzt, solange das Neue nicht geprüft ist**:

1. Die Version wird aus der Datei `VERSION` im Repository abgefragt.
2. Über die GitHub-API wird der **genaue Commit des Branches `main`** ermittelt; die Dateien werden
   anhand dieses Commits geladen. So kann der CDN-Cache keinen Satz Dateien von einem älteren
   Commit liefern (ein solcher Fall wurde beobachtet).
3. `MANIFEST.txt` wird geladen und die **sha256 jeder Datei** verglichen (die Summen werden ohne
   Berücksichtigung der Zeilenumbrüche berechnet, daher liefern Windows und Linux dasselbe Ergebnis).
4. Die Syntax der neuen Skripte wird geprüft: `ParseFile` für PowerShell, `bash -n` für `.sh`.
5. Die aktuellen Dateien werden nach `~/.lan-toolkit/backup/<Version>-<Datum>/` kopiert.
   **Das Backup ist verpflichtend:** Konnte die Kopie nicht erstellt werden, wird die Aktualisierung abgebrochen.
6. Erst danach werden die Dateien ersetzt. Jeder Fehler in den Schritten 1–4 führt zum Abbruch,
   der Zustand bleibt unverändert.

Unter Windows werden die Dateien einzeln geladen, ohne das Archiv zu entpacken: `tar.exe` dekodiert
kyrillische Namen (`НАЧАТЬ-Windows.bat`) als CP866 und erzeugt unlesbare Namen. Unter Linux und
Android wird das Branch-Archiv verwendet — dort liest `tar` die Namen korrekt.

**Grenzen des Schutzes.** Dateien und Prüfsummen stammen aus einer einzigen Quelle (GitHub über HTTPS).
Das schützt gegen Verbindungsabbrüche, beschädigte Dateien und Fehler in den Skripten, jedoch nicht
gegen einen ausgetauschten Server. Für eine vollständige Absicherung wird die Installation aus git
mit Prüfung der Commits verwendet.

Hinweise:

* Die Prüfung auf Aktualisierungen beim Start des Menüs dauert etwa 3 Sekunden und behindert die
  Arbeit nicht; ohne Netzzugang gibt sie einfach nichts aus. Abschalten: `no-update` oder `NOUPDATECHECK=1`.
* Nach einer Aktualisierung aktualisieren Sie auch die zweite Maschine: Im Partner-Modus müssen die
  Hashes der Toolkits übereinstimmen, sonst lehnt die Gegenseite ab.
* `update-manifest` erzeugt `MANIFEST.txt` neu — auszuführen nach Änderungen an den Skripten,
  andernfalls scheitert die Aktualisierung auf anderen Maschinen an abweichenden Summen.

## Verbindungsmatrix

| Von → Nach | Was funktioniert | Wie |
|---|---|---|
| **Win → Win** | Explorer, SMB | `\\PC\LAN` im Explorer |
| **Win → Linux** | SMB, SSH, HTTP | `\\IP\LAN`; `ssh user@IP`; `http://IP:8080` |
| **Linux → Win** | SMB (cifs), HTTP | Linux-Menü → Punkt 7 |
| **Win → Android** | SSH/SCP, HTTP | `scp -P 8022 user@IP:...`; `http://IP:8080` |
| **Android → Win** | SMB über GUI, HTTP, SSH | Cx File Explorer `smb://IP/LAN`; Android-Menü → 4 |
| **Android → Linux** | SSH, HTTP, SMB (GUI) | `ssh -p 8022 user@IP` |

## Minecraft im selben Netzwerk

Java und Bedrock sind **unterschiedliche Welten**: Ohne die Plugins Geyser + Floodgate sehen sie
sich gegenseitig nicht.

**Variante ohne Server (Host — Windows).** Im Spiel: `Esc` → „Für LAN öffnen". Die übrigen
Teilnehmer verbinden sich über die IP des Hosts. Einschränkung: Der Host muss im Spiel bleiben.

**Vollwertiger Server:**

| Seite | Aktion |
|---|---|
| Windows | Menü → **6** → **1** (fragt den Arbeitsspeicher in GB ab; fehlt `server.jar`, wird der Download von Vanilla/Paper/Fabric angeboten). Die Datei `server.jar` wird in `%PUBLIC%\LANShare\minecraft` gelegt |
| Linux | Menü → Punkt **4** (Java/Paper, wird automatisch geladen) oder **5** (Bedrock-Server) |
| Android | Menü → Punkt **6** (Server auf dem Telefon, für 1–2 Personen; vorher `termux-wake-lock`) |

| Spielversion | Wohin die Adresse eingegeben wird |
|---|---|
| Java Edition | Multiplayer → Direct Connection → `<IP>:25565` |
| Bedrock (Telefon, Win-Store, Konsole) | Play → Servers → Add Server → `<IP>:19132` |

Besonderheiten:

- Port 25565 wird **sowohl über TCP als auch über UDP** benötigt.
- Bedrock verwendet immer **UDP 19132**; die LAN-Autoerkennung findet den PC am Telefon nicht,
  die Adresse wird manuell eingegeben.
- Ohne `eula=true` in `eula.txt` bricht der Server mit einem Fehler ab (die Skripte legen die Datei selbst an).
- Cross-Play: Auf dem Paper-Server werden `Geyser-Spigot.jar` und `Floodgate.jar` in `plugins/` abgelegt.
- Server auf dem Telefon: Ohne `termux-wake-lock` schläft Termux ein und der Server trennt die Verbindung.

## Suche nach einer laufenden Spielsitzung („Für LAN öffnen")

Es geht nicht um einen Server, sondern um eine gewöhnliche Spielsitzung: Das Skript findet den
java-Prozess des Clients und dessen lauschenden Port und führt anschließend einen echten
Minecraft-Ping aus — so werden Welt, Version und Spielerliste ermittelt.

```powershell
.\lan-win.ps1 detect
```

Beispielausgabe (Werte anonymisiert). Hinweis: Menü und Ausgabe des Toolkits sind russisch.

```
  Найдено: КЛИЕНТ (игра)  PID 10000
    Инстанс : <название сборки> (MultiMC)
    Версия  : 1.20.1
    ЛОКАЛЬНАЯ СЕТЬ ОТКРЫТА -> порт 55534
      Мир      : player1 - <название мира>
      Версия   : 1.20.1 (protocol 763)
      Игроки   : 2/8
      Сейчас в игре: player1, player2
      Адрес для друзей:
        192.168.1.20:55534
```

Funktionsweise: Es wird der Ping des Server-List-Ping-Protokolls verwendet (`0x00` handshake →
`0x00` status → JSON mit MOTD, Version und Spielerliste), daher werden „der Port ist offen" und
„das ist tatsächlich Minecraft" nicht verwechselt. Der Port bei „Für LAN öffnen" ist **zufällig und
ändert sich bei jedem Mal**; eine manuelle Suche ist sinnlos — `detect` liest ihn aus dem Prozess aus.

Entsprechungen:

- Linux: `sudo bash lan-linux.sh detect`
- Android (Subnetz-Scan + Suche nach LAN-Spielen): `bash lan-android.sh scan`
- Eigenständiges Werkzeug: `python3 mcping.py ping <IP> <порт>` / `scan <192.168.1>` / `listen`

Hinweis: Multicast-Ankündigungen unter `224.0.2.60:4445` (über sie sehen sich die Clients im Menü
„Netzwerkspiel") werden häufig von der Windows-Firewall und von Wi-Fi-Routern blockiert. Die direkte
Verbindung über `<IP>:<Port>` funktioniert immer, daher ist `detect` der Hauptweg und nicht Multicast.

## Weltübertragung zwischen Maschinen

Eine Welt ist ein Verzeichnis mit `level.dat` (außerdem `session.lock`, `region/`, `playerdata/`).
Die Skripte synchronisieren es über den gemeinsamen Ordner in beide Richtungen, **nach dem Prinzip
„neuer gewinnt"** und mit automatischer Sicherung vor jeder Änderung.

```powershell
.\lan-win.ps1 world -WorldMode list                  # welche Welten vorhanden sind und wo
.\lan-win.ps1 world -WorldMode push  -World "имя" -Remote \\192.168.1.50\LAN\mcworlds
.\lan-win.ps1 world -WorldMode pull  -World "имя" -Remote \\192.168.1.50\LAN\mcworlds
.\lan-win.ps1 world -WorldMode sync  -World "имя" -Remote \\192.168.1.50\LAN\mcworlds
```
```bash
sudo bash lan-linux.sh world list
sudo bash lan-linux.sh world sync "имя мира" /mnt/lan/mcworlds
```

Schutzmechanismen:

- **Welt durch das Spiel belegt → Synchronisierung verboten.** `session.lock` wird durch exklusives
  Öffnen geprüft, zusätzlich wird das Vorhandensein des java-Clientprozesses geprüft: Das Kopieren
  eines vom Spiel geöffneten Verzeichnisses führt garantiert zu einer beschädigten Welt. Eine
  Umgehung ist nur über explizites `-Force` (Windows) / `FORCE=1` (Linux) möglich.
- **Sicherung vor jedem Durchlauf**: `_backups/<Welt>-<Datum>.zip` (Windows) oder `.tar.gz` (Linux).
- **Der Standardmodus löscht nichts** (robocopy `/E /XO`, rsync `--update`): Löschungen werden nicht
  zwischen den Maschinen übertragen. Die Spiegelung (`-Mirror` / `MIRROR=1`) existiert, löscht jedoch
  Dateien auf beiden Seiten.
- Das Windows-Skript findet Welten aller Launcher: Prism, MultiMC, das Vanilla-Verzeichnis
  `.minecraft` sowie Bedrock-Welten (UWP, `levelname.txt` wird als UTF-8 gelesen).

## Bidirektionaler Ordnerabgleich

Ein dauerhaft arbeitender gemeinsamer Ordner zwischen zwei Maschinen: Dateien gelangen in beide Richtungen.

```powershell
.\lan-win.ps1 sync -Local "$env:USERPROFILE\Desktop\обмен" -Remote \\192.168.1.50\LAN\обмен -Watch 30
```
```bash
sudo bash lan-linux.sh sync /home/user/обмен /mnt/lan/обмен 30
bash lan-android.sh sync ~/storage/shared/Download user@192.168.1.20:/home/user/обмен 30
```

`-Watch 30` — ein Durchlauf alle 30 Sekunden (Abbruch mit Ctrl+C); ohne Zahl wird ein einzelner
Durchlauf ausgeführt. Die Logik löscht nichts; für eine vollständige Spiegelung werden `-Mirror`
(Windows) oder `MIRROR=1` ergänzt.

## Partner-Modus: entfernte Verbindung zur zweiten Maschine

Modus der entfernten Synchronisierung: **Der Initiator verbindet sich per SSH mit der zweiten
Maschine und übergibt ihr eine Anfrage zur Ausführung ihrer Hälfte der Synchronisierung.** Auf
beiden Maschinen muss dasselbe Toolkit liegen (wird per Hash geprüft).

Ablauf: Der Initiator startet per SSH auf der zweiten Maschine `peer-serve`, übergibt die Anfrage
an stdin, und die Gegenseite **entscheidet selbst, ob sie sie annimmt**, und führt die Arbeit mit
eigenen Mitteln aus — eigene Freigabe, eigenes `robocopy`/`rsync`.

### Einrichtung (4 Schritte)

```powershell
# 1) auf BEIDEN Maschinen das Toolkit installieren, lokal einen Schlüssel erzeugen
.\lan-win.ps1 peer-keygen

# 2) Partner eintragen und die Skripte dorthin übertragen
.\lan-win.ps1 peer-add -Peer pc2 -PeerHost 192.168.1.50 -PeerUser user -PeerPlatform win
.\lan-win.ps1 peer-bootstrap -Peer pc2

# 3) den eigenen öffentlichen Schlüssel auf die zweite Maschine übertragen (siehe Ausgabe von peer-keygen)
#    Windows: C:\Users\<user>\.ssh\authorized_keys
#    Linux/Android: ssh-copy-id -i ~/.lan-toolkit/keys/id_ed25519.pub user@IP

# 4) AUF DER ZWEITEN MASCHINE die Annahme manuell scharfschalten:
#    bash lan-linux.sh peer-arm -t мойКод123 -m 30
```

Prüfung: `.\lan-win.ps1 peer-test -Peer pc2`
Synchronisierung: `.\lan-win.ps1 peer-sync -Peer pc2 -Local "$env:USERPROFILE\Desktop\обмен" -RemoteDir /srv/lanshare/обмен -Watch 30`

Ohne Schritt 4 (das Scharfschalten) **lehnt** die zweite Maschine ab — das ist der zentrale
Schutzmechanismus. Ein Scharfschalten aus der Ferne ist nicht möglich: Die Befehle
`peer-arm`/`peer-disarm` stehen nicht auf der Positivliste.

### Schutzmechanismen

| Schutz | Funktionsweise |
|---|---|
| SSH-Zugang | Ein bereits erlaubter Login per Schlüssel ist erforderlich. Den Toolkit-Schlüssel fügt eine Person auf jener Maschine hinzu. |
| Manuelles Scharfschalten | Solange auf der zweiten Maschine kein `peer-arm` ausgeführt wurde, erhält jede Anfrage `denied`. |
| Token | Es wird SHA-256 verglichen; im Klartext wird es nirgends gespeichert. Mindestens 6 Zeichen. |
| Frist | Höchstens 240 Minuten, danach schließt die Annahme automatisch. |
| Einmaligkeit | `--once` — das Scharfschalten erlischt nach der ersten Anfrage (es wird **vor** der Arbeit beendet, damit ein Verbindungsabbruch keinen Zugang hinterlässt). |
| Bindung an den Initiator | `--fp "user@PC"` — nur von einer bestimmten Maschine annehmen. |
| Positivliste | Erlaubt sind nur `ping, hash, status, detect, world, sync`. Beliebiger Code ist verboten. |
| Skriptabgleich | Der Hash des Toolkits muss auf beiden Maschinen übereinstimmen. Sonst Ablehnung (Umgehung: `-AllowVersionDrift` / `ALLOW_DRIFT=1`). |
| Protokoll | `~/.lan-toolkit/audit.log` — sowohl erfolgreiche Anfragen als auch Ablehnungen mit Grund. |
| Widerruf | `peer-disarm` schließt die Annahme sofort; `peer-forget` entfernt den Partner. |

Der Zustand (Schlüssel, Partnerliste, Scharfschaltung, Protokoll) liegt **außerhalb** des Toolkits —
in `~/.lan-toolkit`, daher gelangt er weder in git noch in Kopien des Austauschordners.

### Grenzen des Modus

- Schaltet die zweite Maschine nicht selbst scharf und fragt kein Kennwort ab — es wird
  ausschließlich ein bereits erlaubter SSH-Zugang verwendet.
- Führt keine beliebigen Befehle aus — nur Aktionen aus der Positivliste.
- Trägt sich nicht in den Autostart ein und hält keinen dauerhaften Kanal: eine SSH-Verbindung
  pro Anfrage.
- Speichert keine Kennwörter: nur den SSH-Schlüssel des Toolkits.

### Beispiele für Linux und Android

```bash
sudo bash lan-linux.sh peer-keygen
sudo bash lan-linux.sh peer-add pc2 192.168.1.50 user 22 win
sudo bash lan-linux.sh peer-bootstrap pc2
sudo bash lan-linux.sh peer-arm -t мойКод123 -m 30        # Annahme auf dieser Maschine
sudo bash lan-linux.sh peer-test pc2
sudo bash lan-linux.sh peer-sync pc2 /srv/lanshare/обмен /srv/lanshare/обмен 30
bash lan-android.sh peer-arm -t мойКод123 -m 30           # Telefon als Ziel
bash lan-android.sh peer-sync pc  ~/storage/shared/lan  ~/lan
```

## Ports

| Port | Protokoll | Zweck |
|---|---|---|
| 445, 139 | TCP | SMB (Freigaben, Dateien) |
| 137–138 | UDP | NetBIOS-Namen |
| 5357, 3702 | TCP/UDP | WSD (Sichtbarkeit im Windows-„Netzwerk") |
| 5353 | UDP | mDNS (`.local`, Linux/Android) |
| 4445 | UDP | Multicast „Für LAN öffnen" (224.0.2.60) |
| 22 / 8022 | TCP | SSH (Linux / Android-Termux) |
| 22 | TCP | SSH-Server unter Windows (für den Partner-Modus erforderlich) |
| 8080 | TCP | HTTP-Dateiaustausch (änderbar) |
| 25565 | TCP+UDP | Minecraft Java |
| 19132, 19133 | UDP | Minecraft Bedrock |
| 4445–65535 | TCP | LAN-Port des Clients („Für LAN öffnen", zufällig) |

## Befehle

```powershell
.\lan-win.ps1 setup
.\lan-win.ps1 status
.\lan-win.ps1 http -Port 8080
.\lan-win.ps1 hotspot -On
.\lan-win.ps1 minecraft -McMem 4G -McDir D:\mc
.\lan-win.ps1 detect
.\lan-win.ps1 world -WorldMode list
.\lan-win.ps1 world -WorldMode sync -World "имя" -Remote \\192.168.1.50\LAN\mcworlds
.\lan-win.ps1 sync -Remote \\192.168.1.50\LAN\обмен -Watch 30
.\lan-win.ps1 peer-keygen
.\lan-win.ps1 peer-add -Peer pc2 -PeerHost 192.168.1.50 -PeerPlatform win
.\lan-win.ps1 peer-arm -Token мойКод123 -Minutes 30 -Once
.\lan-win.ps1 peer-sync -Peer pc2 -Watch 30
.\lan-win.ps1 peer-log
.\lan-win.ps1 mount -Remote \\192.168.1.50\LAN -User lan -Drive Z
.\lan-win.ps1 remove
```

```bash
sudo bash lan-linux.sh setup            # alles auf einmal
sudo bash lan-linux.sh mc java          # Paper-Server
sudo bash lan-linux.sh mc bedrock       # Bedrock-Server
sudo bash lan-linux.sh mount //192.168.1.50/LAN lan пароль
sudo bash lan-linux.sh remove
```

```bash
bash lan-android.sh setup
bash lan-android.sh mc join
bash lan-android.sh scan                # Server/LAN-Spiele im Netzwerk finden
bash lan-android.sh world list
bash lan-android.sh sync ~/storage/shared/Download user@192.168.1.20:/home/user/обмен 30
bash lan-android.sh get http://192.168.1.50:8080/file.zip
```

Eigenständiges Werkzeug (ein Befehl, ohne Skripte):

```bash
python3 mcping.py ping 192.168.1.20 55534     # welcher Server auf dem Port läuft
python3 mcping.py scan 192.168.1              # wer im Netzwerk auf 25565 lauscht
python3 mcping.py listen 6                    # „Für LAN öffnen" mithören
python3 mcping.py bedrock 192.168.1.20        # Bedrock-Server (UDP 19132)
```

## Parameter

| Variable / Parameter | Wo | Standardwert |
|---|---|---|
| `-ShareName` / `SHARE_NAME` | win / linux | `LAN` |
| `-Path` / `SHARE_DIR` | win / linux | `C:\Users\Public\LANShare` / `/srv/lanshare` |
| `SMB_USER` / `SMB_PASS` | linux | `lan` / wird erzeugt |
| `-Port` / `PORT` | alle | `8080` |
| `-McPort` / `MC_PORT` | alle | `25565` |
| `-BedrockPort` | win | `19132` |
| `-WorldMode` / `world <Modus>` | alle | `list` (weiter: `push`, `pull`, `sync`, `backup`) |
| `-World` | alle | die neueste Welt |
| `-Watch` / `sync ... <Sek>` | alle | `0` (ein Durchlauf) |
| `-Mirror` / `MIRROR=1` | alle | deaktiviert (Modus mit Löschen von Dateien) |

## Fehlerdiagnose

1. **Kein Ping** → unterschiedliche Subnetze (`ipconfig` / `ip a`). Ist das Wi-Fi ein Gastnetz, sind
   die Geräte isoliert: Hotspot einschalten (Windows-Menü, Punkt **5**) und die übrigen Geräte damit
   verbinden.
2. **Ping vorhanden, Freigabe nicht sichtbar** → Firewall: Punkt 1 des Windows-Menüs öffnet die
   nötigen Regeln.
3. **Kennwort wird abgefragt** → ein reales Windows-Benutzerkonto ist erforderlich (ein leeres
   Kennwort ist per Richtlinie über das Netz gesperrt).
4. **Windows sieht Linux nicht** → unter Linux müssen `smbd`, `nmbd`, `avahi-daemon` laufen
   (Punkt 2 des Linux-Menüs).
5. **Android öffnet `smb://` nicht** → Cx File Explorer / Material Files; alternativ Dateien über
   den Browser (`http` am PC + `get` am Telefon).
6. **Windows 11 24H2 verlangt SMB-Signierung** → auf dem Linux-Client `vers=3.0` (bereits im Skript).

## Sicherheit

- Die Freigabe ist für das gesamte lokale Netzwerk zugänglich; von der Nutzung in öffentlichen
  Wi-Fi-Netzen wird abgeraten.
- `remove` (Abschnitt **S** → **1** im Menü) macht die vorgenommenen Änderungen rückgängig.
- Das SMB-Kennwort unter Linux wird zufällig erzeugt und einmal ausgegeben — bewahren Sie es auf.
