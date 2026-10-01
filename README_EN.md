# LAN Toolkit — local network Windows ⇄ Linux ⇄ Android + Minecraft

[Русский](README.md) · **English** · [Deutsch](README_DE.md) · [Español](README_ES.md) · [中文](README_ZH.md)

A set of scripts for connecting computers and a phone on the same local network: a shared folder (SMB),
network visibility, SSH, file exchange via a browser, a mobile hotspot and a Minecraft server
(Java and Bedrock).

> No commands need to be typed: the files are launched by double-clicking, and all actions are selected
> by number in a Russian-language menu.

---

## Quick start

### Windows

1. Launch `НАЧАТЬ-Windows.bat` (or `START-Windows.bat`) by double-clicking.
2. Confirm the User Account Control prompt ("Allow this app to make changes") — "Yes".
3. In the menu that opens, select item **`1`** and press Enter: the network is prepared.
   Items 4 and 5 in the same menu are responsible for Minecraft.

### Linux

1. Place the files `start-linux.sh`, `lan-linux.sh` and `НАЧАТЬ-Linux.desktop` in one directory.
2. Launch `НАЧАТЬ-Linux.desktop` by double-clicking; when prompted, allow the file to be executed.
3. Enter the administrator password and select item **`1`** in the menu.

If double-clicking does not work: open the directory in a terminal and run `bash start-linux.sh`.

### Android (Termux)

1. Install Termux from **F-Droid**: the Play Market version is outdated.
2. Copy the `lan-toolkit` directory to the device (or download it via a browser).
3. In Termux, run once:

   ```
   cd ~/storage/downloads/lan-toolkit && bash lan-android.sh
   ```

   After that, select menu items.

> Mounting a Windows folder directly on Android without root is impossible. To access files
> over SMB, a third-party file manager is used, for example Cx File Explorer
> (Network → New connection → SMB, address `smb://<IP_ПК>/LAN`). The remaining capabilities
> are available via SSH and a browser — they are in the menu.

---

## Kit contents

| File | Purpose | Launch |
|---|---|---|
| `НАЧАТЬ-Windows.bat` / `START-Windows.bat` | menu for Windows | double-click |
| `lan-win.ps1` | Windows engine (also available manually) | `.\lan-win.ps1 setup` |
| `start-linux.sh` | menu for Linux | double-click / `bash start-linux.sh` |
| `НАЧАТЬ-Linux.desktop` | shortcut for double-clicking in Linux | double-click |
| `lan-linux.sh` | Linux engine | `sudo bash lan-linux.sh setup` |
| `lan-android.sh` | Android menu and engine (Termux) | `bash lan-android.sh` |
| `mcping.py` | Minecraft ping, subnet scan, LAN game discovery (Linux/Android) | called by the scripts |
| `VERSION` | current version (shown in the menu) | — |
| `MANIFEST.txt` | checksums of all files (update verification) | — |
| `README.md` | documentation | — |

## Update

The current version is shown in the menu header. If a newer one is published in the repository,
the menu displays `>>> ДОСТУПНО ОБНОВЛЕНИЕ <<<`, and the update is started by item **16** (Windows),
**17** (Linux) or **14** (Android). From the command line:

```powershell
.\lan-win.ps1 update-check     # check only
.\lan-win.ps1 update           # download, verify and install
.\lan-win.ps1 rollback         # restore the previous version from backup
.\lan-win.ps1 no-update        # disable the check at menu startup
```
```bash
sudo bash lan-linux.sh update-check
sudo bash lan-linux.sh update
sudo bash lan-linux.sh rollback
```

The update procedure — **no replacement is performed until the new one has been verified**:

1. The version is requested from the `VERSION` file in the repository.
2. Via the GitHub API the **exact commit of the `main` branch** is determined, and the files are downloaded by it.
   This way the CDN cache cannot serve a set of files at an older commit (such a case was observed).
3. `MANIFEST.txt` is downloaded and the **sha256 of each file** is compared (the checksums are computed
   without regard to line endings, so Windows and Linux produce the same result).
4. The syntax of the new scripts is checked: `ParseFile` for PowerShell, `bash -n` for `.sh`.
5. The current files are copied to `~/.lan-toolkit/backup/<версия>-<дата>/`.
   **A backup is mandatory:** if the copy could not be created, the update is cancelled.
6. Only after that are the files replaced. Any error at steps 1–4 → cancellation, the state does not change.

On Windows, files are downloaded by name, without unpacking an archive: `tar.exe` decodes Cyrillic
names (`НАЧАТЬ-Windows.bat`) as CP866 and creates unreadable names. On Linux and Android
the branch archive is used — there `tar` reads the names correctly.

