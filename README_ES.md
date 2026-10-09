# LAN Toolkit — red local Windows ⇄ Linux ⇄ Android + Minecraft

[Русский](README.md) · [English](README_EN.md) · [Deutsch](README_DE.md) · **Español** · [中文](README_ZH.md)

Conjunto de scripts para conectar ordenadores y un teléfono en una misma red local: carpeta
compartida (SMB), visibilidad en la red, SSH, intercambio de archivos a través del navegador,
punto de acceso móvil y servidor de Minecraft (Java y Bedrock).

> No es necesario introducir comandos: los archivos se inician con doble clic y todas las acciones
> se seleccionan con números en un menú en ruso.

---

## Novedades en la versión 1.6

- **Menú anidado.** Los elementos principales (red, dirección, compartir, conectar a una carpeta
  ajena, punto de acceso) están arriba; Minecraft, archivos/mundos, el socio por SSH, la actualización
  y el servicio están en secciones aparte. Todas las acciones se ejecutan **en la misma ventana** — sin
  ventanas extra y sin un nuevo «Pulsa Enter» tras cada acción.
- **Las ventanas ya no se cierran demasiado rápido.** La información (IP, estado) permanece en pantalla
  hasta que pulses Enter; en la línea de comandos es la opción `-Pause`.
- **El socio SSH se configura automáticamente.** «Socio SSH → 1» crea la clave, la instala en el
  segundo equipo (pide la contraseña una vez), sube los scripts, activa la recepción y comprueba el
  enlace. Antes se hacía manualmente.
- **Transferencia de mundos con selección automática.** «Minecraft → Transferir mundo» muestra los
  mundos encontrados y ofrece elegir el mundo y a dónde enviarlo/recogerlo (carpeta propia o `\\IP\LAN`).
- **La red se guarda y se restaura.** `setup` hace una instantánea de la configuración de red (perfiles,
  servicios, recursos compartidos) y `remove` la restaura.
- **El servidor de Minecraft se descarga solo.** Si falta `server.jar`, el menú ofrece descargar
  Vanilla / Paper / Fabric (se puede indicar con `-ServerType`).
- **Registro automático.** Todas las acciones se escriben en `~/.lan-toolkit/lan.log`; el registro está
  en la sección «Servicio».
- **Funciona como plugin de DSH.** En `dsh-plugin/` hay un plugin Host listo con herramientas
  `lan_toolkit_*` y la habilidad de agente `lan-toolkit`.

---

## Inicio rápido

### Windows

1. Inicie `НАЧАТЬ-Windows.bat` (o `START-Windows.bat`) con doble clic.
2. Confirme la solicitud de control de cuentas de usuario («Permitir que esta aplicación haga cambios») — «Sí».
3. En el menú que se abre, seleccione la opción **`1`** y pulse Enter: la red queda preparada.
   Minecraft es la sección **`6`** (servidor, dirección para amigos, transferencia de mundos).

### Linux

1. Coloque los archivos `start-linux.sh`, `lan-linux.sh` y `НАЧАТЬ-Linux.desktop` en un mismo directorio.
2. Inicie `НАЧАТЬ-Linux.desktop` con doble clic; cuando se solicite, permita la ejecución del archivo.
3. Introduzca la contraseña de administrador y seleccione la opción **`1`** en el menú.

Si el doble clic no funciona: abra el directorio en la terminal y ejecute `bash start-linux.sh`.

### Android (Termux)

1. Instale Termux desde **F-Droid**: la versión de Play Market está desactualizada.
2. Copie el directorio `lan-toolkit` al dispositivo (o descárguelo a través del navegador).
3. En Termux, ejecute una vez:

   ```
   cd ~/storage/downloads/lan-toolkit && bash lan-android.sh
   ```

   Después, seleccione las opciones del menú.

> El montaje directo de una carpeta de Windows en Android sin root es imposible. Para acceder a los
> archivos por SMB se utiliza un gestor de archivos de terceros, por ejemplo Cx File Explorer
> (Red → Nueva conexión → SMB, dirección `smb://<IP_ПК>/LAN`). Las demás funciones están disponibles
> a través de SSH y del navegador — aparecen en el menú.

