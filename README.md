# LAN Toolkit — локальная сеть Win ⇄ Win ⇄ Linux ⇄ Android + Minecraft

Один набор файлов, который поднимает общую сеть между компьютерами и телефоном:
общая папка, видимость в сети, SSH, раздача файлов через браузер, мобильный хот-спот
и Minecraft-сервер (Java + Bedrock).

> **Ничего вводить в командную строку не нужно.** Запускай файлы двойным кликом —
> откроется меню на русском, где надо нажать цифру.

---

## Что нажимать (для новичков)

### Windows
1. Найди файл **`НАЧАТЬ-Windows.bat`** (или такой же по смыслу `START-Windows.bat`).
2. Двойной клик по нему.
3. Windows спросит разрешение (синее окно «Разрешить этому приложению вносить изменения») — нажми **Да**.
4. В открывшемся меню нажми **`1`** и Enter — сеть подготовлена. Дальше там же цифры 4/5 для Minecraft.

### Linux
1. Файлы `start-linux.sh`, `lan-linux.sh`, `НАЧАТЬ-Linux.desktop` положи в одну папку.
2. Двойной клик по **`НАЧАТЬ-Linux.desktop`** (если система спросит — «Разрешить выполнение»/«Доверять»).
3. Введи пароль администратора и нажми **`1`** в меню.

   Если двойной клик не работает: правый клик в папке → «Открыть в терминале» →
   набрать `bash start-linux.sh` (одна команда, и дальше всё по цифрам).

### Android (телефон)
1. Поставь **Termux** (только из **F-Droid**, версия из Play Market устарела).
2. Скинь папку `lan-toolkit` на телефон (или скачай через браузер).
3. В Termux набери один раз:
   ```
   cd ~/storage/downloads/lan-toolkit && bash lan-android.sh
   ```
   дальше — цифры в меню.

> На Android без root нельзя «примонтировать» папку Windows. Для файлов по SMB
> используй бесплатное приложение **Cx File Explorer** (Сеть → Новое подключение → SMB,
> адрес `smb://<IP_ПК>/LAN`). Всё остальное — через SSH и браузер, они в меню.

---

## Что в комплекте

| Файл | Для чего | Как запускать |
|---|---|---|
| `НАЧАТЬ-Windows.bat` / `START-Windows.bat` | меню для Windows | двойной клик |
| `lan-win.ps1` | «движок» Windows (можно и вручную) | `.\lan-win.ps1 setup` |
| `start-linux.sh` | меню для Linux | двойной клик / `bash start-linux.sh` |
| `НАЧАТЬ-Linux.desktop` | ярлык-двойной клик для Linux | двойной клик |
| `lan-linux.sh` | «движок» Linux | `sudo bash lan-linux.sh setup` |
| `lan-android.sh` | меню и движок Android (Termux) | `bash lan-android.sh` |
| `mcping.py` | Minecraft-пинг, скан подсети, LAN-поиск (Linux/Android) | вызывается скриптами сам |
| `README.md` | эта инструкция | — |

## Матрица связок

| Из → В | Что работает | Как |
|---|---|---|
| **Win → Win** | Проводник, SMB | `\\ПК\LAN` в проводнике |
| **Win → Linux** | SMB, SSH, HTTP | `\\IP\LAN`; `ssh user@IP`; `http://IP:8080` |
| **Linux → Win** | SMB (cifs), HTTP | меню Linux → пункт 7 |
| **Win → Android** | SSH/SCP, HTTP | `scp -P 8022 user@IP:...`; `http://IP:8080` |
| **Android → Win** | SMB через GUI, HTTP, SSH | Cx File Explorer `smb://IP/LAN`; меню Android → 4 |
| **Android → Linux** | SSH, HTTP, SMB (GUI) | `ssh -p 8022 user@IP` |

## Minecraft в этой же сети

Java и Bedrock — **разные миры**, друг друга они не видят без плагинов Geyser + Floodgate.

**Как быстро поиграть (без сервера, только Windows-хост):**
игра → `Esc` → «Открыть для сети» (Open to LAN) → друзья по IP присоединяются.
Ограничение: хост должен оставаться в игре.

**Как поднять настоящий сервер:**

| Сторона | Действие |
|---|---|
| Windows | меню → пункт **4** (спросит память в ГБ). Файл `server.jar` положить в `%PUBLIC%\LANShare\minecraft` |
| Linux | меню → пункт **4** (Java/Paper, скачается сам) или **5** (Bedrock-сервер) |
| Android | меню → пункт **6** (сервер на телефоне, для 1–2 человек; перед этим `termux-wake-lock`) |