**Protection boundaries.** The files and checksums come from a single source (GitHub over HTTPS),
so this protects against a broken connection, file corruption and errors in the scripts, but not against
server substitution. For a full guarantee, installation from git with commit verification is used.

Notes:

* The update check at menu startup takes about 3 seconds and does not interfere with work;
  without network access it simply outputs nothing. Disabling: `no-update` or `NOUPDATECHECK=1`.
* After updating, update the second machine as well: in "partner" mode the toolkit hashes must match,
  otherwise the second side will refuse.
* `update-manifest` rebuilds `MANIFEST.txt` — it is run after editing the scripts,
  otherwise the update on other machines will fail on a checksum mismatch.

## Link matrix

| From → To | What works | How |
|---|---|---|
| **Win → Win** | Explorer, SMB | `\\ПК\LAN` in Explorer |
| **Win → Linux** | SMB, SSH, HTTP | `\\IP\LAN`; `ssh user@IP`; `http://IP:8080` |
| **Linux → Win** | SMB (cifs), HTTP | Linux menu → item 7 |
| **Win → Android** | SSH/SCP, HTTP | `scp -P 8022 user@IP:...`; `http://IP:8080` |
| **Android → Win** | SMB via GUI, HTTP, SSH | Cx File Explorer `smb://IP/LAN`; Android menu → 4 |
| **Android → Linux** | SSH, HTTP, SMB (GUI) | `ssh -p 8022 user@IP` |

## Minecraft on the same network

Java and Bedrock are **different worlds**: without the Geyser + Floodgate plugins they do not see each other.

**Serverless option (host — Windows).** In the game: `Esc` → "Open to LAN". The other
participants connect by the host's IP. Limitation: the host must remain in the game.

**Full-fledged server:**

| Side | Action |
|---|---|
| Windows | menu → item **4** (asks for the amount of memory in GB). The file `server.jar` is placed in `%PUBLIC%\LANShare\minecraft` |
| Linux | menu → item **4** (Java/Paper, downloaded automatically) or **5** (Bedrock server) |
| Android | menu → item **6** (server on the phone, for 1–2 people; `termux-wake-lock` beforehand) |

| Game version | Where to enter the address |
|---|---|
| Java Edition | Multiplayer → Direct Connection → `<IP>:25565` |
| Bedrock (phone, Win-Store, console) | Play → Servers → Add Server → `<IP>:19132` |

Features:

- Port 25565 is required **both over TCP and over UDP**.
- Bedrock is always **UDP 19132**; the phone's LAN auto-discovery does not see the PC, the address is entered manually.
- Without `eula=true` in `eula.txt` the server terminates with an error (the scripts create the file themselves).
- Cross-play: `Geyser-Spigot.jar` and `Floodgate.jar` are placed in `plugins/` on the Paper server.
- Phone server: without `termux-wake-lock` Termux falls asleep and the server disconnects.

## Finding a running game ("Open to LAN")

This is not about a server, but about an ordinary game session: the script finds the client's java
process and its listening port, after which it performs a real Minecraft ping — this is how the world,
version and player list are determined.

```powershell
.\lan-win.ps1 detect
```

Example output (values anonymized). Note that the toolkit's menu and output are in Russian.

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

How it works: the Server List Ping protocol ping is used (`0x00` handshake → `0x00` status →
JSON with MOTD, version and player list), so "the port is open" and "this really is Minecraft"
are not confused. The port for "Open to LAN" is **random and changes every time**; selecting it
manually is pointless — `detect` extracts it from the process.

Analogues:

- Linux: `sudo bash lan-linux.sh detect`
- Android (subnet scan + LAN game discovery): `bash lan-android.sh scan`
- Standalone utility: `python3 mcping.py ping <IP> <порт>` / `scan <192.168.1>` / `listen`

Note: multicast announcements at `224.0.2.60:4445` (through which clients see each other in the
"Network game" menu) are often blocked by the Windows firewall and Wi-Fi routers. A direct connection
via `<IP>:<порт>` always works, so `detect` is the primary method, not multicast.

## Transferring a world between machines

A world is a directory with `level.dat` (as well as `session.lock`, `region/`, `playerdata/`). The scripts
synchronize it through the shared folder in both directions, **on the "newer wins" principle**
and with an automatic backup before every change.

```powershell
.\lan-win.ps1 world -WorldMode list                  # какие миры есть и где
.\lan-win.ps1 world -WorldMode push  -World "имя" -Remote \\192.168.1.50\LAN\mcworlds
.\lan-win.ps1 world -WorldMode pull  -World "имя" -Remote \\192.168.1.50\LAN\mcworlds
.\lan-win.ps1 world -WorldMode sync  -World "имя" -Remote \\192.168.1.50\LAN\mcworlds
```
```bash
sudo bash lan-linux.sh world list
sudo bash lan-linux.sh world sync "имя мира" /mnt/lan/mcworlds
```