---

## Composición del conjunto

| Archivo | Función | Inicio |
|---|---|---|
| `НАЧАТЬ-Windows.bat` / `START-Windows.bat` | menú para Windows | doble clic |
| `lan-win.ps1` | motor de Windows (también disponible manualmente) | `.\lan-win.ps1 setup` |
| `start-linux.sh` | menú para Linux | doble clic / `bash start-linux.sh` |
| `НАЧАТЬ-Linux.desktop` | acceso directo para doble clic en Linux | doble clic |
| `lan-linux.sh` | motor de Linux | `sudo bash lan-linux.sh setup` |
| `lan-android.sh` | menú y motor de Android (Termux) | `bash lan-android.sh` |
| `mcping.py` | ping de Minecraft, escaneo de subred, búsqueda de partidas LAN (Linux/Android) | se invoca desde los scripts |
| `VERSION` | versión actual (se muestra en el menú) | — |
| `MANIFEST.txt` | sumas de comprobación de todos los archivos (verificación de actualización) | — |
| `README.md` | documentación | — |

## Actualización

La versión actual se muestra en el encabezado del menú. Si en el repositorio se ha publicado una más
reciente, el menú muestra `>>> ДОСТУПНО ОБНОВЛЕНИЕ <<<`, y la actualización se inicia con la sección
**9 → 1** (Windows), **17** (Linux) o **14** (Android). Desde la línea de comandos:

```powershell
.\lan-win.ps1 update-check     # solo comprobar
.\lan-win.ps1 update           # descargar, verificar e instalar
.\lan-win.ps1 rollback         # restaurar la versión anterior desde la copia de seguridad
.\lan-win.ps1 no-update        # desactivar la comprobación al iniciar el menú
```
```bash
sudo bash lan-linux.sh update-check
sudo bash lan-linux.sh update
sudo bash lan-linux.sh rollback
```

Orden de las operaciones durante la actualización — **ninguna sustitución se realiza hasta que lo nuevo ha sido verificado**:

1. Se solicita la versión desde el archivo `VERSION` del repositorio.
2. Mediante la API de GitHub se determina el **commit exacto de la rama `main`** y los archivos se descargan según él.
   Así la caché de la CDN no puede entregar un conjunto de archivos de un commit más antiguo (se ha observado ese caso).
3. Se descarga `MANIFEST.txt` y se compara el **sha256 de cada archivo** (las sumas se calculan
   sin tener en cuenta los saltos de línea, por lo que Windows y Linux dan el mismo resultado).
4. Se comprueba la sintaxis de los nuevos scripts: `ParseFile` para PowerShell, `bash -n` para `.sh`.
5. Los archivos actuales se copian en `~/.lan-toolkit/backup/<версия>-<дата>/`.
   **La copia de seguridad es obligatoria:** si no se ha podido crear la copia, la actualización se cancela.
6. Solo después se sustituyen los archivos. Cualquier error en los pasos 1–4 → cancelación, el estado no cambia.

En Windows los archivos se descargan uno por uno, sin descomprimir el archivo comprimido: `tar.exe`
decodifica los nombres en cirílico (`НАЧАТЬ-Windows.bat`) como CP866 y crea nombres ilegibles.
En Linux y Android se utiliza el archivo comprimido de la rama — allí `tar` lee los nombres correctamente.

**Límites de la protección.** Los archivos y las sumas de comprobación provienen de una única fuente
(GitHub por HTTPS), por lo que esto protege contra cortes de conexión, daños en los archivos y errores
en los scripts, pero no contra la suplantación del servidor. Para una garantía total se utiliza la
instalación desde git con verificación de commits.

Notas:

* La comprobación de actualizaciones al iniciar el menú tarda unos 3 segundos y no interfiere en el trabajo;
  sin acceso a la red simplemente no muestra nada. Desactivación: `no-update` o `NOUPDATECHECK=1`.
