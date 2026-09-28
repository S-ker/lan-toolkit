#!/usr/bin/env bash
# ============================================================
#  LAN Toolkit — сторона Linux
#  Связки: Linux<->Win, Linux<->Android, Linux<->Linux
#  Запуск: sudo bash lan-linux.sh <команда>
#  Команды: setup | share | http | mount | ssh | status | remove
# ============================================================
set -uo pipefail

SHARE_NAME="${SHARE_NAME:-LAN}"
SHARE_DIR="${SHARE_DIR:-/srv/lanshare}"
SMB_USER="${SMB_USER:-lan}"
SMB_PASS="${SMB_PASS:-}"          # если пусто — будет сгенерирован
PORT="${PORT:-8080}"
MOUNT_DIR="${MOUNT_DIR:-/mnt/lan}"
MC_DIR="${MC_DIR:-/srv/minecraft}"
MC_PORT="${MC_PORT:-25565}"
MC_MEM="${MC_MEM:-2G}"
BEDROCK_PORT="${BEDROCK_PORT:-19132}"
TOKEN="${TOKEN:-}"                  # токен для peer-синхронизации (взведение на той стороне)
ALLOW_DRIFT="${ALLOW_DRIFT:-0}"     # 1 = не сверять хеш тулкита с инициатором

C_G="\033[32m"; C_Y="\033[33m"; C_R="\033[31m"; C_C="\033[36m"; C_0="\033[0m"
ok()   { echo -e "${C_G}[+]${C_0} $*"; }
warn() { echo -e "${C_Y}[!]${C_0} $*"; }
err()  { echo -e "${C_R}[x]${C_0} $*"; }
hdr()  { echo -e "\n${C_C}=== $* ===${C_0}"; }

need_root() { [ "$(id -u)" -eq 0 ] || { err "нужен root: sudo bash $0 $*"; exit 1; }; }

# ---------- пакетный менеджер ----------
pkg_install() {
  local pkgs=("$@")
  if command -v apt >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt update -qq && apt install -y "${pkgs[@]}"
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y "${pkgs[@]}"
  elif command -v pacman >/dev/null 2>&1; then
    pacman -Sy --noconfirm "${pkgs[@]}"
  elif command -v zypper >/dev/null 2>&1; then
    zypper --non-interactive install "${pkgs[@]}"
  elif command -v apk >/dev/null 2>&1; then
    apk add --no-cache "${pkgs[@]}"
  else
    err "неизвестный пакетный менеджер"; return 1
  fi
}

fw_open() {
  local ports=("$@")
  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qi active; then
    for p in "${ports[@]}"; do ufw allow "$p" >/dev/null 2>&1; done
    ok "ufw: открыты ${ports[*]}"
  elif command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    for p in "${ports[@]}"; do
      firewall-cmd --permanent --add-port="${p%/*}" 2>/dev/null
      firewall-cmd --add-port="${p%/*}" 2>/dev/null
    done
    firewall-cmd --reload >/dev/null 2>&1
    ok "firewalld: открыты ${ports[*]}"
  else
    warn "активного файрвола не найдено (ок)"
  fi
}

show_ip() {
  echo -e "  IPv4:"
  if command -v ip >/dev/null 2>&1; then
    ip -4 -o addr show scope global | awk '{split($4,a,"/"); printf "   -> %s (%s)\n", a[1], $2}'
  else
    ifconfig 2>/dev/null | awk '/inet /{print "   -> "$2}'
  fi
  command -v hostname >/dev/null 2>&1 && echo "  host: $(hostname)"
}

# ---------- setup ----------
do_setup() {
  need_root "$@"
  hdr "LAN Toolkit: Linux setup"
  echo "[1] Пакеты"
  pkg_install samba openssh-server avahi-daemon cifs-utils || warn "часть пакетов не встала"

  echo "[2] Службы"
  for svc in sshd ssh smbd nmbd avahi-daemon; do
    if systemctl list-unit-files 2>/dev/null | grep -q "^${svc}\."; then
      systemctl enable --now "$svc" >/dev/null 2>&1 && ok "$svc включена"
    fi
  done

  echo "[3] Файрвол"
  fw_open 445/tcp 139/tcp 137/udp 138/udp 22/tcp 5353/udp 4445/udp "$PORT/tcp"

  echo "[4] SMB-шара"
  do_share silent

  hdr "ГОТОВО"
  show_ip
  local ip; ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  cat <<EOF

=== Подключение К Linux ===
Windows : \\$ip\\$SHARE_NAME   (проводник; логин $SMB_USER)
Linux   : smb://$ip/$SHARE_NAME
Android : SMB-клиент -> smb://$ip/$SHARE_NAME
SSH     : ssh $SMB_USER@$ip
HTTP    : sudo bash $0 http  ->  http://$ip:$PORT

SMB-логин: $SMB_USER
SMB-пароль: ${SMB_PASS:-<смотри вывод выше / задай SMB_PASS>}
EOF
}

# ---------- share ----------
do_share() {
  [ "${1:-}" = "silent" ] || need_root "$@"
  command -v smbd >/dev/null 2>&1 || pkg_install samba
  mkdir -p "$SHARE_DIR"
  chmod 0777 "$SHARE_DIR"

  if ! id "$SMB_USER" >/dev/null 2>&1; then
    useradd -M -s /usr/sbin/nologin "$SMB_USER" 2>/dev/null || adduser -D -H -s /sbin/nologin "$SMB_USER" 2>/dev/null
  fi
  [ -n "$SMB_PASS" ] || SMB_PASS="$(head -c 12 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 12)"
  (echo "$SMB_PASS"; echo "$SMB_PASS") | smbpasswd -s -a "$SMB_USER" >/dev/null 2>&1

  local conf=/etc/samba/smb.conf
  [ -f "$conf" ] && cp -n "$conf" "${conf}.lanbak" 2>/dev/null
  if ! grep -q "^\[$SHARE_NAME\]" "$conf" 2>/dev/null; then
    cat >> "$conf" <<EOF

[$SHARE_NAME]
   path = $SHARE_DIR
   browseable = yes
   read only = no
   guest ok = no
   valid users = $SMB_USER
   create mask = 0666
   directory mask = 0777
EOF
  else
    warn "секция [$SHARE_NAME] уже есть в $conf — не меняю"
  fi
  grep -q "server min protocol = SMB2" "$conf" || sed -i '/^\[global\]/a\   server min protocol = SMB2\n   map to guest = never' "$conf" 2>/dev/null

  systemctl restart smbd 2>/dev/null || service smbd restart 2>/dev/null
  ok "шара //$(hostname)/$SHARE_NAME -> $SHARE_DIR (user: $SMB_USER / $SMB_PASS)"
}