Safeguards:

- **The world is busy with the game → synchronization is forbidden.** `session.lock` is checked by exclusive
  opening; additionally, the presence of the client's java process is checked: copying a directory
  opened by the game is guaranteed to produce a corrupted world. Bypass — only an explicit `-Force`
  (Windows) / `FORCE=1` (Linux).
- **Backup before every run**: `_backups/<мир>-<дата>.zip` (Windows) or `.tar.gz` (Linux).
- **By default the mode deletes nothing** (robocopy `/E /XO`, rsync `--update`): deletions
  are not propagated between machines. Mirroring (`-Mirror` / `MIRROR=1`) exists,
  but deletes files on both sides.
- The Windows script finds the worlds of all launchers: Prism, MultiMC, vanilla `.minecraft`,
  as well as Bedrock worlds (UWP, `levelname.txt` is read as UTF-8).

## Two-way folder exchange

A permanently running shared folder between two machines: files arrive in both directions.

```powershell
.\lan-win.ps1 sync -Local "$env:USERPROFILE\Desktop\обмен" -Remote \\192.168.1.50\LAN\обмен -Watch 30
```
```bash
sudo bash lan-linux.sh sync /home/user/обмен /mnt/lan/обмен 30
bash lan-android.sh sync ~/storage/shared/Download user@192.168.1.20:/home/user/обмен 30
```

`-Watch 30` — a pass every 30 seconds (stop — Ctrl+C); without a number a single pass is performed.
Logic without deletions; for a full mirror, `-Mirror` (Windows) or `MIRROR=1` is added.

## "Partner" mode: remote connection to the second machine

Remote synchronization mode: **the initiator connects to the second machine over SSH and sends
it a request to perform its half of the synchronization.** The same toolkit must be present on both
machines (verified by hash).

How it works: the initiator starts `peer-serve` on the second machine over SSH, passes the request via stdin,
and the second side **decides for itself whether to accept it**, and performs the work with its own means —
its own share, its own `robocopy`/`rsync`.

### Setup (4 steps)

```powershell
# 1) на ОБЕИХ машинах установить тулкит, у себя создать ключ
.\lan-win.ps1 peer-keygen

# 2) указать партнёра и залить к нему скрипты
.\lan-win.ps1 peer-add -Peer pc2 -PeerHost 192.168.1.50 -PeerUser user -PeerPlatform win
.\lan-win.ps1 peer-bootstrap -Peer pc2

# 3) добавить свой публичный ключ на вторую машину (см. вывод peer-keygen)
#    Windows: C:\Users\<user>\.ssh\authorized_keys
#    Linux/Android: ssh-copy-id -i ~/.lan-toolkit/keys/id_ed25519.pub user@IP

# 4) НА ВТОРОЙ МАШИНЕ вручную взвести приём:
#    bash lan-linux.sh peer-arm -t мойКод123 -m 30
```

Check: `.\lan-win.ps1 peer-test -Peer pc2`
Synchronization: `.\lan-win.ps1 peer-sync -Peer pc2 -Local "$env:USERPROFILE\Desktop\обмен" -RemoteDir /srv/lanshare/обмен -Watch 30`

Without step 4 (arming), the second machine **will refuse** — this is the main protection mechanism.
Arming the reception remotely is impossible: the `peer-arm`/`peer-disarm` commands are not on the whitelist.

### Protection mechanisms

| Protection | How it works |
|---|---|
| SSH access | An already authorized key-based login is required. The toolkit key is added by a human on that machine. |
| Manual arming | Until `peer-arm` is executed on the second machine, any request receives `denied`. |
| Token | SHA-256 is compared; it is never stored in plaintext. Minimum 6 characters. |
| Lifetime | Maximum 240 minutes, after which the reception closes automatically. |
| One-shot | `--once` — the arming is consumed after the very first request (it is cleared **before** the work, so that a broken connection does not leave access). |
| Binding to the initiator | `--fp "user@ПК"` — accept from only one specific machine. |
| Whitelist | Only `ping, hash, status, detect, world, sync` are allowed. Arbitrary code is forbidden. |
| Script verification | The toolkit hash must match on both machines. Otherwise refusal (bypass: `-AllowVersionDrift` / `ALLOW_DRIFT=1`). |
| Log | `~/.lan-toolkit/audit.log` — both successful requests and refusals with the reason. |
| Revocation | `peer-disarm` closes the reception immediately; `peer-forget` removes the partner. |

State (keys, partner list, arming, log) is stored **outside** the toolkit —
in `~/.lan-toolkit`, so it ends up neither in git nor in copies of the exchange folder.

### Mode limitations

- It does not arm the second machine on its own and does not request a password — only an already
  authorized SSH access is used.