* Después de actualizar, actualice también la segunda máquina: en el modo «socio» los hashes de los toolkits deben coincidir,
  de lo contrario la segunda parte rechazará la operación.
* `update-manifest` reconstruye `MANIFEST.txt` — se ejecuta después de modificar los scripts,
  de lo contrario la actualización en otras máquinas fallará por la discrepancia de las sumas.

## Matriz de conexiones

| De → A | Qué funciona | Cómo |
|---|---|---|
| **Win → Win** | Explorador, SMB | `\\ПК\LAN` en el Explorador |
| **Win → Linux** | SMB, SSH, HTTP | `\\IP\LAN`; `ssh user@IP`; `http://IP:8080` |
| **Linux → Win** | SMB (cifs), HTTP | menú Linux → opción 7 |
| **Win → Android** | SSH/SCP, HTTP | `scp -P 8022 user@IP:...`; `http://IP:8080` |
| **Android → Win** | SMB a través de GUI, HTTP, SSH | Cx File Explorer `smb://IP/LAN`; menú Android → 4 |
| **Android → Linux** | SSH, HTTP, SMB (GUI) | `ssh -p 8022 user@IP` |

## Minecraft en esta misma red

Java y Bedrock son **mundos distintos**: sin los plugins Geyser + Floodgate no se ven entre sí.

**Variante sin servidor (anfitrión — Windows).** En el juego: `Esc` → «Abrir para la red». Los demás
participantes se conectan por la IP del anfitrión. Limitación: el anfitrión debe permanecer en el juego.

**Servidor completo:**

| Lado | Acción |
|---|---|
| Windows | menú → **6** → **1** (solicita la cantidad de memoria en GB; si falta `server.jar`, ofrece descargar Vanilla/Paper/Fabric). El archivo `server.jar` se coloca en `%PUBLIC%\LANShare\minecraft` |
| Linux | menú → opción **4** (Java/Paper, se descarga automáticamente) u **5** (servidor Bedrock) |
| Android | menú → opción **6** (servidor en el teléfono, para 1–2 personas; antes `termux-wake-lock`) |

| Versión del juego | Dónde introducir la dirección |
|---|---|
| Java Edition | Multiplayer → Direct Connection → `<IP>:25565` |
| Bedrock (teléfono, Win-Store, consola) | Play → Servers → Add Server → `<IP>:19132` |

Particularidades:

- El puerto 25565 se requiere **tanto por TCP como por UDP**.
- Bedrock siempre es **UDP 19132**; la búsqueda automática de LAN en el teléfono no ve el PC, la dirección se introduce manualmente.
- Sin `eula=true` en `eula.txt` el servidor termina con error (los scripts crean el archivo por sí mismos).
- Cross-play: en el servidor Paper se colocan `Geyser-Spigot.jar` y `Floodgate.jar` en `plugins/`.
- Servidor en el teléfono: sin `termux-wake-lock` Termux se suspende y el servidor se apaga.

## Búsqueda de una partida en ejecución («Abrir para la red»)

No se trata de un servidor, sino de una sesión de juego normal: el script encuentra el proceso java
del cliente y su puerto de escucha, y después realiza un ping real de Minecraft — así se determinan
el mundo, la versión y la lista de jugadores.

```powershell
.\lan-win.ps1 detect
```

Ejemplo de salida (valores anonimizados):

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

El menú y la salida de esta herramienta están en ruso.

Cómo funciona: se utiliza el ping del protocolo Server List Ping (`0x00` handshake → `0x00` status →
JSON con el MOTD, la versión y la lista de jugadores), por lo que «el puerto está abierto» y «esto es
realmente Minecraft» no se confunden. El puerto de «Abrir para la red» es **aleatorio y cambia cada
vez**, elegirlo manualmente no tiene sentido — `detect` lo extrae del proceso.

Equivalentes:

- Linux: `sudo bash lan-linux.sh detect`
- Android (escaneo de subred + búsqueda de partidas LAN): `bash lan-android.sh scan`
- Utilidad independiente: `python3 mcping.py ping <IP> <порт>` / `scan <192.168.1>` / `listen`