# ---------- http ----------
do_http() {
  mkdir -p "$SHARE_DIR"
  fw_open "$PORT/tcp"
  local ip; ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  ok "HTTP-обмен каталога $SHARE_DIR"
  echo "  http://$ip:$PORT   (для Android/любого браузера)"
  command -v python3 >/dev/null 2>&1 || pkg_install python3
  (cd "$SHARE_DIR" && python3 -m http.server "$PORT" --bind 0.0.0.0)
}

# ---------- mount ----------
do_mount() {
  need_root "$@"
  local remote="${1:-}"
  [ -n "$remote" ] || { err "укажи шлях: bash $0 mount //192.168.1.50/LAN [user] [pass]"; exit 1; }
  local user="${2:-Guest}" pass="${3:-}"
  pkg_install cifs-utils >/dev/null 2>&1
  mkdir -p "$MOUNT_DIR"
  local opts="vers=3.0,uid=$(id -u),gid=$(id -g),iocharset=utf8,user=$user"
  [ -n "$pass" ] && opts="$opts,password=$pass"
  mount -t cifs "$remote" "$MOUNT_DIR" -o "$opts" && ok "$remote -> $MOUNT_DIR" || err "не смонтировалось"
}

# ---------- ssh ----------
do_ssh() {
  need_root "$@"
  pkg_install openssh-server >/dev/null 2>&1
  systemctl enable --now sshd 2>/dev/null || systemctl enable --now ssh 2>/dev/null
  fw_open 22/tcp
  show_ip
  ok "SSH готов: ssh $(whoami)@<IP>  (из Termux/Windows/Telephone)"
}

# ---------- minecraft ----------
do_mc() {
  local kind="${1:-java}"      # java | bedrock | firewall | join
  case "$kind" in
    firewall|fw)
      fw_open "$MC_PORT/tcp" "$MC_PORT/udp" "$BEDROCK_PORT/udp"
      ok "порты Minecraft открыты"; return ;;
    join)
      show_ip
      echo "  Java    : <IP>:$MC_PORT"
      echo "  Bedrock : <IP>:$BEDROCK_PORT (UDP)"
      return ;;
  esac

  need_root "$@"
  if [ "$kind" = "bedrock" ]; then
    hdr "Bedrock Dedicated Server"
    if ! command -v unzip >/dev/null 2>&1; then pkg_install unzip; fi
    mkdir -p "$MC_DIR" && cd "$MC_DIR"
    if [ ! -f bedrock-server.zip ]; then
      ok "качаю актуальный Bedrock Server (aka.ms)"
      curl -L -o bedrock-server.zip "https://aka.ms/minecraftbedrockserverlinux" || { err "не скачалось"; return 1; }
    fi
    unzip -o bedrock-server.zip >/dev/null 2>&1
    fw_open "$BEDROCK_PORT/udp"
    chmod +x bedrock_server 2>/dev/null
    cat > start-bedrock.sh <<EOF
#!/usr/bin/env bash
cd "\$(dirname "\$0")"
LD_LIBRARY_PATH=. ./bedrock_server
EOF
    chmod +x start-bedrock.sh
    show_ip
    ok "готово: cd $MC_DIR && ./start-bedrock.sh"
    echo "  Подключение: Bedrock -> Add Server -> <IP>:$BEDROCK_PORT"
    return
  fi

  hdr "Java Edition server (Paper)"
  pkg_install curl jq 2>/dev/null || pkg_install curl
  command -v java >/dev/null 2>&1 || {
    warn "Java нет — ставлю openjdk 21/17"
    pkg_install openjdk-21-jre-headless 2>/dev/null || pkg_install openjdk-17-jre-headless 2>/dev/null || pkg_install java-21-openjdk-headless 2>/dev/null || warn "поставь JDK 17+ вручную"
  }
  mkdir -p "$MC_DIR" && cd "$MC_DIR"

  if [ ! -f server.jar ]; then
    ok "ищу последний Paper build..."
    local ver build url
    ver="$(curl -s https://api.papermc.io/v2/projects/paper | sed -n 's/.*"versions":\[\(.*\)\].*/\1/p' | tr -d ' "' | tr ',' '\n' | tail -1)"
    if [ -n "$ver" ]; then
      build="$(curl -s "https://api.papermc.io/v2/projects/paper/versions/$ver" | sed -n 's/.*"builds":\[\([0-9,]*\)\].*/\1/p' | tr ',' '\n' | tail -1)"
      url="https://api.papermc.io/v2/projects/paper/versions/$ver/builds/$build/downloads/paper-$ver-$build.jar"
      curl -L -o server.jar "$url" && ok "скачан Paper $ver build $build" || warn "не скачался Paper — положи server.jar вручную"
    fi
  fi
  echo "eula=true" > eula.txt
  if [ ! -f server.properties ]; then
    cat > server.properties <<EOF
