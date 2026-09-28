#!/usr/bin/env bash
# ============================================================
#  Двойной клик / запуск:  bash start-linux.sh
#  Простое меню для тех, кто не хочет помнить команды.
# ============================================================
DIR="$(cd "$(dirname "$0")" && pwd)"
S="$DIR/lan-linux.sh"
C_C="\033[36m"; C_G="\033[32m"; C_Y="\033[33m"; C_0="\033[0m"

ask_root() {   # $1 = команда
  sudo bash "$S" "$@"
}

while true; do
  clear 2>/dev/null
  echo ""
  echo -e "  ${C_C}==============================================================${C_0}"
  echo -e "  ${C_C}      ЛОКАЛЬНАЯ СЕТЬ + MINECRAFT   (Linux)                  ${C_0}"
  echo -e "  ${C_C}==============================================================${C_0}"
  echo ""
  echo "   1  Подготовить сеть (общая папка + видимость в сети)"
  echo "   2  Показать мои адреса и состояние"
  echo "   3  Раздать файлы через браузер (телефон/Windows откроет ссылку)"
  echo -e "   4  ${C_G}Minecraft: поднять сервер (Java / Paper)${C_0}"
  echo -e "   5  ${C_G}Minecraft: поднять Bedrock-сервер (для телефонов)${C_0}"
  echo -e "   6  ${C_G}Minecraft: показать адрес для друзей${C_0}"
  echo "   7  Подключиться к папке на Windows по IP"
  echo "   8  Открыть SSH (чтобы заходить с телефона/ПК)"
  echo "   9  Убрать все настройки этой программы"
  echo "   0  Выход"
  echo ""
  read -rp "  Введи цифру и нажми Enter: " c

  case "$c" in
    1) ask_root setup;  echo; read -rp "  Enter -> назад в меню" ;;
    2) bash "$S" status; echo; read -rp "  Enter -> назад в меню" ;;
    3) ask_root http ;;
    4) ask_root mc java; echo; read -rp "  Enter -> назад в меню" ;;
    5) ask_root mc bedrock; echo; read -rp "  Enter -> назад в меню" ;;
    6) bash "$S" mc join; echo; read -rp "  Enter -> назад в меню" ;;
    7)
       echo "  Пример: //192.168.1.50/LAN"
       read -rp "  Адрес папки: " r
       read -rp "  Логин Windows (Enter = Guest): " u
       [ -n "$u" ] || u=Guest
       read -rsp "  Пароль (можно пусто): " p; echo
       sudo bash "$S" mount "$r" "$u" "$p"
       echo; read -rp "  Enter -> назад в меню" ;;
    8) ask_root ssh; echo; read -rp "  Enter -> назад в меню" ;;
    9) ask_root remove; echo; read -rp "  Enter -> назад в меню" ;;
    0) exit 0 ;;
    *) echo "  Не понял. Введи цифру из списка."; sleep 2 ;;
  esac
done