Nota: los anuncios multicast `224.0.2.60:4445` (mediante ellos los clientes se ven entre sí en el menú
«Multijugador») a menudo son bloqueados por el cortafuegos de Windows y por los routers Wi-Fi. La
conexión directa por `<IP>:<порт>` funciona siempre, por lo que `detect` es el método principal, y no el multicast.

## Transferencia de mundos entre máquinas

Un mundo es un directorio con `level.dat` (además de `session.lock`, `region/`, `playerdata/`). Los
scripts lo sincronizan a través de la carpeta compartida en ambos sentidos, **según el principio
«el más reciente gana»** y con copia de seguridad automática antes de cada cambio.

```powershell
.\lan-win.ps1 world -WorldMode list                  # qué mundos hay y dónde
.\lan-win.ps1 world -WorldMode push  -World "имя" -Remote \\192.168.1.50\LAN\mcworlds
.\lan-win.ps1 world -WorldMode pull  -World "имя" -Remote \\192.168.1.50\LAN\mcworlds
.\lan-win.ps1 world -WorldMode sync  -World "имя" -Remote \\192.168.1.50\LAN\mcworlds
```
```bash
sudo bash lan-linux.sh world list
sudo bash lan-linux.sh world sync "имя мира" /mnt/lan/mcworlds
```

Protecciones:

- **El mundo está ocupado por el juego → la sincronización está prohibida.** `session.lock` se comprueba
  con una apertura exclusiva y además se verifica la presencia del proceso java del cliente: copiar un
  directorio abierto por el juego da garantizadamente un mundo dañado. La omisión solo es posible con
  `-Force` explícito (Windows) / `FORCE=1` (Linux).
- **Copia de seguridad antes de cada ejecución**: `_backups/<мир>-<дата>.zip` (Windows) o `.tar.gz` (Linux).
- **El modo predeterminado no elimina nada** (robocopy `/E /XO`, rsync `--update`): las eliminaciones
  no se propagan entre máquinas. La creación de espejo (`-Mirror` / `MIRROR=1`) existe,
  pero elimina archivos en ambos lados.
- El script de Windows encuentra los mundos de todos los lanzadores: Prism, MultiMC, el `.minecraft`
  vainilla, y también los mundos Bedrock (UWP, `levelname.txt` se lee como UTF-8).

## Intercambio bidireccional de carpetas

Carpeta compartida en funcionamiento permanente entre dos máquinas: los archivos llegan en ambos sentidos.

```powershell
.\lan-win.ps1 sync -Local "$env:USERPROFILE\Desktop\обмен" -Remote \\192.168.1.50\LAN\обмен -Watch 30
```
```bash
sudo bash lan-linux.sh sync /home/user/обмен /mnt/lan/обмен 30
bash lan-android.sh sync ~/storage/shared/Download user@192.168.1.20:/home/user/обмен 30
```

`-Watch 30` — una pasada cada 30 segundos (para detener, Ctrl+C); sin el número se realiza una sola
pasada. La lógica no elimina archivos; para un espejo completo se añaden `-Mirror` (Windows) o `MIRROR=1`.

## Modo «socio»: conexión remota a la segunda máquina

Modo de sincronización remota: **el iniciador se conecta a la segunda máquina por SSH y le envía una
solicitud para que ejecute su mitad de la sincronización.** En ambas máquinas debe encontrarse el mismo
toolkit (se verifica por el hash).

Esquema de funcionamiento: el iniciador, por SSH, ejecuta `peer-serve` en la segunda máquina, transmite
la solicitud por stdin, y la segunda parte **decide por sí misma si aceptarla** y realiza el trabajo
con sus propios medios — su carpeta compartida, su `robocopy`/`rsync`.

### Configuración (4 pasos)