server-port=$MC_PORT
enable-query=true
query.port=$MC_PORT
motd=LAN Minecraft
max-players=20
view-distance=8
online-mode=true
EOF
  fi
  fw_open "$MC_PORT/tcp" "$MC_PORT/udp"
  show_ip
  ok "готово: cd $MC_DIR && java -Xmx$MC_MEM -Xms$MC_MEM -jar server.jar nogui"
  echo "  Автозапуск-хелпер: создаю start-mc.sh"
  cat > start-mc.sh <<EOF
#!/usr/bin/env bash
cd "\$(dirname "\$0")" || exit 1
exec java -Xmx$MC_MEM -Xms$MC_MEM -jar server.jar nogui
EOF
  chmod +x start-mc.sh
  echo "  Подключение: Java -> Direct Connection -> <IP>:$MC_PORT"
  echo "  Кросс-плей Java<->Bedrock: плагины Geyser + Floodgate в plugins/"
}

# ---------- Minecraft: LAN-сессия клиента ----------
mc_worlds_list() {
  local roots=(
    "$HOME/.minecraft/saves"
    "$HOME/.local/share/PrismLauncher/instances"
    "$HOME/.var/app/org.prismlauncher.PrismLauncher/data/PrismLauncher/instances"
    "$HOME/.local/share/multimc/instances"
    "$HOME/.local/share/MultiMC/instances"
    "$MC_DIR"
  )
  local r inst w
  for r in "${roots[@]}"; do
    [ -d "$r" ] || continue
    if ls "$r"/*/.minecraft/saves >/dev/null 2>&1; then
      for inst in "$r"/*; do
        [ -d "$inst/.minecraft/saves" ] || continue
        for w in "$inst"/.minecraft/saves/*; do
          [ -f "$w/level.dat" ] || continue
          printf '%s\t%s\t%s\n' "$(basename "$w")" "$w" "$(basename "$inst")"
        done
      done
    else
      for w in "$r"/*/; do
        [ -f "${w}level.dat" ] || continue
        printf '%s\t%s\t%s\n' "$(basename "$w")" "${w%/}" "local"
      done
    fi
  done
  return 0
}

do_detect() {
  hdr "Поиск запущенного Minecraft (клиент-клиент, «Открыть для сети»)"
  local pids p cl inst ver ports port out any=0
  pids="$(pgrep -f 'net\.minecraft' 2>/dev/null | tr '\n' ' ')"
  [ -z "$pids" ] && warn "Minecraft сейчас не запущен"
  for p in $pids; do
    [ -r "/proc/$p/cmdline" ] || continue
    cl="$(tr '\0' ' ' < "/proc/$p/cmdline")"
    case "$cl" in *java*) ;; *) continue ;; esac
    inst="$(echo "$cl" | grep -oE 'instances/[^/ ]+' | head -1 | cut -d/ -f2)"
    ver="$(echo "$cl"  | grep -oE 'minecraft-[0-9][^/ ;]*-client\.jar' | head -1 | sed 's/minecraft-//;s/-client\.jar//')"
    echo ""
    ok "КЛИЕНТ (игра) PID $p${inst:+   инстанс: $inst}${ver:+   версия: $ver}"
    ports="$(ss -tlnpH 2>/dev/null | grep "pid=$p," | awk '{print $4}' | sed 's/.*://' | sort -u)"
    [ -z "$ports" ] && ports="$(ss -tlnH 2>/dev/null | awk '{print $4}' | sed 's/.*://' | sort -u | grep -E '^[0-9]{4,5}$')"
    for port in $ports; do
      out="$(python3 "$(dirname "$0")/mcping.py" ping 127.0.0.1 "$port" 2>/dev/null)"
      case "$out" in
        *"OK=yes"*)
          any=1
          echo -e "    ${C_G}ЛОКАЛЬНАЯ СЕТЬ ОТКРЫТА -> порт $port${C_0}"
          echo "$out" | sed -n 's/^MOTD=/      Мир     : /p;s/^VERSION=/      Версия  : /p;s/^PLAYERS=/      Игроки  : /p;s/^WHO=/      В игре  : /p'
          fw_open "$port/tcp"
          echo "      Адрес для друзей:"
          show_ip | sed 's/^   -> /        /'
          ;;
      esac
    done
    if [ -z "$ports" ]; then
      warn "LAN не открыт. В игре: Esc -> «Открыть для сети» (Open to LAN)"
    fi
  done

  echo ""
  echo "  --- Поиск чужих LAN-игр (мультикаст 224.0.2.60) ---"
  command -v python3 >/dev/null 2>&1 && python3 "$(dirname "$0")/mcping.py" listen 4 2>/dev/null | sed -n 's/^HUMAN=/    /p'
  [ "$any" = 1 ] && echo -e "\n  ${C_G}Друзья: Multiplayer -> Direct Connection -> <IP>:<порт выше>${C_0}"
  return 0
}