| Версия игры | Куда вводить адрес |
|---|---|
| Java Edition | Multiplayer → Direct Connection → `<IP>:25565` |
| Bedrock (телефон, Win-Store, консоль) | Play → Servers → Add Server → `<IP>:19132` |

Грабли:
- Порт 25565 нужен **и TCP, и UDP**.
- Bedrock всегда **UDP 19132**; автопоиск LAN на телефоне ПК не видит → адрес вручную.
- Без `eula=true` в `eula.txt` сервер падает (скрипты ставят сами).
- Кросс-плей: на Paper-сервер положить `Geyser-Spigot.jar` + `Floodgate.jar` в `plugins/`.
- Телефон-сервер: без `termux-wake-lock` Termux засыпает и сервер отваливается.

## Найти запущенную игру (клиент → клиент, «Открыть для сети»)

Не сервер, а обычная сессия из игры: скрипт находит java-процесс клиента, его слушающий
порт и **делает настоящий Minecraft-пинг** — так видно мир, версию и кто сейчас в игре.

```powershell
.\lan-win.ps1 detect
```
```
  Найдено: КЛИЕНТ (игра)  PID 10528
    Инстанс : TerraFirmaGreg-Modern-0.13.10-multimc
    Версия  : 1.20.1
    ЛОКАЛЬНАЯ СЕТЬ ОТКРЫТА -> порт 55534
      Мир      : S_ker - выживание_Ваня_ноет
      Версия   : 1.20.1 (protocol 763)
      Игроки   : 2/8
      Сейчас в игре: Ivantuz_z, S_ker
      Адрес для друзей:
        192.168.1.64:55534
```

Как это работает: пинг протокола Server List Ping (`0x00` handshake → `0x00` status →
JSON с MOTD, версией и списком игроков) — поэтому «порт открыт» и «это действительно
Minecraft» не путаются. Порт у «Открыть для сети» **случайный и меняется каждый раз**,
поэтому вручную его угадывать бесполезно — `detect` достаёт его из процесса.

Аналоги:
- Linux: `sudo bash lan-linux.sh detect`
- Android (скан подсети + LAN-поиск): `bash lan-android.sh scan`
- Свой инструмент: `python3 mcping.py ping <IP> <порт>` / `scan <192.168.1>` / `listen`

Оговорка: мультикаст-объявления `224.0.2.60:4445` (по ним клиенты видят друг друга в
меню «Сетевая игра») часто режет Windows Firewall и Wi-Fi-роутеры. Прямое подключение
по `<IP>:<порт>` работает всегда, поэтому `detect` — основной способ, а не мультикаст.

## Перенос мира между машинами

Мир — это папка с `level.dat` (+ `session.lock`, `region/`, `playerdata/`). Скрипты
синхронизируют её через общую папку в обе стороны, **по принципу «новее побеждает»**
и с автоматическим бэкапом перед каждым изменением.

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

Защиты, которые важнее удобства:
- **Мир занят игрой → синхронизация запрещена.** Проверяется `session.lock` эксклюзивным
  открытием и наличие java-процесса клиента: копирование папки, открытой игрой, гарантированно
  даёт битый мир. Обход — только явный `-Force` (Windows) / `FORCE=1` (Linux).
- **Бэкап перед каждым прогоном**: `_backups/<мир>-<дата>.zip` (Windows) или `.tar.gz` (Linux).
- **Режим по умолчанию ничего не удаляет** (robocopy `/E /XO`, rsync `--update`): удаления
  не разъезжаются между машинами. Зеркалирование (`-Mirror` / `MIRROR=1`) есть, но оно удаляет
  файлы на обеих сторонах — включай осознанно.
- Windows-скрипт находит миры всех лаунчеров: Prism, MultiMC, ванильный `.minecraft`,
  а также Bedrock-миры (UWP, `levelname.txt` читается как UTF-8).

## Двусторонний обмен папками

Постоянно работающая «общая папка» между двумя машинами — файлы доезжают в обе стороны.

```powershell
.\lan-win.ps1 sync -Local "$env:USERPROFILE\Desktop\обмен" -Remote \\192.168.1.50\LAN\обмен -Watch 30
```
```bash
sudo bash lan-linux.sh sync /home/user/обмен /mnt/lan/обмен 30
bash lan-android.sh sync ~/storage/shared/Download user@192.168.1.64:/home/user/обмен 30
```

`-Watch 30` = проход каждые 30 секунд (Ctrl+C — стоп), без числа — один проход.
Логика без удалений; для полного зеркала добавь `-Mirror` (Windows) или `MIRROR=1`.

## Порты

