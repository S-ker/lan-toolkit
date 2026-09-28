#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  LAN Toolkit — сторона Android (Termux, БЕЗ root)
#  Требуется приложение Termux (F-Droid версия).
#  Запуск: bash lan-android.sh <команда>
#  Команды: setup | ssh | http | get <url> | mount <IP> <share> | status
# ============================================================

C_G="\033[32m"; C_Y="\033[33m"; C_R="\033[31m"; C_C="\033[36m"; C_0="\033[0m"
ok()   { echo -e "${C_G}[+]${C_0} $*"; }
warn() { echo -e "${C_Y}[!]${C_0} $*"; }
err()  { echo -e "${C_R}[x]${C_0} $*"; }
hdr()  { echo -e "\n${C_C}=== $* ===${C_0}"; }

STORE=~/storage/shared
PORT="${PORT:-8080}"
HTTP_DIR="${HTTP_DIR:-$STORE/Download}"

pkg_install() { pkg update -y >/dev/null 2>&1; pkg install -y "$@"; }

show_ip() {
  echo "  IPv4 (WLAN):"
  if command -v ifconfig >/dev/null 2>&1; then
    ifconfig 2>/dev/null | awk '/inet /{if ($2!="127.0.0.1") print "   -> "$2}'
  else
    ip -4 addr show 2>/dev/null | awk '/inet /{split($2,a,"/"); if (a[1]!="127.0.0.1") print "   -> "a[1]}'
  fi
}

do_setup() {
  hdr "LAN Toolkit: Android (Termux) setup"
  pkg_install openssh python nmap-ncat rsync
  termux-setup-storage 2>/dev/null && ok "доступ к памяти выдан"
  termux-wake-lock 2>/dev/null && ok "wake-lock включён (не уснёт в фоне)"
  mkdir -p ~/.ssh && chmod 700 ~/.ssh
  [ -f ~/.ssh/id_ed25519 ] || ssh-keygen -t ed25519 -N '' -f ~/.ssh/id_ed25519 >/dev/null 2>&1 && ok "SSH-ключ создан"
  do_ssh
  hdr "ГОТОВО"
  show_ip
  cat <<'EOF'

=== Что теперь можно ===
1) Android -> Windows/Linux: ssh user@<IP>            (из этого Termux)
2) Android -> Windows/Linux файлы: bash lan-android.sh mount <IP> <share>
3) Windows/Linux -> Android: подключайся к этому телефону:
      ssh -p 8022 $(whoami)@<IP_телефона>
      sftp://<IP>:8022   (в проводнике Windows: WinSCP / scp -P 8022)
4) Раздача файлов с телефона: bash lan-android.sh http
      затем с ПК: http://<IP_телефона>:8080

SMB (шары Windows) из Termux НЕ работает без root.
Для файлов по SMB ставь GUI-клиент: Cx File Explorer | Material Files | Solid Explorer
   адрес: smb://<IP_ПК>/LAN
EOF
}

do_ssh() {
  command -v sshd >/dev/null 2>&1 || pkg_install openssh
  pkill sshd 2>/dev/null
  sshd >/dev/null 2>&1 && ok "sshd запущен на порту 8022"
  passwd 2>/dev/null || warn "задай пароль командой: passwd"
}

do_http() {
  command -v python >/dev/null 2>&1 || pkg_install python
  mkdir -p "$HTTP_DIR"
  show_ip
  ok "HTTP-раздача: $HTTP_DIR"
  echo "  http://<IP_телефона>:$PORT"
  (cd "$HTTP_DIR" && python -m http.server "$PORT" --bind 0.0.0.0)
}

do_get() {
  local url="${1:-}"
  [ -n "$url" ] || { err "укажи url: bash lan-android.sh get http://192.168.1.5:8080/file.zip"; exit 1; }
  mkdir -p "$STORE/Download"
  command -v curl >/dev/null 2>&1 && curl -L --progress-bar -O --output-dir "$STORE/Download" "$url" \
    || pkg_install curl
  ok "скачано в $STORE/Download"
}

# Android -> SMB-шара Windows/Linux, монтирование в Termux через FUSE-обёртку
do_mount() {
  local ip="${1:-}" share="${2:-LAN}" user="${3:-}"
  [ -n "$ip" ] || { err "укажи IP: bash lan-android.sh mount 192.168.1.5 LAN [user]"; exit 1; }
  hdr "монтирование //$ip/$share"
  pkg_install smbnetfs 2>/dev/null || pkg_install cifs-utils 2>/dev/null
  mkdir -p ~/smb
  if command -v smbnetfs >/dev/null 2>&1; then
    mkdir -p ~/.smb
    cat > ~/.smb/smbnetfs.conf <<EOF
auth "guest" "guest"
auth "$user" "$user"
EOF
    pkill smbnetfs 2>/dev/null
    smbnetfs ~/smb && ok "готово: ls ~/smb/$ip/$share"
  else
    warn "smbnetfs недоступен в этом Termux"
    echo "  Вариант A (FUSE, без root): pkg install root-repo && pkg install smbnetfs"
    echo "  Вариант B (надёжно, GUI): Cx File Explorer -> Сеть -> Новое подключение -> SMB"
    echo "      smb://$ip/$share"
    echo "  Вариант C: используй HTTP-обмен (bash lan-android.sh http на ПК)"
  fi
}