# ---------- Minecraft: миры ----------
do_world() {
  local mode="${1:-list}"; local want="${2:-}"
  local remote="${3:-$SHARE_DIR/mcworlds}"
  hdr "Minecraft: миры"

  if [ "$mode" = "list" ]; then
    local n=0 name path inst busy
    while IFS=$'\t' read -r name path inst; do
      n=$((n+1)); busy=""
      if [ -f "$path/session.lock" ] && fuser "$path/session.lock" >/dev/null 2>&1; then busy=" [ЗАНЯТ игрой]"; fi
      printf '  %2d) %s  (%s)%s\n      %s\n' "$n" "$name" "$inst" "$busy" "$path"
    done < <(mc_worlds_list)
    [ "$n" = 0 ] && warn "миры не найдены"
    echo ""
    echo "  Синхронизация: sudo bash $0 world sync \"имя мира\" /путь/общей/папки"
    return 0
  fi

  local sel_name="" sel_path="" sel_inst=""
  while IFS=$'\t' read -r name path inst; do
    if [ -z "$want" ] || [ "$name" = "$want" ] || [ "${name#*"$want"}" != "$name" ]; then
      sel_name="$name"; sel_path="$path"; sel_inst="$inst"; break
    fi
  done < <(mc_worlds_list)
  [ -z "$sel_path" ] && { err "мир не найден${want:+: $want}"; return 1; }

  ok "мир: $sel_name"
  echo "     $sel_path"
  if [ -f "$sel_path/session.lock" ] && fuser "$sel_path/session.lock" >/dev/null 2>&1; then
    warn "мир сейчас используется игрой — закрой Minecraft"
    [ "${FORCE:-0}" = "1" ] || return 1
  fi

  mkdir -p "$remote"
  local dest="$remote/$sel_name"

  if [ "${NOBACKUP:-0}" != "1" ]; then
    mkdir -p "$remote/_backups"
    local bz="$remote/_backups/$(echo "$sel_name" | tr -c 'A-Za-z0-9_.-' '_')-$(date +%Y%m%d-%H%M%S).tar.gz"
    ok "бэкап: $bz"
    tar -czf "$bz" -C "$sel_path" . 2>/dev/null || warn "бэкап не сделался"
  fi

  command -v rsync >/dev/null 2>&1 || pkg_install rsync
  if ! command -v rsync >/dev/null 2>&1; then
    err "rsync не установлен — поставь вручную (apt install rsync / pacman -S rsync / apk add rsync)"
    return 1
  fi
  local ROPTS=(-a --update --exclude=session.lock)
  if [ "$mode" = "push" ] || [ "$mode" = "sync" ]; then
    echo "  Отдаю мир в общую папку..."
    rsync "${ROPTS[@]}" "$sel_path/" "$dest/" && ok "готово -> $dest"
  fi
  if [ "$mode" = "pull" ] || [ "$mode" = "sync" ]; then
    [ -d "$dest" ] || { err "в общей папке нет мира '$sel_name'"; return 1; }
    echo "  Забираю мир из общей папки..."
    rsync "${ROPTS[@]}" "$dest/" "$sel_path/" && ok "готово -> $sel_path"
  fi
  [ "$mode" = "backup" ] && ok "бэкап готов"
  return 0
}

# ---------- Двусторонний обмен папками ----------
do_sync() {
  local local_dir="${1:-$SHARE_DIR}" remote_dir="${2:-}" watch="${3:-0}"
  [ -n "$remote_dir" ] || { err "укажи: bash $0 sync <локальная папка> <папка-на-той-стороне> [секунды]"; return 1; }
  command -v rsync >/dev/null 2>&1 || pkg_install rsync
  if ! command -v rsync >/dev/null 2>&1; then
    err "rsync не установлен — поставь вручную (apt install rsync / pacman -S rsync / apk add rsync)"
    return 1
  fi
  mkdir -p "$local_dir"
  hdr "Двусторонний обмен"
  echo "  Локально : $local_dir"
  echo "  Удалённо : $remote_dir"
  local ROPTS
  if [ "${MIRROR:-0}" = "1" ]; then
    warn "режим ЗЕРКАЛО: лишние файлы удаляются с обеих сторон"
    ROPTS=(-a --update --delete)
  else
    ok "безопасный режим: новее побеждает, ничего не удаляется"
    ROPTS=(-a --update)
  fi
  while true; do
    echo "  [$(date +%H:%M:%S)] туда..."
    rsync "${ROPTS[@]}" "$local_dir/" "$remote_dir/" && echo "     ок"
    echo "  [$(date +%H:%M:%S)] обратно..."
    rsync "${ROPTS[@]}" "$remote_dir/" "$local_dir/" && echo "     ок"
    if [ "$watch" != "0" ] && [ "$watch" -gt 0 ] 2>/dev/null; then
      echo "  ... следующая синхронизация через $watch сек. (Ctrl+C — стоп)"
      sleep "$watch"
    else
      echo "  Один проход. Для постоянного обмена добавь секунды (например 30)."
      break
    fi
  done
}

# ---------- status ----------
do_status() {
  hdr "status"
  show_ip
  echo -e "\nSMB:"
  (smbstatus --shares 2>/dev/null || echo "  smbd не запущен") | head -20
  echo -e "\nSSH: $(systemctl is-active sshd 2>/dev/null || systemctl is-active ssh 2>/dev/null || echo 'off')"
  echo -e "AVAHI: $(systemctl is-active avahi-daemon 2>/dev/null || echo 'off')"
  echo -e "ШАРА: $SHARE_DIR ($(du -sh "$SHARE_DIR" 2>/dev/null | cut -f1))"
  echo -e "MINECRAFT: java=$(command -v java >/dev/null && echo on || echo off) dir=$MC_DIR port=$MC_PORT"
}

# ---------- remove ----------
do_remove() {
  need_root "$@"
  sed -i "/^\[$SHARE_NAME\]/,/^$/d" /etc/samba/smb.conf 2>/dev/null
  systemctl restart smbd 2>/dev/null
  smbpasswd -x "$SMB_USER" >/dev/null 2>&1
  ok "шара удалена, пользователь $SMB_USER убран"
}

# ============================================================
#  PEER: удалённая синхронизация через SSH (см. README)
#  На обеих машинах лежит один и тот же тулкит. Инициатор заходит по SSH
#  и просит вторую сторону сделать её половину работы.
#  Защиты: SSH-доступ, ручное ВЗВЕДЕНИЕ (peer-arm), токен, срок, белый список
#  команд, сверка хеша тулкита, журнал. Взвести удалённо нельзя.
# ============================================================
PEER_HOME="${PEER_HOME:-$HOME/.lan-toolkit}"
TOOLKIT_FILES=(lan-win.ps1 lan-linux.sh lan-android.sh mcping.py)

peer_dir() { mkdir -p "$PEER_HOME/keys"; echo "$PEER_HOME"; }
peer_key() { echo "$PEER_HOME/keys/id_ed25519"; }
peer_kh()  { echo "$PEER_HOME/known_hosts_peers"; }
peer_peers() { echo "$PEER_HOME/peers"; }