- It does not execute arbitrary commands — only actions from the whitelist.
- It does not register itself for autostart and does not keep a permanent channel: one SSH connection per request.
- It does not store passwords: only the toolkit's SSH key.

### Examples for Linux and Android

```bash
sudo bash lan-linux.sh peer-keygen
sudo bash lan-linux.sh peer-add pc2 192.168.1.50 user 22 win
sudo bash lan-linux.sh peer-bootstrap pc2
sudo bash lan-linux.sh peer-arm -t мойКод123 -m 30        # приём на этой машине
sudo bash lan-linux.sh peer-test pc2
sudo bash lan-linux.sh peer-sync pc2 /srv/lanshare/обмен /srv/lanshare/обмен 30
bash lan-android.sh peer-arm -t мойКод123 -m 30           # телефон как цель
bash lan-android.sh peer-sync pc  ~/storage/shared/lan  ~/lan
```

## Ports

| Port | Protocol | Purpose |
|---|---|---|
| 445, 139 | TCP | SMB (shares, files) |
| 137–138 | UDP | NetBIOS names |
| 5357, 3702 | TCP/UDP | WSD (visibility in Windows "Network") |
| 5353 | UDP | mDNS (`.local`, Linux/Android) |
| 4445 | UDP | "Open to LAN" multicast (224.0.2.60) |
| 22 / 8022 | TCP | SSH (Linux / Android-Termux) |
| 22 | TCP | SSH server on Windows (needed for "partner" mode) |
| 8080 | TCP | HTTP file exchange (changes) |
| 25565 | TCP+UDP | Minecraft Java |
| 19132, 19133 | UDP | Minecraft Bedrock |
| 4445–65535 | TCP | Client LAN port ("Open to LAN", random) |

## Commands

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
sudo bash lan-linux.sh setup            # всё сразу
sudo bash lan-linux.sh mc java          # Paper-сервер
sudo bash lan-linux.sh mc bedrock       # Bedrock-сервер
sudo bash lan-linux.sh mount //192.168.1.50/LAN lan пароль
sudo bash lan-linux.sh remove
```

```bash
bash lan-android.sh setup
bash lan-android.sh mc join
bash lan-android.sh scan                # найти серверы/LAN-игры в сети
bash lan-android.sh world list
bash lan-android.sh sync ~/storage/shared/Download user@192.168.1.20:/home/user/обмен 30
bash lan-android.sh get http://192.168.1.50:8080/file.zip
```

Standalone utility (a single command, without the scripts):

```bash
python3 mcping.py ping 192.168.1.20 55534     # что за сервер на порту
python3 mcping.py scan 192.168.1              # кто в сети на 25565
python3 mcping.py listen 6                    # слушать «Открыть для сети»
python3 mcping.py bedrock 192.168.1.20        # Bedrock-сервер (UDP 19132)
```

## Parameters

| Variable / parameter | Where | Default |
|---|---|---|
| `-ShareName` / `SHARE_NAME` | win / linux | `LAN` |
| `-Path` / `SHARE_DIR` | win / linux | `C:\Users\Public\LANShare` / `/srv/lanshare` |
| `SMB_USER` / `SMB_PASS` | linux | `lan` / generated |
| `-Port` / `PORT` | all | `8080` |
| `-McPort` / `MC_PORT` | all | `25565` |
| `-BedrockPort` | win | `19132` |
| `-WorldMode` / `world <режим>` | all | `list` (also: `push`, `pull`, `sync`, `backup`) |
| `-World` | all | the most recent world |
| `-Watch` / `sync ... <сек>` | all | `0` (a single pass) |
| `-Mirror` / `MIRROR=1` | all | off (mode with file deletion) |

## Diagnostics

1. **No ping** → different subnets (`ipconfig` / `ip a`). If the Wi-Fi is a guest network, the devices
   are isolated: enable the hotspot (Windows menu, item 6) and connect the others to it.
2. **Ping works, the share is not visible** → firewall: item 1 of the Windows menu opens the required rules.
3. **A password is requested** → a real Windows account is needed (an empty password over the network
   is forbidden by policy).
4. **Windows does not see Linux** → on Linux `smbd`, `nmbd`, `avahi-daemon` must be running
   (item 2 of the Linux menu).
5. **Android does not open `smb://`** → Cx File Explorer / Material Files; or files via the
   browser (`http` on the PC + `get` on the phone).
6. **Windows 11 24H2 requires SMB signing** → on the Linux client `vers=3.0` (already in the script).

## Security

- The share is available to the entire local network; it is not recommended to use it on public Wi-Fi.
- `remove` (item 8/9 in the menu) rolls back the changes made.
- The SMB password on Linux is generated randomly and displayed once — save it.
