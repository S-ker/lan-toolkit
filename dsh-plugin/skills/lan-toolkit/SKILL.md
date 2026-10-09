---
name: lan-toolkit
description: Use when the user asks about the LAN Toolkit — sharing files/folders over the local network (Windows↔Windows↔Linux↔Android), a Minecraft server or world transfer, an SSH peer (partner) setup/sync, or network status/addresses on this Windows machine. The plugin exposes `lan_toolkit_*` tools that run the lan-win.ps1 script.
---

# LAN Toolkit

Кросс-платформенный помощник для локальной сети на этой Windows-машине. Плагин
даёт инструменты `lan_toolkit_*`, которые запускают `lan-win.ps1`.

## Инструменты

| Инструмент | Что делает | Нужны права админа? |
|---|---|---|
| `lan_toolkit_status` | IP-адреса, имя ПК, профиль сети, Wi-Fi (и предупреждение про AP-изоляцию), SMB-шары, службы | нет |
| `lan_toolkit_mc_address` | Адрес Minecraft для друзей (IP + порт) | нет |
| `lan_toolkit_worlds` | Найти миры Minecraft (Java/Bedrock), их путь, размер, дата | нет |
| `lan_toolkit_peer_list` | Список SSH-партнёров и их состояние | нет |
| `lan_toolkit_peer_test` | Проверить SSH-связь с партнёром | нет |
| `lan_toolkit_peer_setup` | Полностью настроить партнёра автоматически (ключ + ключ на нём + скрипты + взвод) | нет |
| `lan_toolkit_peer_sync` | Двусторонняя синхронизация папки с партнёром по SSH | нет |
| `lan_toolkit_setup` | Подготовить сеть (профиль Private, firewall, SMB-шара) | **да** |
| `lan_toolkit_http` | Раздать папку через браузер (http://IP:порт) | **да** |

## Правила использования

1. **Сначала читай, потом меняй.** Для вопросов «какой у меня IP / как подключиться»
   вызывай `lan_toolkit_status` или `lan_toolkit_mc_address`. Не трогай сеть без явной просьбы.

2. **Действия с правами админа** (`lan_toolkit_setup`, `lan_toolkit_http`, а также
   world transfer в push/pull/sync) при вызове из агента вернут сообщение
   «требует прав администратора». Не пытайся обойти это. Вместо этого скажи пользователю
   запустить меню: `.\lan-win.ps1` (или двойной клик `start.bat`) и выбрать нужный пункт.
   Меню само попросит UAC.

3. **Смена мира Minecraft.** `lan_toolkit_worlds` показывает миры. Перенос между машинами
   требует прав админа (общая папка) — направь пользователя в меню → Minecraft →
   «Перенести/синхронизировать мир», где мир и машина выбираются автоматически.

4. **SSH-партнёр.** Это способ синхронизироваться с Linux/Android/Windows по SSH без
   ввода пароля каждый раз. `lan_toolkit_peer_setup` делает всё: ключ → установка ключа
   (попросит пароль один раз) → заливка скриптов → взвод приёма → проверка. Потом
   `lan_toolkit_peer_sync` синхронизирует папки. Перед синхронизацией зови `lan_toolkit_peer_test`.

5. **Не запускай интерактивное меню через инструменты.** Инструменты передают `-NoElevate`,
   поэтому интерактивные вопросы (Read-Host) не покажутся. Если пользователю нужен
   интерактив (выбор сервера, порт, имя мира) — направь его в меню скрипта.

6. **Безопасность приёма.** Чтобы другая машина могла попросить синхронизацию, на ней
   должен быть «взведён» приём (`peer-arm -Token XXX -Minutes 30`). Это делается вручную
   на той машине, удалённо взвести нельзя.

## Типовые сценарии

- «Как мне дать файлы с этого ПК?» → `lan_toolkit_status` (узнать IP), затем направить
  в меню для `setup` + `http`.
- «Друзья не могут зайти в Minecraft» → `lan_toolkit_mc_address`, `lan_toolkit_status`.
- «Синхронизируй папку с моим ноутбуком» → `lan_toolkit_peer_list`, затем
  `lan_toolkit_peer_test`, затем `lan_toolkit_peer_sync`.
- «Где мой мир?» → `lan_toolkit_worlds`.