sha_of_str() { printf '%s' "$1" | sha256sum | cut -d' ' -f1; }

toolkit_hash() {
  local dir="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}" body="" n fp h
  for n in "${TOOLKIT_FILES[@]}"; do
    fp="$dir/$n"
    if [ -f "$fp" ]; then h=$(sha256sum -- "$fp" | cut -d' ' -f1); else h='-'; fi
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
  peer_dir >/dev/null
  if [ -z "$token" ]; then err "нужен токен: peer-arm -t <код> [-m 30] [--once]"; return 1; fi
  if [ "${#token}" -lt 6 ]; then err "токен короче 6 символов"; return 1; fi
  [ "$minutes" -le 240 ] 2>/dev/null || { err "максимум 240 минут"; return 1; }
  local exp=$(( $(date +%s) + minutes * 60 ))
  {
    echo "TokenHash=$(sha_of_str "$token")"
    echo "Expires=$exp"
    echo "Once=$once"
    echo "AllowFp=$allowfp"
    echo "ToolkitHash=$(toolkit_hash)"
    echo "ArmedBy=$(whoami)@$(hostname)"
  } > "$PEER_HOME/armed"
  chmod 600 "$PEER_HOME/armed"
  peer_audit "ARM на $minutes мин, once=$once"
  ok "машина взведена на $minutes мин — принимаю удалённую синхронизацию"
  echo "    отключить: bash $0 peer-disarm"
}

peer_disarm() {
  peer_dir >/dev/null
  rm -f "$PEER_HOME/armed"
  peer_audit "DISARM"
  ok "машина больше не принимает удалённые команды"
}

# --- принимающая сторона: читает запрос из stdin ---
peer_serve() {
  peer_dir >/dev/null
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
      arg.mirror) ARG_MIRROR="$val" ;;
    esac
  done <<< "$raw"

  deny() { peer_audit "DENY cmd=$cmd from=$from: $1"; echo "RESULT=denied"; echo "MSG=$1"; }

  [ -f "$PEER_HOME/armed" ] || { deny "машина не взведена: нужно выполнить peer-arm -t <код>"; return; }
  # shellcheck disable=SC1090
  local A_TOKENHASH A_EXPIRES A_ONCE A_ALLOWFP
  A_TOKENHASH=$(grep '^TokenHash=' "$PEER_HOME/armed" | cut -d= -f2-)
  A_EXPIRES=$(grep '^Expires=' "$PEER_HOME/armed" | cut -d= -f2-)
  A_ONCE=$(grep '^Once=' "$PEER_HOME/armed" | cut -d= -f2-)
  A_ALLOWFP=$(grep '^AllowFp=' "$PEER_HOME/armed" | cut -d= -f2-)
  [ "$(date +%s)" -lt "$A_EXPIRES" ] || { deny "срок взведения истёк"; return; }
  [ -n "$token" ] || { deny "не передан токен"; return; }
  [ "$(sha_of_str "$token")" = "$A_TOKENHASH" ] || { deny "неверный токен"; return; }
  if [ -n "$A_ALLOWFP" ] && [ "$A_ALLOWFP" != "$from" ]; then deny "инициатор $from не разрешён"; return; fi

  local my_hash allowed=0
  for c in ping hash status detect world sync; do
    [ "$cmd" = "$c" ] && allowed=1
  done
  [ "$allowed" = "1" ] || { deny "команда '$cmd' не в белом списке"; return; }

  my_hash=$(toolkit_hash)
  if [ -n "$their_hash" ] && [ "$their_hash" != "$my_hash" ] && [ "${ALLOW_DRIFT:-0}" != "1" ]; then
    peer_audit "DENY cmd=$cmd from=$from: hash mismatch"
    echo "RESULT=denied"
    echo "MSG=версии скриптов разные: у меня $my_hash, у инициатора $their_hash"
    return
  fi

  # одноразовое взведение сжигаем ДО работы
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
      if [ -z "${ARG_LOCAL:-}" ] || [ -z "${ARG_REMOTE:-}" ]; then
        echo "MSG=нужны arg.local и arg.remote"
      else
        if MIRROR="${ARG_MIRROR:-0}" do_sync "$ARG_LOCAL" "$ARG_REMOTE" 0; then
          echo "MSG=sync выполнен"
        else
          echo "MSG=sync не удался (нет rsync или недоступна папка)"
        fi
      fi
      ;;
  esac
  peer_audit "DONE cmd=$cmd"
}

# --- инициатор ---
peer_keygen() {
  peer_dir >/dev/null
  local k; k="$(peer_key)"
  if [ ! -f "$k" ]; then
    ssh-keygen -t ed25519 -N '' -C "lan-toolkit@$(hostname)" -f "$k" >/dev/null
    ok "создан ключ: $k"
  else
    ok "ключ уже есть: $k"
  fi
  echo
  echo "Публичный ключ — добавить на ВТОРОЙ машине:"
  cat "$k.pub"
  echo
  echo "  Linux/Android: ssh-copy-id -i $k.pub user@IP"
  echo "  Windows      : строка в C:\\Users\\<user>\\.ssh\\authorized_keys"
}

peer_add() {
  local name="${1:-}" host="${2:-}" user="${3:-$(whoami)}" port="${4:-22}" plat="${5:-linux}" tk="${6:-lan-toolkit}"
  [ -n "$name" ] && [ -n "$host" ] || { err "укажи: peer-add <имя> <IP> [user] [порт] [win|linux|android]"; return 1; }
  peer_dir >/dev/null
  echo "Пинную host key..."
  if ssh-keyscan -p "$port" "$host" > "$(peer_kh)" 2>/dev/null && [ -s "$(peer_kh)" ]; then
    ok "host key сохранён"
  else
    warn "host key не прочитан — машина недоступна?"
  fi
  grep -v "^$name|" "$(peer_peers)" 2>/dev/null > "$(peer_peers).tmp" || true
  mv "$(peer_peers).tmp" "$(peer_peers)" 2>/dev/null
  echo "$name|$host|$user|$port|$plat|$tk" >> "$(peer_peers)"
  ok "peer '$name' -> $user@$host:$port ($plat)"
  echo
  echo "Дальше:"
  echo "  1) bash $0 peer-bootstrap $name     # залить тулкит на ту машину"
  echo "  2) bash $0 peer-keygen              # и добавить ключ на ту машину"
  echo "  3) НА ТОЙ МАШИНЕ человек: peer-arm -t <код>"
  echo "  4) bash $0 peer-test $name"
}