| Порт | Протокол | Назначение |
|---|---|---|
| 445, 139 | TCP | SMB (шары, файлы) |
| 137–138 | UDP | NetBIOS-имена |
| 5357, 3702 | TCP/UDP | WSD (видимость в «Сети» Windows) |
| 5353 | UDP | mDNS (`.local`, Linux/Android) |
| 4445 | UDP | Мультикаст «Открыть для сети» (224.0.2.60) |
| 22 / 8022 | TCP | SSH (Linux / Android-Termux) |
| 8080 | TCP | HTTP-обмен файлами (меняется) |
| 25565 | TCP+UDP | Minecraft Java |
| 19132, 19133 | UDP | Minecraft Bedrock |
| 4445–65535 | TCP | LAN-порт клиента («Открыть для сети», случайный) |

## Полезные команды (для тех, кто любит терминал)

```powershell
.\lan-win.ps1 setup
.\lan-win.ps1 status
.\lan-win.ps1 http -Port 8080
.\lan-win.ps1 hotspot -On
.\lan-win.ps1 minecraft -McMem 4G -McDir D:\mc
.\lan-win.ps1 detect
.\lan-win.ps1 world -WorldMode list
.\lan-win.ps1 world -WorldMode sync -World "выживание" -Remote \\192.168.1.50\LAN\mcworlds
.\lan-win.ps1 sync -Remote \\192.168.1.50\LAN\обмен -Watch 30
.\lan-win.ps1 mount -Remote \\192.168.1.50\LAN -User lan -Drive Z
.\lan-win.ps1 remove
```

```bash
sudo bash lan-linux.sh setup            # всё сразу
sudo bash lan-linux.sh mc java          # Paper-сервер
sudo bash lan-linux.sh mc bedrock       # Bedrock-сервер
sudo bash lan-linux.sh mount //192.168.1.5/LAN lan пароль
sudo bash lan-linux.sh remove
```

```bash
bash lan-android.sh setup
bash lan-android.sh mc join
bash lan-android.sh scan                # найти серверы/LAN-игры в сети
bash lan-android.sh world list
bash lan-android.sh sync ~/storage/shared/Download user@192.168.1.64:/home/user/обмен 30
bash lan-android.sh get http://192.168.1.5:8080/file.zip
```

Свой инструмент (одна команда, без скриптов):
```bash
python3 mcping.py ping 192.168.1.64 55534     # что за сервер на порту
python3 mcping.py scan 192.168.1              # кто в сети на 25565
python3 mcping.py listen 6                    # слушать «Открыть для сети»
python3 mcping.py bedrock 192.168.1.64        # Bedrock-сервер (UDP 19132)
```

## Настройки

| Переменная / параметр | Где | По умолчанию |
|---|---|---|
| `-ShareName` / `SHARE_NAME` | win / linux | `LAN` |
| `-Path` / `SHARE_DIR` | win / linux | `C:\Users\Public\LANShare` / `/srv/lanshare` |
| `SMB_USER` / `SMB_PASS` | linux | `lan` / генерируется |
| `-Port` / `PORT` | все | `8080` |
| `-McPort` / `MC_PORT` | все | `25565` |
| `-BedrockPort` | win | `19132` |
| `-WorldMode` / `world <режим>` | все | `list` (ещё: `push`, `pull`, `sync`, `backup`) |
| `-World` | все | самый свежий мир |
| `-Watch` / `sync ... <сек>` | все | `0` (один проход) |
| `-Mirror` / `MIRROR=1` | все | выключено (режим с удалением файлов) |

## Если не видно друг друга

1. **Нет пинга** → разные подсети (`ipconfig` / `ip a`). Если Wi-Fi «гостевой», устройства изолированы: включи хот-спот (меню Windows, пункт 6) и подключи остальных к нему.
2. **Пинг есть, шара не видна** → брандмауэр: пункт 1 меню Windows открывает нужные правила.
3. **Просит пароль** → нужна реальная учётка Windows (пустой пароль по сети запрещён политикой).
4. **Windows не видит Linux** → на Linux должны быть живы `smbd`, `nmbd`, `avahi-daemon` (пункт 2 меню Linux).
5. **Android не открывает smb://** → Cx File Explorer / Material Files; либо файлы через браузер (`http` на ПК + `get` на телефоне).
6. **Windows 11 24H2 требует SMB-подпись** → на Linux-клиенте `vers=3.0` (уже в скрипте).

## Безопасность

- Шара открыта на всю локальную сеть. Не поднимай это в публичных Wi-Fi.
- `remove` (пункт 8/9 в меню) откатывает изменения.
- Пароль SMB на Linux генерируется случайно и печатается один раз — сохрани его.