```powershell
# 1) instalar el toolkit en AMBAS máquinas y crear la clave en la propia
.\lan-win.ps1 peer-keygen

# 2) indicar el socio y subirle los scripts
.\lan-win.ps1 peer-add -Peer pc2 -PeerHost 192.168.1.50 -PeerUser user -PeerPlatform win
.\lan-win.ps1 peer-bootstrap -Peer pc2

# 3) añadir la propia clave pública a la segunda máquina (véase la salida de peer-keygen)
#    Windows: C:\Users\<user>\.ssh\authorized_keys
#    Linux/Android: ssh-copy-id -i ~/.lan-toolkit/keys/id_ed25519.pub user@IP

# 4) EN LA SEGUNDA MÁQUINA, activar manualmente la recepción:
#    bash lan-linux.sh peer-arm -t мойКод123 -m 30
```

Comprobación: `.\lan-win.ps1 peer-test -Peer pc2`
Sincronización: `.\lan-win.ps1 peer-sync -Peer pc2 -Local "$env:USERPROFILE\Desktop\обмен" -RemoteDir /srv/lanshare/обмен -Watch 30`

Sin el paso 4 (la activación) la segunda máquina **rechazará** la solicitud — es el mecanismo de
protección principal. No se puede activar la recepción de forma remota: los comandos
`peer-arm`/`peer-disarm` no están en la lista blanca.

### Mecanismos de protección

| Protección | Cómo funciona |
|---|---|
| Acceso SSH | Se requiere un inicio de sesión por clave ya autorizado. La clave del toolkit la añade una persona en esa máquina. |
| Activación manual | Mientras no se ejecute `peer-arm` en la segunda máquina, cualquier solicitud recibe `denied`. |
| Token | Se compara SHA-256; no se almacena en texto claro en ningún lugar. Mínimo 6 caracteres. |
| Plazo | Máximo 240 minutos; después la recepción se cierra automáticamente. |
| Un solo uso | `--once` — la activación se consume tras la primera solicitud (se desactiva **antes** del trabajo, para que una interrupción de la conexión no deje el acceso abierto). |
| Vinculación al iniciador | `--fp "user@ПК"` — aceptar solo desde una máquina concreta. |
| Lista blanca | Solo se permiten `ping, hash, status, detect, world, sync`. Se prohíbe código arbitrario. |
| Verificación de scripts | El hash del toolkit debe coincidir en ambas máquinas. De lo contrario, rechazo (omisión: `-AllowVersionDrift` / `ALLOW_DRIFT=1`). |
| Registro | `~/.lan-toolkit/audit.log` — tanto las solicitudes exitosas como los rechazos con su motivo. |
| Revocación | `peer-disarm` cierra la recepción de inmediato; `peer-forget` elimina al socio. |

El estado (claves, lista de socios, activación, registro) se almacena **fuera** del toolkit —
en `~/.lan-toolkit`, por lo que no acaba ni en git ni en las copias de la carpeta de intercambio.

### Limitaciones del modo

- No activa la segunda máquina por sí mismo ni solicita contraseña — solo se utiliza un acceso
  SSH ya autorizado.
- No ejecuta comandos arbitrarios — solo las acciones de la lista blanca.
- No se registra en el inicio automático ni mantiene un canal permanente: una conexión SSH por solicitud.
- No almacena contraseñas: solo la clave SSH del toolkit.

### Ejemplos para Linux y Android

```bash
sudo bash lan-linux.sh peer-keygen
sudo bash lan-linux.sh peer-add pc2 192.168.1.50 user 22 win
sudo bash lan-linux.sh peer-bootstrap pc2
sudo bash lan-linux.sh peer-arm -t мойКод123 -m 30        # recepción en esta máquina
sudo bash lan-linux.sh peer-test pc2
sudo bash lan-linux.sh peer-sync pc2 /srv/lanshare/обмен /srv/lanshare/обмен 30
bash lan-android.sh peer-arm -t мойКод123 -m 30           # el teléfono como destino
bash lan-android.sh peer-sync pc  ~/storage/shared/lan  ~/lan
```

## Puertos