peer_get() { grep "^$1|" "$(peer_peers)" 2>/dev/null | head -1; }

peer_invoke() {
  local name="$1" req="$2"
  local rec; rec="$(peer_get "$name")"
  [ -n "$rec" ] || { err "peer '$name' не найден (peer-list)"; return 1; }
  local host user port plat tk
  IFS='|' read -r _ host user port plat tk <<< "$rec"
  [ -f "$(peer_key)" ] || { err "нет ключа — запусти: bash $0 peer-keygen"; return 1; }
  local runner
  if [ "$plat" = "win" ]; then
    runner="powershell -NoProfile -ExecutionPolicy Bypass -File \"%USERPROFILE%\\$(echo "$tk" | tr '/' '\\')\\lan-win.ps1\" -Action peer-serve"
  elif [ "$plat" = "android" ]; then
    runner="bash \"\$HOME/$tk/lan-android.sh\" peer-serve"
  else
    runner="bash \"\$HOME/$tk/lan-linux.sh\" peer-serve"
  fi
  printf '%s' "$req" | timeout 600 ssh -i "$(peer_key)" -p "$port" \
    -o "UserKnownHostsFile=$(peer_kh)" -o StrictHostKeyChecking=yes -o BatchMode=yes \
    -o ConnectTimeout=8 "$user@$host" "$runner" 2>&1
}