do_status() {
  hdr "Android status"
  show_ip
  echo "  sshd: $(pgrep -x sshd >/dev/null && echo работает || echo выключен) (порт 8022)"
  echo "  user: $(whoami)"
  echo "  память: $STORE ($(df -h "$STORE" 2>/dev/null | awk 'NR==2{print $4" свободно"}'))"
}

# ---------- Minecraft ----------
MC_PORT="${MC_PORT:-25565}"
BEDROCK_PORT="${BEDROCK_PORT:-19132}"

do_mc() {
  local kind="${1:-join}"
  case "$kind" in
    join|help)
      hdr "Minecraft: подключение с телефона"
      show_ip
      cat <<EOF

  Java Edition (PojavLauncher / любой Java-клиент):
      Multiplayer -> Direct Connection -> <IP_ПК>:$MC_PORT
      (PojavLauncher: Add Server -> адрес вручную)

  Bedrock Edition (официальный клиент):
      Play -> Servers -> Add Server -> <IP_ПК>:$BEDROCK_PORT
      ВАЖНО: LAN-автопоиск на телефоне часто НЕ видит ПК,
      поэтому адрес вводится ВРУЧНУЮ.

  Если сервер у тебя на самом телефоне — сделай так:
      bash lan-android.sh server
EOF
      ;;
    server)
      hdr "Minecraft-сервер НА телефоне (Termux + Java)"
      pkg_install openjdk-17 curl unzip
      mkdir -p ~/mc && cd ~/mc || exit 1
      if [ ! -f server.jar ]; then
        ok "качаю Paper (последняя версия)..."
        local ver build url
        ver="$(curl -s https://api.papermc.io/v2/projects/paper | sed -n 's/.*"versions":\[\(.*\)\].*/\1/p' | tr -d ' "' | tr ',' '\n' | tail -1)"
        if [ -n "$ver" ]; then
          build="$(curl -s "https://api.papermc.io/v2/projects/paper/versions/$ver" | sed -n 's/.*"builds":\[\([0-9,]*\)\].*/\1/p' | tr ',' '\n' | tail -1)"
          url="https://api.papermc.io/v2/projects/paper/versions/$ver/builds/$build/downloads/paper-$ver-$build.jar"
          curl -L -o server.jar "$url" && ok "Paper $ver build $build скачан" || warn "положи server.jar вручную в ~/mc"
        fi
      fi
      [ -f server.jar ] || { err "server.jar нет — нечего запускать"; exit 1; }
      echo "eula=true" > eula.txt
      [ -f server.properties ] || cat > server.properties <<EOF
server-port=$MC_PORT
motd=Termux MC
max-players=10
view-distance=6
online-mode=true
EOF
      show_ip
      warn "Держи Termux активным (wake-lock): termux-wake-lock"
      warn "Телефон как сервер = просадки по TPS. Для игры лучше ПК/линукс-сервер."
      ok "Запуск: cd ~/mc && java -Xmx1200M -jar server.jar nogui"
      echo "  Клиенты подключаются на <IP_телефона>:$MC_PORT"
      ;;
    *) echo "usage: $0 mc [join|server]"; exit 1 ;;
  esac
}

# ---------- Поиск игр в сети (телефон как клиент) ----------
do_scan() {
  local prefix="${1:-}"
  command -v python >/dev/null 2>&1 || pkg_install python
  if [ -z "$prefix" ]; then
    local ip; ip="$(ifconfig 2>/dev/null | awk '/inet /{print $2}' | grep -v '^127' | head -1)"
    prefix="$(echo "$ip" | cut -d. -f1-3)"
  fi
  hdr "Сканирую $prefix.0/24 на Minecraft-серверы (порт 25565)"
  python "$(dirname "$0")/mcping.py" scan "$prefix" 25565
  echo ""
  hdr "Ищу LAN-игры в сети (224.0.2.60, «Открыть для сети»)"
  python "$(dirname "$0")/mcping.py" listen 6
  echo ""
  echo "  Дальше: Java -> Direct Connection / Bedrock -> Add Server, адрес из строк выше."
  echo "  Нестандартный порт: bash $0 scan-ping <IP> <порт>"
}

do_scanping() {
  local ip="${1:-}" port="${2:-25565}"
  [ -n "$ip" ] || { err "укажи: bash $0 scan-ping <IP> <порт>"; return 1; }
  command -v python >/dev/null 2>&1 || pkg_install python
  python "$(dirname "$0")/mcping.py" ping "$ip" "$port" || python "$(dirname "$0")/mcping.py" bedrock "$ip" "$port"
}

