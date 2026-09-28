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
  while true; do
    clear 2>/dev/null
    echo ""
    echo -e "  ${C_C}================================================${C_0}"
    echo -e "  ${C_C}   ТЕЛЕФОН: СЕТЬ + MINECRAFT (Termux)          ${C_0}"
    echo -e "  ${C_C}================================================${C_0}"
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
      0) exit 0 ;;
      *) echo "  Не понял. Введи цифру из списка."; sleep 2 ;;
    esac
  done
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
  status) do_status ;;
  *) echo "usage: $0 {setup|ssh|http|get|mount|mc [join|server]|scan [prefix]|scan-ping <IP> [port]|world [list|push|pull|sync] <path> <user@IP:/dir>|sync <local> <user@IP:/dir> [sec]|status}"; exit 1 ;;
esac