peer_request() {
  local cmd="$1" token="$2"; shift 2
  local out="v=1
cmd=$cmd
token=$token
from=$(whoami)@$(hostname)
hash=$(toolkit_hash)"
  while [ $# -gt 0 ]; do out="$out
arg.${1}=${2}"; shift 2; done
  printf '%s\n\n' "$out"
}

peer_result() { grep -m1 '^RESULT=' <<< "$1" | cut -d= -f2; }
peer_msg()    { grep -m1 '^MSG=' <<< "$1" | cut -d= -f2-; }

peer_list() {
  peer_dir >/dev/null
  if [ -s "$(peer_peers)" ]; then
    echo -e "\nИзвестные партнёры:"
    while IFS='|' read -r n h u p pl tk; do
      printf '  %-10s %s@%s:%s  [%s]\n' "$n" "$u" "$h" "$p" "$pl"
    done < "$(peer_peers)"
  else
    warn "партнёров нет — добавь: bash $0 peer-add <имя> <IP>"
  fi
  echo -e "\nСостояние ЭТОЙ машины (приём удалённых команд):"
  if [ ! -f "$PEER_HOME/armed" ]; then
    echo "  не взведена — удалённые команды отклоняются"
  else
    local exp left
    exp=$(grep '^Expires=' "$PEER_HOME/armed" | cut -d= -f2-)
    left=$(( (exp - $(date +%s)) / 60 ))
    if [ "$left" -le 0 ]; then echo "  взведена, но срок истёк"; else echo "  ВЗВЕДЕНА ещё ~$left мин"; fi
  fi
}

peer_forget() {
  [ -n "${1:-}" ] || { err "укажи имя"; return 1; }
  peer_dir >/dev/null
  grep -v "^$1|" "$(peer_peers)" 2>/dev/null > "$(peer_peers).tmp" || true
  mv "$(peer_peers).tmp" "$(peer_peers)" 2>/dev/null
  peer_audit "peer-forget $1"
  ok "партнёр '$1' удалён"
}

peer_bootstrap() {
  local name="${1:-}"; [ -n "$name" ] || { err "укажи имя"; return 1; }
  local rec; rec="$(peer_get "$name")"
  [ -n "$rec" ] || { err "peer '$name' не найден"; return 1; }
  local host user port plat tk
  IFS='|' read -r _ host user port plat tk <<< "$rec"
  local dir; dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  echo "Копирую тулкит на $user@$host ($plat)..."
  # ssh использует -p, scp — -P: два разных набора опций
  local SSHOPT=(-i "$(peer_key)" -p "$port" -o "UserKnownHostsFile=$(peer_kh)" -o StrictHostKeyChecking=yes -o BatchMode=yes)
  local SCPOPT=(-i "$(peer_key)" -P "$port" -o "UserKnownHostsFile=$(peer_kh)" -o StrictHostKeyChecking=yes -o BatchMode=yes)
  if [ "$plat" = "win" ]; then
    ssh "${SSHOPT[@]}" "$user@$host" "mkdir \"$tk\" 2>nul & echo ok" >/dev/null 2>&1
  else
    ssh "${SSHOPT[@]}" "$user@$host" "mkdir -p \"\$HOME/$tk\"" >/dev/null 2>&1
  fi
  local okc=0 total=0 f
  for f in "$dir"/*; do
    case "$(basename "$f")" in .*|*.pyc) continue ;; esac
    total=$((total+1))
    if scp "${SCPOPT[@]}" "$f" "$user@$host:$tk/$(basename "$f")" >/dev/null 2>&1; then okc=$((okc+1)); fi
  done
  if [ "$plat" != "win" ]; then
    ssh "${SSHOPT[@]}" "$user@$host" "chmod +x \"\$HOME/$tk\"/*.sh 2>/dev/null; echo ok" >/dev/null 2>&1
  fi
  ok "отправлено файлов: $okc из $total"
  peer_audit "bootstrap $name ($okc файлов)"
  echo "Теперь НА ТОЙ машине человек выполняет: peer-arm -t <код>"
}

peer_test() {
  local name="${1:-}"; [ -n "$name" ] || { err "укажи имя"; return 1; }
  local out; out="$(peer_invoke "$name" "$(peer_request ping '')")"
  local res; res="$(peer_result "$out")"
  echo
  echo "Ответ второй стороны: RESULT=$res"
  local m; m="$(peer_msg "$out")"
  [ -n "$m" ] && echo "  MSG: $m"
  case "$m" in
    *"не взведена"*) echo "  -> на той машине: peer-arm -t <код>" ;;
    *"токен"*)       echo "  -> токен не совпал" ;;
    *"разные"*)      echo "  -> обнови тулкит на обеих машинах" ;;
  esac
  local rh; rh="$(grep -m1 '^hash=' <<< "$out" | cut -d= -f2)"
  if [ -n "$rh" ]; then
    if [ "$rh" = "$(toolkit_hash)" ]; then ok "скрипты совпадают"; else warn "версии скриптов разные"; fi
  fi
  peer_audit "test $name -> $res"
}

peer_sync() {
  local name="${1:-}"; [ -n "$name" ] || { err "укажи имя"; return 1; }
  local local_dir="${2:-}" remote_dir="${3:-}" sec="${4:-0}"
  [ -n "$local_dir" ] || local_dir="$SHARE_DIR/обмен"
  [ -n "$remote_dir" ] || remote_dir="$SHARE_DIR/обмен"
  local rec; rec="$(peer_get "$name")"
  [ -n "$rec" ] || { err "peer '$name' не найден"; return 1; }
  local host user port plat tk
  IFS='|' read -r _ host user port plat tk <<< "$rec"
  hdr "Двусторонняя синхронизация с '$name'"
  echo "  моя папка  : $local_dir"
  echo "  у партнёра : $remote_dir"
  mkdir -p "$local_dir"
  # куда положить шара партнёра (SMB)
  local peer_share="/mnt/peer-$name"
  mkdir -p "$peer_share" 2>/dev/null
  mountpoint -q "$peer_share" 2>/dev/null || \
    mount -t cifs "//$host/$SHARE_NAME" "$peer_share" -o "username=$SMB_USER,password=${SMB_PASS},vers=3.0,uid=$(id -u),gid=$(id -g)" 2>/dev/null || \
    warn "шара партнёра не смонтирована (моя половина может не пройти)"
  local my_ip; my_ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  while true; do
    local out; out="$(peer_invoke "$name" "$(peer_request sync "$TOKEN" local "$remote_dir" remote "//$my_ip/$SHARE_NAME/$(basename "$local_dir")" mirror "${MIRROR:-0}")")"
    local res; res="$(peer_result "$out")"
    if [ "$res" = "ok" ]; then echo "  [$(date +%H:%M:%S)] вторая сторона: ок"; else echo "  [$(date +%H:%M:%S)] вторая сторона: $res — $(peer_msg "$out")"; fi
    echo "  [$(date +%H:%M:%S)] моя сторона..."
    rsync -a --update "$local_dir/" "$peer_share/$(basename "$local_dir")/" 2>/dev/null && echo "     туда ок"
    rsync -a --update "$peer_share/$(basename "$local_dir")/" "$local_dir/" 2>/dev/null && echo "     обратно ок"
    peer_audit "sync $name local=$local_dir remote=$remote_dir"
    if [ "$sec" != "0" ] && [ "$sec" -gt 0 ] 2>/dev/null; then sleep "$sec"; else break; fi
  done
}

peer_log() {
  peer_dir >/dev/null
  if [ -f "$PEER_HOME/audit.log" ]; then hdr "Журнал"; tail -40 "$PEER_HOME/audit.log"
  else echo "журнал пуст"; fi
}

# ============================================================
#  АВТООБНОВЛЕНИЕ ИЗ GITHUB
#  Версия — в файле VERSION, суммы — в MANIFEST.txt.
#  Порядок: версия -> архив -> проверка сумм и синтаксиса -> бэкап -> замена.
# ============================================================
UPDATE_REPO="${UPDATE_REPO:-S-ker/lan-toolkit}"
UPDATE_BRANCH="${UPDATE_BRANCH:-main}"
LOCAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RAW_BASE="https://raw.githubusercontent.com/$UPDATE_REPO/$UPDATE_BRANCH"
TARBALL="https://codeload.github.com/$UPDATE_REPO/tar.gz/refs/heads/$UPDATE_BRANCH"

http_get() { # $1 = url, $2 = выходной файл (пусто = в stdout)
  if command -v curl >/dev/null 2>&1; then
    if [ -n "${2:-}" ]; then curl -fsSL --max-time 120 "$1" -o "$2"; else curl -fsSL --max-time 10 "$1"; fi
  elif command -v wget >/dev/null 2>&1; then
    if [ -n "${2:-}" ]; then wget -q -O "$2" "$1"; else wget -q -O - "$1"; fi
  else
    return 127
  fi
}

local_version() { [ -f "$LOCAL_DIR/VERSION" ] && tr -d ' \t\r\n' < "$LOCAL_DIR/VERSION" || echo "0.0.0"; }
remote_version() { http_get "$RAW_BASE/VERSION" 2>/dev/null | tr -d ' \t\r\n'; }

ver_newer() { # $1 новее $2 ?
  [ "$1" = "$2" ] && return 1
  local IFS='.'
  local r=($1) l=($2) i a b
  for i in 0 1 2; do
    a="${r[$i]:-0}"; b="${l[$i]:-0}"
    [ "$a" -gt "$b" ] 2>/dev/null && return 0
    [ "$a" -lt "$b" ] 2>/dev/null && return 1
  done
  return 1
}

do_update_check() {
  local quiet="${1:-0}" lv rv
  lv="$(local_version)"
  rv="$(remote_version)"
  if [ -z "$rv" ]; then
    [ "$quiet" != "1" ] && echo "  проверить не удалось (нет интернета?) — работаю как есть"
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
  if [ -z "$rv" ]; then err "не смог узнать версию на GitHub (интернет?)"; return 1; fi
  echo "  На GitHub          : $rv"
  if [ "$force" != "1" ] && ! ver_newer "$rv" "$lv"; then ok "обновление не нужно"; return 0; fi

  local tmp; tmp="$(mktemp -d)"
  echo "  Скачиваю архив..."
  if ! http_get "$TARBALL" "$tmp/lt.tar.gz"; then
    err "скачать не удалось (нет curl/wget или нет сети)"; rm -rf "$tmp"; return 1
  fi
  tar -xzf "$tmp/lt.tar.gz" -C "$tmp" || { err "архив не распаковался"; rm -rf "$tmp"; return 1; }
  local root; root="$(find "$tmp" -maxdepth 1 -type d ! -path "$tmp" | head -1)"
  [ -n "$root" ] || { err "пустой архив"; rm -rf "$tmp"; return 1; }

  echo "  Проверяю содержимое..."
  if ! http_get "$RAW_BASE/MANIFEST.txt" "$root/MANIFEST.txt"; then
    err "нет MANIFEST.txt — проверить целостность не могу, отменяю"; rm -rf "$tmp"; return 1
  fi
  if ! (cd "$root" && sha256sum -c MANIFEST.txt --quiet >/dev/null 2>&1); then
    err "суммы не сошлись — ничего не меняю"
    (cd "$root" && sha256sum -c MANIFEST.txt 2>&1 | grep -v ': OK$' | head -5)
    rm -rf "$tmp"; return 1
  fi
  ok "суммы сошлись"

  local f
  for f in lan-linux.sh lan-android.sh start-linux.sh; do
    if [ -f "$root/$f" ]; then
      bash -n "$root/$f" || { err "новый $f с ошибкой синтаксиса — отменяю"; rm -rf "$tmp"; return 1; }
    fi
  done

  local bk="$PEER_HOME/backup/$lv-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$bk"
  cp -a "$LOCAL_DIR"/. "$bk"/ 2>/dev/null
  rm -rf "$bk/.git"
  echo "  Бэкап: $bk"

  local n=0
  while IFS= read -r f; do
    case "$(basename "$f")" in .git*) continue ;; esac
    cp -f "$f" "$LOCAL_DIR/$(basename "$f")" && n=$((n+1))
  done < <(find "$root" -maxdepth 1 -type f)
  chmod +x "$LOCAL_DIR"/*.sh 2>/dev/null
  rm -rf "$tmp"
  peer_audit "update $lv -> $rv ($n файлов)"
  ok "обновлено до $rv (файлов: $n)"
  echo "  Откатить: bash $0 rollback"
  echo "  Вторую машину тоже обнови — иначе режим «партнёр» откажет по хешу."
}

do_rollback() {
  local base="$PEER_HOME/backup" last
  [ -d "$base" ] || { err "бэкапов нет"; return 1; }
  last="$(ls -1 "$base" | sort | tail -1)"
  [ -n "$last" ] || { err "бэкапов нет"; return 1; }
  hdr "Откат"
  echo "  Из: $base/$last"
  local n=0 f
  for f in "$base/$last"/*; do
    [ -f "$f" ] || continue
    cp -f "$f" "$LOCAL_DIR/$(basename "$f")" && n=$((n+1))
  done
  chmod +x "$LOCAL_DIR"/*.sh 2>/dev/null
  peer_audit "rollback из $last ($n файлов)"
  ok "восстановлено файлов: $n (версия $(local_version))"
}

make_manifest() {
  local names=(VERSION lan-win.ps1 lan-linux.sh lan-android.sh mcping.py start-linux.sh START-Windows.bat
               "НАЧАТЬ-Windows.bat" "НАЧАТЬ-Linux.desktop" README.md .gitattributes .gitignore)
  local n
  : > "$LOCAL_DIR/MANIFEST.txt"
  for n in "${names[@]}"; do
    [ -f "$LOCAL_DIR/$n" ] || continue
    printf '%s  %s\n' "$(sha256sum -- "$LOCAL_DIR/$n" | cut -d' ' -f1)" "$n" >> "$LOCAL_DIR/MANIFEST.txt"
  done
  ok "MANIFEST.txt обновлён"
}

case "${1:-setup}" in
  setup)  do_setup "${@:2}" ;;
  share)  do_share "${@:2}" ;;
  http)   do_http "${@:2}" ;;
  mount)  do_mount "${@:2}" ;;
  ssh)    do_ssh "${@:2}" ;;
  mc|minecraft) do_mc "${@:2}" ;;
  detect|lan)   do_detect ;;
  world)        do_world "${@:2}" ;;
  sync)         do_sync "${@:2}" ;;
  peer-serve)   peer_serve ;;
  peer-keygen)  peer_keygen ;;
  peer-add)     peer_add "${@:2}" ;;
  peer-list)    peer_list ;;
  peer-forget)  peer_forget "${@:2}" ;;
  peer-arm)     peer_arm "${@:2}" ;;
  peer-disarm)  peer_disarm ;;
  peer-bootstrap) peer_bootstrap "${@:2}" ;;
  peer-test)    peer_test "${@:2}" ;;
  peer-sync)    peer_sync "${@:2}" ;;
  peer-log)     peer_log ;;
  update)       do_update ;;
  update-check) do_update_check "${2:-0}" ;;
  update-manifest) make_manifest ;;
  rollback)     do_rollback ;;
  status) do_status ;;
  remove) do_remove "${@:2}" ;;
  *) echo "usage: $0 {setup|share|http|mount|ssh|mc [java|bedrock|firewall|join]|detect|world [list|push|pull|sync|backup]|sync <local> <remote> [sec]|peer-<keygen|add|list|forget|arm|disarm|bootstrap|test|sync|log|serve>|status|remove}"; exit 1 ;;
esac