# ---------- Миры и двусторонний обмен (через SSH на ПК) ----------
do_world() {
  local mode="${1:-list}" world="${2:-}" dest="${3:-}"
  hdr "Minecraft: миры на телефоне"
  local n=0 w
  for w in ~/mc/world ~/mc/world_* "$STORE/games/com.mojang/minecraftWorlds"/*; do
    [ -d "$w" ] || continue
    { [ -f "$w/level.dat" ] || [ -f "$w/levelname.txt" ]; } || continue
    n=$((n+1)); printf '  %2d) %s\n      %s\n' "$n" "$(basename "$w")" "$w"
  done
  [ "$n" = 0 ] && warn "миры не найдены (Bedrock-миры: $STORE/games/com.mojang/minecraftWorlds)"
  [ "$mode" = "list" ] && return 0

  [ -n "$world" ] || { err "укажи мир: bash $0 world $mode <путь-к-миру> user@IP:/путь"; return 1; }
  [ -n "$dest" ] || { err "укажи получателя: user@IP:/путь/общей/папки"; return 1; }
  pkg_install rsync openssh >/dev/null 2>&1
  local ROPTS=(-a --update --exclude=session.lock --progress)
  if [ "$mode" = "push" ] || [ "$mode" = "sync" ]; then
    echo "  Отдаю мир на ПК..."; rsync "${ROPTS[@]}" "$world/" "$dest/$(basename "$world")/" && ok "готово"
  fi
  if [ "$mode" = "pull" ] || [ "$mode" = "sync" ]; then
    echo "  Забираю мир с ПК..."; rsync "${ROPTS[@]}" "$dest/$(basename "$world")/" "$world/" && ok "готово"
  fi
  echo "  Bedrock-миры на телефоне: GUI-клиент или HTTP-обмен (bash $0 http)"
}

do_sync() {
  local local_dir="${1:-$STORE/Download}" remote_dir="${2:-}" watch="${3:-0}"
  [ -n "$remote_dir" ] || { err "укажи: bash $0 sync <локальная папка> user@IP:/путь [секунды]"; return 1; }
  pkg_install rsync openssh >/dev/null 2>&1
  mkdir -p "$local_dir"
  hdr "Двусторонний обмен с ПК"
  echo "  Телефон : $local_dir"
  echo "  ПК      : $remote_dir"
  local ROPTS=(-a --update)
  if [ "${MIRROR:-0}" = "1" ]; then warn "режим ЗЕРКАЛО: лишнее удаляется"; ROPTS=(-a --update --delete); fi
  while true; do
    echo "  [$(date +%H:%M:%S)] туда..."
    rsync "${ROPTS[@]}" "$local_dir/" "$remote_dir/" && echo "     ок"
    echo "  [$(date +%H:%M:%S)] обратно..."
    rsync "${ROPTS[@]}" "$remote_dir/" "$local_dir/" && echo "     ок"
    if [ "$watch" != "0" ] && [ "$watch" -gt 0 ] 2>/dev/null; then
      echo "  ... через $watch сек. (Ctrl+C — стоп)"; sleep "$watch"
    else
      echo "  Один проход. Для постоянного обмена добавь секунды."; break
    fi
  done
}

# ================= ПРОСТОЕ МЕНЮ =================
do_menu() {
  # тихая проверка обновлений один раз за запуск
  UPDATE_OFFER=""
  if [ "${NOUPDATECHECK:-0}" != "1" ] && [ ! -f "$PEER_HOME/noupdate" ]; then
    if do_update_check 1 >/dev/null 2>&1; then UPDATE_OFFER=1; fi
  fi
  while true; do
    clear 2>/dev/null
    echo ""
    echo -e "  ${C_C}================================================${C_0}"
    echo -e "  ${C_C}   ТЕЛЕФОН: СЕТЬ + MINECRAFT (Termux)          ${C_0}"
    echo -e "  ${C_C}================================================${C_0}"
    if [ -n "$UPDATE_OFFER" ]; then
      echo -e "  ${C_G}>>> ДОСТУПНО ОБНОВЛЕНИЕ — пункт 14 <<<${C_0}"
    fi
    echo ""
    echo "   1  Первая настройка (SSH, файлы, доступ к памяти)"
    echo "   2  Показать мой IP на телефоне"
    echo "   3  Раздать файлы с телефона в браузер"
    echo "   4  Скачать файл с ПК (браузерная раздача)"
    echo -e "   5  ${C_G}Minecraft: как подключиться к серверу${C_0}"
    echo -e "   6  ${C_G}Minecraft: сервер на телефоне (для 1-2 человек)${C_0}"
    echo -e "   7  ${C_G}Minecraft: найти игру в сети (скан + LAN-поиск)${C_0}"
    echo -e "   8  ${C_G}Minecraft: перенести/синхронизировать мир${C_0}"
    echo "   9  Двусторонняя папка-обмен с ПК (по SSH)"
    echo "  10  Включить SSH-сервер (заход с ПК на телефон)"
    echo -e "  11  ${C_Y}Разрешить приём синхронизации с ПК на N минут (взвести)${C_0}"
    echo -e "  12  ${C_Y}Синхронизация с партнёром по SSH (телефон сам)${C_0}"
    echo "  13  Журнал удалённых действий"
    echo -e "  14  ${C_C}Проверить и установить обновление${C_0} (v$(local_version))"
    echo "   0  Выход"
    echo ""
    read -rp "  Введи цифру и нажми Enter: " c
    case "$c" in
      1) do_setup; echo; read -rp "  Enter -> назад в меню" ;;
      2) show_ip; echo; read -rp "  Enter -> назад в меню" ;;
      3) do_http ;;
      4) read -rp "  Вставь ссылку (http://...): " u; do_get "$u"; echo; read -rp "  Enter -> назад" ;;
      5) do_mc join; echo; read -rp "  Enter -> назад в меню" ;;
      6) do_mc server; echo; read -rp "  Enter -> назад в меню" ;;
      7) do_scan; echo; read -rp "  Enter -> назад в меню" ;;
      8)
         do_world list; echo
         read -rp "  Путь к миру: " w
         read -rp "  Куда (user@IP:/путь): " d
         read -rp "  [1] отдать [2] забрать [3] синхронизировать (Enter=3): " m
         case "$m" in 1) m=push ;; 2) m=pull ;; *) m=sync ;; esac
         do_world "$m" "$w" "$d"; echo; read -rp "  Enter -> назад в меню" ;;
      9)
         read -rp "  Локальная папка (Enter = Download): " ld
         read -rp "  Папка на ПК (user@IP:/путь): " rd
         read -rp "  Обновлять каждые N секунд? (Enter = один раз): " sec
         do_sync "${ld:-}" "$rd" "${sec:-0}"; echo; read -rp "  Enter -> назад в меню" ;;
      10) do_ssh; echo; read -rp "  Enter -> назад в меню" ;;
      11)
         echo "  Придумай код (6+ символов) и скажи его тому, кто будет подключаться."
         read -rp "  Код: " t
         if [ -n "$t" ]; then
           read -rp "  На сколько минут (Enter = 30, максимум 240): " m
           read -rp "  Только один проход? [y/N]: " one
           args=(-t "$t" -m "${m:-30}")
           [ "$one" = "y" ] && args+=(--once)
           peer_arm "${args[@]}"
         fi
         echo; read -rp "  Enter -> назад в меню" ;;
      12)
         peer_list; echo
         read -rp "  Имя партнёра: " n
         if [ -n "$n" ]; then
           read -rp "  Моя папка (Enter = Download): " ld
           read -rp "  Папка на ПК: " rd
           read -rp "  Код с той машины: " tok
           TOKEN="$tok" peer_sync "$n" "${ld:-}" "$rd" 0
         fi
         echo; read -rp "  Enter -> назад в меню" ;;
      13) peer_log; echo; read -rp "  Enter -> назад в меню" ;;
      14)
         do_update_check
         echo
         read -rp "  Установить обновление сейчас? [y/N]: " yn
         [ "$yn" = "y" ] && { do_update; echo; read -rp "  Готово. Enter -> назад в меню"; } 
         ;;
      0) exit 0 ;;
      *) echo "  Не понял. Введи цифру из списка."; sleep 2 ;;
    esac
  done
}

# ============================================================
#  PEER: удалённая синхронизация через SSH (см. README)
#  На обеих машинах один и тот же тулкит. Приём разрешается ТОЛЬКО вручную:
#    bash lan-android.sh peer-arm -t <код> -m 30
#  Взвести удалённо нельзя (peer-arm нет в белом списке).
# ============================================================
PEER_HOME="${PEER_HOME:-$HOME/.lan-toolkit}"
TOOLKIT_FILES=(lan-win.ps1 lan-linux.sh lan-android.sh mcping.py)

peer_dir() { mkdir -p "$PEER_HOME/keys"; }
peer_key() { echo "$PEER_HOME/keys/id_ed25519"; }
peer_kh()  { echo "$PEER_HOME/known_hosts_peers"; }
peer_peers() { echo "$PEER_HOME/peers"; }
sha_of_str() { printf '%s' "$1" | sha256sum | cut -d' ' -f1; }
norm_hash() { tr -d '\r' < "$1" | sha256sum | cut -d' ' -f1; }

toolkit_hash() {
  local dir="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}" body="" n fp h
  for n in "${TOOLKIT_FILES[@]}"; do
    fp="$dir/$n"
    if [ -f "$fp" ]; then h=$(norm_hash "$fp"); else h='-'; fi
    body="${body}${n}:${h}\n"
  done
  printf '%b' "$body" | sha256sum | cut -d' ' -f1
}
peer_audit() { echo "$(date '+%Y-%m-%d %H:%M:%S')  $*" >> "$PEER_HOME/audit.log"; }

peer_arm() {
  local token="" minutes=30 once=0 allowfp=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --token|-t) token="${2:-}"; shift 2 ;;
      --minutes|-m) minutes="${2:-30}"; shift 2 ;;
      --once) once=1; shift ;;
      --fp) allowfp="${2:-}"; shift 2 ;;
      *) shift ;;
    esac
  done
  peer_dir
  [ -n "$token" ] || { echo "[x] нужен токен: peer-arm -t <код> [-m 30] [--once]"; return 1; }
  [ "${#token}" -ge 6 ] || { echo "[x] токен короче 6 символов"; return 1; }
  [ "$minutes" -le 240 ] 2>/dev/null || { echo "[x] максимум 240 минут"; return 1; }
  {
    echo "TokenHash=$(sha_of_str "$token")"
    echo "Expires=$(( $(date +%s) + minutes * 60 ))"
    echo "Once=$once"
    echo "AllowFp=$allowfp"
    echo "ToolkitHash=$(toolkit_hash)"
    echo "ArmedBy=$(whoami)@$(hostname)"
  } > "$PEER_HOME/armed"
  chmod 600 "$PEER_HOME/armed" 2>/dev/null
  peer_audit "ARM на $minutes мин, once=$once"
  echo "[+] телефон взведён на $minutes мин — принимаю удалённую синхронизацию"
  echo "    отключить: bash lan-android.sh peer-disarm"
}

peer_disarm() {
  peer_dir
  rm -f "$PEER_HOME/armed"
  peer_audit "DISARM"
  echo "[-] телефон больше не принимает удалённые команды"
}

peer_serve() {
  peer_dir
  local raw cmd="" token="" from="" their_hash=""
  raw="$(cat)"
  local line key val
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    key="${line%%=*}"; val="${line#*=}"
    case "$key" in
      cmd) cmd="$val" ;;
      token) token="$val" ;;
      from) from="$val" ;;
      hash) their_hash="$val" ;;
      arg.local) ARG_LOCAL="$val" ;;
      arg.remote) ARG_REMOTE="$val" ;;
      arg.mode) ARG_MODE="$val" ;;
      arg.world) ARG_WORLD="$val" ;;
    esac
  done <<< "$raw"

  deny() { peer_audit "DENY cmd=$cmd from=$from: $1"; echo "RESULT=denied"; echo "MSG=$1"; }

  [ -f "$PEER_HOME/armed" ] || { deny "телефон не взведён: нужно выполнить peer-arm -t <код>"; return; }
  local A_TOKENHASH A_EXPIRES A_ONCE A_ALLOWFP
  A_TOKENHASH=$(grep '^TokenHash=' "$PEER_HOME/armed" | cut -d= -f2-)
  A_EXPIRES=$(grep '^Expires=' "$PEER_HOME/armed" | cut -d= -f2-)
  A_ONCE=$(grep '^Once=' "$PEER_HOME/armed" | cut -d= -f2-)
  A_ALLOWFP=$(grep '^AllowFp=' "$PEER_HOME/armed" | cut -d= -f2-)
  [ "$(date +%s)" -lt "$A_EXPIRES" ] || { deny "срок взведения истёк"; return; }
  [ -n "$token" ] || { deny "не передан токен"; return; }
  [ "$(sha_of_str "$token")" = "$A_TOKENHASH" ] || { deny "неверный токен"; return; }
  if [ -n "$A_ALLOWFP" ] && [ "$A_ALLOWFP" != "$from" ]; then deny "инициатор $from не разрешён"; return; fi

  local allowed=0 c
  for c in ping hash status detect world sync; do [ "$cmd" = "$c" ] && allowed=1; done
  [ "$allowed" = "1" ] || { deny "команда '$cmd' не в белом списке"; return; }

  local my_hash; my_hash=$(toolkit_hash)
  if [ -n "$their_hash" ] && [ "$their_hash" != "$my_hash" ] && [ "${ALLOW_DRIFT:-0}" != "1" ]; then
    peer_audit "DENY cmd=$cmd from=$from: hash mismatch"
    echo "RESULT=denied"
    echo "MSG=версии скриптов разные: у меня $my_hash, у инициатора $their_hash"
    return
  fi
  [ "$A_ONCE" = "1" ] && rm -f "$PEER_HOME/armed"

  peer_audit "ACCEPT cmd=$cmd from=$from"
  echo "RESULT=ok"
  echo "hash=$my_hash"
  echo "host=$(hostname)"
  case "$cmd" in
    ping)   echo "MSG=готов" ;;
    status) do_status; echo "MSG=status выполнен" ;;
    detect) do_detect; echo "MSG=detect выполнен" ;;
    world)  do_world "${ARG_MODE:-list}" "${ARG_WORLD:-}" "${ARG_REMOTE:-}"; echo "MSG=world выполнен" ;;
    sync)
      if [ -n "${ARG_LOCAL:-}" ] && [ -n "${ARG_REMOTE:-}" ]; then
        do_sync "$ARG_LOCAL" "$ARG_REMOTE" 0 && echo "MSG=sync выполнен" || echo "MSG=sync не удался"
      else
        echo "MSG=нужны arg.local и arg.remote"
      fi
      ;;
  esac
  peer_audit "DONE cmd=$cmd"
}

peer_keygen() {
  peer_dir
  local k; k="$(peer_key)"
  if [ ! -f "$k" ]; then
    ssh-keygen -t ed25519 -N '' -C "lan-toolkit@$(hostname)" -f "$k" >/dev/null 2>&1
    echo "[+] создан ключ: $k"
  else
    echo "[+] ключ уже есть: $k"
  fi
  echo "Публичный ключ — добавить на второй машине:"; cat "$k.pub"
}

peer_add() {
  local name="${1:-}" host="${2:-}" user="${3:-}" port="${4:-8022}" plat="${5:-android}" tk="${6:-lan-toolkit}"
  [ -n "$name" ] && [ -n "$host" ] || { echo "[x] укажи: peer-add <имя> <IP> [user] [порт] [win|linux|android]"; return 1; }
  peer_dir
  ssh-keyscan -p "$port" "$host" > "$(peer_kh)" 2>/dev/null && echo "[+] host key сохранён" || echo "[!] host key не прочитан"
  grep -v "^$name|" "$(peer_peers)" 2>/dev/null > "$(peer_peers).tmp" || true
  mv "$(peer_peers).tmp" "$(peer_peers)" 2>/dev/null
  echo "$name|$host|$user|$port|$plat|$tk" >> "$(peer_peers)"
  echo "[+] peer '$name' -> $user@$host:$port ($plat)"
}

peer_get() { grep "^$1|" "$(peer_peers)" 2>/dev/null | head -1; }

peer_invoke() {
  local name="$1" req="$2"
  local rec; rec="$(peer_get "$name")"
  [ -n "$rec" ] || { echo "[x] peer '$name' не найден"; return 1; }
  local host user port plat tk
  IFS='|' read -r _ host user port plat tk <<< "$rec"
  local runner
  case "$plat" in
    win) runner="powershell -NoProfile -ExecutionPolicy Bypass -File \"%USERPROFILE%\\$(echo "$tk" | tr '/' '\\')\\lan-win.ps1\" -Action peer-serve" ;;
    android) runner="bash \"\$HOME/$tk/lan-android.sh\" peer-serve" ;;
    *) runner="bash \"\$HOME/$tk/lan-linux.sh\" peer-serve" ;;
  esac
  printf '%s' "$req" | ssh -i "$(peer_key)" -p "$port" \
    -o "UserKnownHostsFile=$(peer_kh)" -o StrictHostKeyChecking=yes -o BatchMode=yes \
    -o ConnectTimeout=8 "$user@$host" "$runner" 2>&1
}

peer_list() {
  peer_dir
  if [ -s "$(peer_peers)" ]; then
    echo "Известные партнёры:"
    while IFS='|' read -r n h u p pl tk; do printf '  %-10s %s@%s:%s [%s]\n' "$n" "$u" "$h" "$p" "$pl"; done < "$(peer_peers)"
  else
    echo "  партнёров нет — добавь: peer-add <имя> <IP>"
  fi
  echo "Состояние ЭТОГО телефона (приём):"
  if [ ! -f "$PEER_HOME/armed" ]; then echo "  не взведён — команды отклоняются"
  else
    local exp; exp=$(grep '^Expires=' "$PEER_HOME/armed" | cut -d= -f2-)
    local left=$(( (exp - $(date +%s)) / 60 ))
    [ "$left" -gt 0 ] && echo "  ВЗВЕДЁН ещё ~$left мин" || echo "  взведён, но срок истёк"
  fi
}

peer_test() {
  local name="${1:-}"; [ -n "$name" ] || { echo "[x] укажи имя"; return 1; }
  local out; out="$(peer_invoke "$name" "v=1
cmd=ping
token=${TOKEN:-}
from=$(whoami)@$(hostname)
hash=$(toolkit_hash)
")"
  echo "$out" | head -4
  local m; m=$(grep -m1 '^MSG=' <<< "$out" | cut -d= -f2-)
  case "$m" in
    *"не взведён"*) echo "  -> на том устройстве: peer-arm -t <код>" ;;
    *"токен"*)      echo "  -> токен не совпал" ;;
    *"разные"*)     echo "  -> обнови тулкит на обоих устройствах" ;;
  esac
}

peer_sync() {
  local name="${1:-}"; [ -n "$name" ] || { echo "[x] укажи имя"; return 1; }
  local local_dir="${2:-}" remote_dir="${3:-$HOME/lan}" sec="${4:-0}"
  [ -n "$local_dir" ] || local_dir="$HOME/storage/shared/lan"
  local rec; rec="$(peer_get "$name")"
  [ -n "$rec" ] || { echo "[x] peer '$name' не найден"; return 1; }
  local host user port plat tk
  IFS='|' read -r _ host user port plat tk <<< "$rec"
  local remote_ssh="$user@$host:$remote_dir"
  mkdir -p "$local_dir"
  while true; do
    local out; out="$(peer_invoke "$name" "v=1
cmd=sync
token=${TOKEN:-}
from=$(whoami)@$(hostname)
hash=$(toolkit_hash)
arg.local=$remote_dir
arg.remote=$remote_ssh
")"
    echo "  [$(date +%H:%M:%S)] вторая сторона: $(grep -m1 '^RESULT=' <<< "$out" | cut -d= -f2) $(grep -m1 '^MSG=' <<< "$out" | cut -d= -f2-)"
    do_sync "$local_dir" "$remote_ssh" 0
    peer_audit "sync $name local=$local_dir remote=$remote_dir"
    if [ "$sec" != "0" ] && [ "$sec" -gt 0 ] 2>/dev/null; then sleep "$sec"; else break; fi
  done
}

peer_log() {
  peer_dir
  [ -f "$PEER_HOME/audit.log" ] && tail -40 "$PEER_HOME/audit.log" || echo "журнал пуст"
}

# ============================================================
#  АВТООБНОВЛЕНИЕ ИЗ GITHUB (версия в VERSION, суммы в MANIFEST.txt)
# ============================================================
UPDATE_REPO="${UPDATE_REPO:-S-ker/lan-toolkit}"
UPDATE_BRANCH="${UPDATE_BRANCH:-main}"
LOCAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RAW_BASE="https://raw.githubusercontent.com/$UPDATE_REPO/$UPDATE_BRANCH"
TARBALL="https://codeload.github.com/$UPDATE_REPO/tar.gz/refs/heads/$UPDATE_BRANCH"

http_get() {
  if command -v curl >/dev/null 2>&1; then
    if [ -n "${2:-}" ]; then curl -fsSL --max-time 120 "$1" -o "$2"; else curl -fsSL --max-time 10 "$1"; fi
  elif command -v wget >/dev/null 2>&1; then
    if [ -n "${2:-}" ]; then wget -q -O "$2" "$1"; else wget -q -O - "$1"; fi
  else
    return 127
  fi
}

local_version() { [ -f "$LOCAL_DIR/VERSION" ] && tr -d ' \t\r\n' < "$LOCAL_DIR/VERSION" || echo "0.0.0"; }
remote_version() { http_get "$RAW_BASE/VERSION?nocache=$(date +%s)" 2>/dev/null | tr -d ' \t\r\n'; }
# точный коммит ветки: файлы по SHA неизменяемы, поэтому кэш CDN не подсунет старый набор
remote_sha() { http_get "https://api.github.com/repos/$UPDATE_REPO/commits/$UPDATE_BRANCH" 2>/dev/null | grep -m1 '"sha"' | cut -d'"' -f4; }

ver_newer() {
  [ "$1" = "$2" ] && return 1
  local IFS='.'; local r=($1) l=($2) i a b
  for i in 0 1 2; do
    a="${r[$i]:-0}"; b="${l[$i]:-0}"
    [ "$a" -gt "$b" ] 2>/dev/null && return 0
    [ "$a" -lt "$b" ] 2>/dev/null && return 1
  done
  return 1
}

do_update_check() {
  local quiet="${1:-0}" lv rv
  lv="$(local_version)"; rv="$(remote_version)"
  if [ -z "$rv" ]; then
    [ "$quiet" != "1" ] && echo "  проверить не удалось (нет интернета?)"
    return 2
  fi
  if ver_newer "$rv" "$lv"; then
    [ "$quiet" != "1" ] && echo "  доступна новая версия: $rv (у тебя $lv)"
    return 0
  fi
  [ "$quiet" != "1" ] && echo "  версия $lv — самая свежая"
  return 1
}

do_update() {
  local force="${1:-0}" lv rv
  lv="$(local_version)"
  hdr "Обновление"
  echo "  Сейчас установлено: $lv"
  rv="$(remote_version)"
  [ -n "$rv" ] || { err "не смог узнать версию (интернет?)"; return 1; }
  echo "  На GitHub          : $rv"
  if [ "$force" != "1" ] && ! ver_newer "$rv" "$lv"; then ok "обновление не нужно"; return 0; fi
  local tmp; tmp="$(mktemp -d)"
  local ref; ref="$(remote_sha)"
  if [ -n "$ref" ]; then echo "  Коммит: $(printf '%.7s' "$ref")"; else ref="$UPDATE_BRANCH"; fi
  echo "  Скачиваю архив..."
  http_get "https://codeload.github.com/$UPDATE_REPO/tar.gz/$ref" "$tmp/lt.tar.gz" || { err "скачать не удалось"; rm -rf "$tmp"; return 1; }
  tar -xzf "$tmp/lt.tar.gz" -C "$tmp" || { err "архив не распаковался"; rm -rf "$tmp"; return 1; }
  local root; root="$(find "$tmp" -maxdepth 1 -type d ! -path "$tmp" | head -1)"
  [ -n "$root" ] || { err "пустой архив"; rm -rf "$tmp"; return 1; }
  echo "  Проверяю содержимое..."
  [ -f "$root/MANIFEST.txt" ] || { err "в архиве нет MANIFEST.txt — отменяю"; rm -rf "$tmp"; return 1; }
  local bad=0 checked=0 sum name fp got
  while read -r sum name; do
    [ -n "${name:-}" ] || continue
    fp="$root/$name"
    if [ ! -f "$fp" ]; then err "нет файла $name"; bad=$((bad+1)); continue; fi
    got="$(norm_hash "$fp")"
    if [ "$got" != "$sum" ]; then err "не сходится сумма: $name"; bad=$((bad+1)); continue; fi
    checked=$((checked+1))
  done < "$root/MANIFEST.txt"
  if [ "$bad" -gt 0 ] || [ "$checked" -eq 0 ]; then
    err "проверка не прошла ($bad ошибок) — ничего не меняю"; rm -rf "$tmp"; return 1
  fi
  ok "суммы сошлись: $checked файлов"
  local f
  for f in lan-android.sh lan-linux.sh start-linux.sh; do
    [ -f "$root/$f" ] && { bash -n "$root/$f" || { err "новый $f с ошибкой синтаксиса — отменяю"; rm -rf "$tmp"; return 1; }; }
  done
  local bk="$PEER_HOME/backup/$lv-$(date +%Y%m%d-%H%M%S)"
  # без бэкапа не обновляемся: откатываться будет некуда
  if ! mkdir -p "$bk" || ! cp -a "$LOCAL_DIR"/. "$bk"/ 2>/dev/null || [ -z "$(ls -A "$bk" 2>/dev/null)" ]; then
    err "не смог сделать бэкап ($bk) — отменяю обновление"
    rm -rf "$tmp"; return 1
  fi
  rm -rf "$bk/.git"
  echo "  Бэкап: $bk"
  local n=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    cp -f "$f" "$LOCAL_DIR/$(basename "$f")" && n=$((n+1))
  done < <(find "$root" -maxdepth 1 -type f)
  chmod +x "$LOCAL_DIR"/*.sh 2>/dev/null
  rm -rf "$tmp"
  peer_audit "update $lv -> $rv ($n файлов)"
  ok "обновлено до $rv (файлов: $n)"
  echo "  Откатить: bash $0 rollback"
}

do_rollback() {
  local base="$PEER_HOME/backup" last
  [ -d "$base" ] || { err "бэкапов нет"; return 1; }
  last="$(ls -1 "$base" | sort | tail -1)"
  [ -n "$last" ] || { err "бэкапов нет"; return 1; }
  hdr "Откат"
  local n=0 f
  for f in "$base/$last"/*; do
    [ -f "$f" ] || continue
    cp -f "$f" "$LOCAL_DIR/$(basename "$f")" && n=$((n+1))
  done
  chmod +x "$LOCAL_DIR"/*.sh 2>/dev/null
  peer_audit "rollback из $last ($n файлов)"
  ok "восстановлено файлов: $n (версия $(local_version))"
}

case "${1:-menu}" in
  menu)   do_menu ;;
  setup)  do_setup ;;
  ssh)    do_ssh ;;
  http)   do_http ;;
  get)    do_get "${@:2}" ;;
  mount)  do_mount "${@:2}" ;;
  mc|minecraft) do_mc "${@:2}" ;;
  scan)   do_scan "${@:2}" ;;
  scan-ping) do_scanping "${@:2}" ;;
  world)  do_world "${@:2}" ;;
  sync)   do_sync "${@:2}" ;;
  peer-serve)     peer_serve ;;
  peer-keygen)    peer_keygen ;;
  peer-add)       peer_add "${@:2}" ;;
  peer-list)      peer_list ;;
  peer-arm)       peer_arm "${@:2}" ;;
  peer-disarm)    peer_disarm ;;
  peer-test)      peer_test "${@:2}" ;;
  peer-sync)      peer_sync "${@:2}" ;;
  peer-log)       peer_log ;;
  update)         do_update ;;
  update-check)   do_update_check "${2:-0}" ;;
  rollback)       do_rollback ;;
  status) do_status ;;
  *) echo "usage: $0 {setup|ssh|http|get|mount|mc [join|server]|scan [prefix]|scan-ping <IP> [port]|world [list|push|pull|sync] <path> <user@IP:/dir>|sync <local> <user@IP:/dir> [sec]|peer-<keygen|add|list|arm|disarm|test|sync|log|serve>|status}"; exit 1 ;;
esac
