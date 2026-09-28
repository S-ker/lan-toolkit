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
  fw_open 445/tcp 139/tcp 137/udp 138/udp 22/tcp 5353/udp "$PORT/tcp"

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

case "${1:-setup}" in
  setup)  do_setup "${@:2}" ;;
  share)  do_share "${@:2}" ;;
  http)   do_http "${@:2}" ;;
  mount)  do_mount "${@:2}" ;;
  ssh)    do_ssh "${@:2}" ;;
  mc|minecraft) do_mc "${@:2}" ;;
  status) do_status ;;
  remove) do_remove "${@:2}" ;;
  *) echo "usage: $0 {setup|share|http|mount|ssh|mc [java|bedrock|firewall|join]|status|remove}"; exit 1 ;;
esac
