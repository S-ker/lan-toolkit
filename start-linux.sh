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
  echo -e "   7  ${C_G}Minecraft: найти запущенную игру и LAN-порт${C_0}"
  echo -e "   8  ${C_G}Minecraft: перенести/синхронизировать мир${C_0}"
  echo "   9  Двусторонняя общая папка (файлы туда-обратно)"
  echo "  10  Подключиться к папке на Windows по IP"
  echo "  11  Открыть SSH (чтобы заходить с телефона/ПК)"
  echo "  12  Убрать все настройки этой программы"
  echo -e "  13  ${C_Y}ПАРТНЁР по SSH: ключ, залить скрипты, проверить связь${C_0}"
  echo -e "  14  ${C_Y}Разрешить приём с другой машины на N минут (взвести)${C_0}"
  echo -e "  15  ${C_Y}Синхронизация с партнёром по SSH (обе стороны сами)${C_0}"
  echo "  16  Журнал удалённых действий"
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
    7) bash "$S" detect; echo; read -rp "  Enter -> назад в меню" ;;
    8)
       bash "$S" world list
       echo
       read -rp "  Имя мира (Enter = самый свежий): " w
       read -rp "  Общая папка другой машины (Enter = своя): " rd
       read -rp "  [1] отдать  [2] забрать  [3] синхронизировать (Enter=3): " m
       case "$m" in 1) m=push ;; 2) m=pull ;; *) m=sync ;; esac
       sudo bash "$S" world "$m" "$w" "${rd:-}"
       echo; read -rp "  Enter -> назад в меню" ;;
    9)
       read -rp "  Локальная папка (Enter = общая папка программы): " ld
       read -rp "  Папка на другом ПК/телефоне (например /mnt/lan или \\\\IP\\LAN): " rd
       read -rp "  Обновлять каждые N секунд? (Enter = один раз): " sec
       sudo bash "$S" sync "${ld:-}" "$rd" "${sec:-0}"
       echo; read -rp "  Enter -> назад в меню" ;;
    10)
       echo "  Пример: //192.168.1.50/LAN"
       read -rp "  Адрес папки: " r
       read -rp "  Логин Windows (Enter = Guest): " u
       [ -n "$u" ] || u=Guest
       read -rsp "  Пароль (можно пусто): " p; echo
       sudo bash "$S" mount "$r" "$u" "$p"
       echo; read -rp "  Enter -> назад в меню" ;;
    11) ask_root ssh; echo; read -rp "  Enter -> назад в меню" ;;
    12) ask_root remove; echo; read -rp "  Enter -> назад в меню" ;;
    13)
       echo "   1 — создать ключ тулкита (один раз)"
       echo "   2 — добавить партнёра по IP"
       echo "   3 — залить скрипты на партнёра"
       echo "   4 — проверить связь"
       echo "   5 — показать список партнёров"
       read -rp "  Цифра: " s
       case "$s" in
         1) bash "$S" peer-keygen ;;
         2) read -rp "  Имя партнёра: " n
            read -rp "  IP партнёра: " h
            read -rp "  Логин на партнёре (Enter = как тут): " u
            read -rp "  Порт SSH (Enter = 22): " pt
            read -rp "  Система: [1] Windows [2] Linux [3] Android (Enter=2): " pl
            case "$pl" in 1) pl=win ;; 3) pl=android ;; *) pl=linux ;; esac
            bash "$S" peer-add "$n" "$h" "${u:-$(whoami)}" "${pt:-22}" "$pl" ;;
         3) read -rp "  Имя партнёра: " n; bash "$S" peer-bootstrap "$n" ;;
         4) read -rp "  Имя партнёра: " n; bash "$S" peer-test "$n" ;;
         5) bash "$S" peer-list ;;
       esac
       echo; read -rp "  Enter -> назад в меню" ;;
    14)
       echo "  Придумай код (6+ символов) и скажи его тому, кто будет подключаться."
       read -rp "  Код: " t
       if [ -n "$t" ]; then
         read -rp "  На сколько минут (Enter = 30, максимум 240): " m
         read -rp "  Только один проход? [y/N]: " one
         read -rp "  Разрешить только с машины (Enter = любую): " fp
         args=(-t "$t" -m "${m:-30}")
         [ "$one" = "y" ] && args+=(--once)
         [ -n "$fp" ] && args+=(--fp "$fp")
         bash "$S" peer-arm "${args[@]}"
       fi
       echo; read -rp "  Enter -> назад в меню" ;;
    15)
       bash "$S" peer-list
       echo
       read -rp "  Имя партнёра: " n
       if [ -n "$n" ]; then
         read -rp "  Моя папка (Enter = общая папка программы/обмен): " ld
         read -rp "  Папка на партнёре (Enter = то же имя у него): " rd
         read -rp "  Обновлять каждые N секунд? (Enter = один раз): " sec
         read -rp "  Код, который сказал человек на той машине: " tok
         if [ -z "$tok" ]; then echo "  Без кода та машина откажет, если на ней так настроено."; fi
         TOKEN="$tok" sudo -E bash "$S" peer-sync "$n" "${ld:-}" "${rd:-}" "${sec:-0}"
       fi
       echo; read -rp "  Enter -> назад в меню" ;;
    16) bash "$S" peer-log; echo; read -rp "  Enter -> назад в меню" ;;
    0) exit 0 ;;
    *) echo "  Не понял. Введи цифру из списка."; sleep 2 ;;
  esac
done