| Puerto | Protocolo | Finalidad |
|---|---|---|
| 445, 139 | TCP | SMB (recursos compartidos, archivos) |
| 137–138 | UDP | Nombres NetBIOS |
| 5357, 3702 | TCP/UDP | WSD (visibilidad en «Red» de Windows) |
| 5353 | UDP | mDNS (`.local`, Linux/Android) |
| 4445 | UDP | Multicast «Abrir para la red» (224.0.2.60) |
| 22 / 8022 | TCP | SSH (Linux / Android-Termux) |
| 22 | TCP | Servidor SSH en Windows (necesario para el modo «socio») |
| 8080 | TCP | Intercambio de archivos por HTTP (modificable) |
| 25565 | TCP+UDP | Minecraft Java |
| 19132, 19133 | UDP | Minecraft Bedrock |
| 4445–65535 | TCP | Puerto LAN del cliente («Abrir para la red», aleatorio) |

## Comandos

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
sudo bash lan-linux.sh setup            # todo a la vez
sudo bash lan-linux.sh mc java          # servidor Paper
sudo bash lan-linux.sh mc bedrock       # servidor Bedrock
sudo bash lan-linux.sh mount //192.168.1.50/LAN lan пароль
sudo bash lan-linux.sh remove
```

```bash
bash lan-android.sh setup
bash lan-android.sh mc join
bash lan-android.sh scan                # encontrar servidores/partidas LAN en la red
bash lan-android.sh world list
bash lan-android.sh sync ~/storage/shared/Download user@192.168.1.20:/home/user/обмен 30
bash lan-android.sh get http://192.168.1.50:8080/file.zip
```

Utilidad independiente (un solo comando, sin scripts):

```bash
python3 mcping.py ping 192.168.1.20 55534     # qué servidor hay en el puerto
python3 mcping.py scan 192.168.1              # quién hay en la red en 25565
python3 mcping.py listen 6                    # escuchar «Abrir para la red»
python3 mcping.py bedrock 192.168.1.20        # servidor Bedrock (UDP 19132)
```

## Parámetros

| Variable / parámetro | Dónde | Valor predeterminado |
|---|---|---|
| `-ShareName` / `SHARE_NAME` | win / linux | `LAN` |
| `-Path` / `SHARE_DIR` | win / linux | `C:\Users\Public\LANShare` / `/srv/lanshare` |
| `SMB_USER` / `SMB_PASS` | linux | `lan` / se genera |
| `-Port` / `PORT` | todos | `8080` |
| `-McPort` / `MC_PORT` | todos | `25565` |
| `-BedrockPort` | win | `19132` |
| `-WorldMode` / `world <режим>` | todos | `list` (además: `push`, `pull`, `sync`, `backup`) |
| `-World` | todos | el mundo más reciente |
| `-Watch` / `sync ... <сек>` | todos | `0` (una pasada) |
| `-Mirror` / `MIRROR=1` | todos | desactivado (modo con eliminación de archivos) |

## Diagnóstico

1. **No hay ping** → subredes distintas (`ipconfig` / `ip a`). Si el Wi-Fi es de invitados, los dispositivos
   están aislados: active el punto de acceso (menú de Windows, opción **5**) y conecte los demás a él.
2. **Hay ping, pero no se ve el recurso compartido** → cortafuegos: la opción 1 del menú de Windows abre las reglas necesarias.
3. **Se solicita contraseña** → se necesita una cuenta real de Windows (la política prohíbe una contraseña
   vacía en la red).
4. **Windows no ve Linux** → en Linux deben estar en ejecución `smbd`, `nmbd`, `avahi-daemon`
   (opción 2 del menú de Linux).
5. **Android no abre `smb://`** → Cx File Explorer / Material Files; o bien los archivos a través del
   navegador (`http` en el PC + `get` en el teléfono).
6. **Windows 11 24H2 exige la firma SMB** → en el cliente Linux `vers=3.0` (ya está en el script).

## Seguridad

- El recurso compartido es accesible a toda la red local; no se recomienda usarlo en Wi-Fi públicas.
- `remove` (sección **S** → **1** del menú) revierte los cambios realizados.
- La contraseña SMB en Linux se genera aleatoriamente y se muestra una sola vez — guárdela.
