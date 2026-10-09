# LAN Toolkit — 局域网 Windows ⇄ Linux ⇄ Android + Minecraft

[Русский](README.md) · [English](README_EN.md) · [Deutsch](README_DE.md) · [Español](README_ES.md) · **中文**

用于在同一局域网内连接计算机和手机的一组脚本：共享文件夹（SMB）、
网络可见性、SSH、通过浏览器交换文件、手机热点以及 Minecraft 服务器
（Java 和 Bedrock）。

> 无需输入命令：文件通过双击运行，所有操作都通过俄语菜单中的数字进行选择。

---

## 1.6 版本的新内容

- **嵌套菜单。** 主菜单项（网络、地址、共享、连接他人文件夹、热点）放在顶部；Minecraft、文件/世界、SSH 伙伴、更新和服务放在各自的子菜单中。所有操作都在**同一个窗口**内执行——不再弹出额外窗口，也不需要在每个操作后再次按 Enter。
- **窗口不再快速关闭。** 信息（IP、状态）会一直停留在屏幕上，直到你按 Enter；在命令行中对应 `-Pause` 参数。
- **SSH 伙伴自动配置。** “SSH 伙伴 → 1”会自动创建密钥、将其安装到第二台机器（只需输入一次密码）、上传脚本、启用接收并检查连接。之前这些都需要手动操作。
- **世界转移支持自动选择。** “Minecraft → 转移世界”会显示找到的世界，并让你选择世界以及发送/接收的位置（自己的文件夹或 `\\IP\LAN`）。
- **网络配置可保存并恢复。** `setup` 会保存网络配置快照（配置文件、服务、共享），`remove` 会将其恢复。
- **Minecraft 服务器自动下载。** 如果没有 `server.jar`，菜单会提供下载 Vanilla / Paper / Fabric（可通过 `-ServerType` 指定）。
- **自动日志。** 所有操作都会写入 `~/.lan-toolkit/lan.log`；日志位于“服务”部分。
- **可作为 DSH 插件使用。** `dsh-plugin/` 中包含一个现成的 Host 插件，提供 `lan_toolkit_*` 工具以及 `lan-toolkit` 代理技能。

---

## 快速开始

### Windows

1. 双击运行 `НАЧАТЬ-Windows.bat`（或 `START-Windows.bat`）。
2. 在用户账户控制提示（“是否允许此应用对你的设备进行更改”）中选择“是”。
3. 在打开的菜单中选择 **`1`** 并按 Enter：网络已准备就绪。
   Minecraft 是第 **`6`** 部分（服务器、好友地址、世界转移）。

### Linux

1. 将 `start-linux.sh`、`lan-linux.sh` 和 `НАЧАТЬ-Linux.desktop` 放入同一目录。
2. 双击运行 `НАЧАТЬ-Linux.desktop`；出现提示时允许执行该文件。
3. 输入管理员密码，然后在菜单中选择 **`1`**。

如果双击无效：在终端中打开该目录并执行 `bash start-linux.sh`。

### Android (Termux)

1. 从 **F-Droid** 安装 Termux：Play 商店中的版本已过时。
2. 将 `lan-toolkit` 目录复制到设备上（或通过浏览器下载）。
3. 在 Termux 中执行一次：

   ```
   cd ~/storage/downloads/lan-toolkit && bash lan-android.sh
   ```

   之后按菜单项进行选择。

> 在 Android 上直接挂载 Windows 共享文件夹（无 root）是不可能的。要通过 SMB 访问文件，
> 需使用第三方文件管理器，例如 Cx File Explorer
> （网络 → 新建连接 → SMB，地址 `smb://<IP_ПК>/LAN`）。其余功能
> 可通过 SSH 和浏览器使用——它们都在菜单中。

---

## 套件组成

| 文件 | 用途 | 启动方式 |
|---|---|---|
| `НАЧАТЬ-Windows.bat` / `START-Windows.bat` | Windows 菜单 | 双击 |
| `lan-win.ps1` | Windows 引擎（也可手动使用） | `.\lan-win.ps1 setup` |
| `start-linux.sh` | Linux 菜单 | 双击 / `bash start-linux.sh` |
| `НАЧАТЬ-Linux.desktop` | Linux 中用于双击的快捷方式 | 双击 |
| `lan-linux.sh` | Linux 引擎 | `sudo bash lan-linux.sh setup` |
| `lan-android.sh` | Android（Termux）菜单与引擎 | `bash lan-android.sh` |
| `mcping.py` | Minecraft ping、子网扫描、查找局域网游戏（Linux/Android） | 由脚本调用 |
| `VERSION` | 当前版本（显示在菜单中） | — |
| `MANIFEST.txt` | 所有文件的校验和（更新校验） | — |
| `README.md` | 文档 | — |

## 更新

当前版本显示在菜单标题中。如果仓库中发布了更新的版本，
菜单会输出 `>>> ДОСТУПНО ОБНОВЛЕНИЕ <<<`，更新通过第 **9 → 1** 部分（Windows）、
**17**（Linux）或 **14**（Android）启动。从命令行：

```powershell
.\lan-win.ps1 update-check     # 仅检查
.\lan-win.ps1 update           # 下载、校验并安装
.\lan-win.ps1 rollback         # 从备份恢复上一个版本
.\lan-win.ps1 no-update        # 关闭菜单启动时的检查
```
```bash
sudo bash lan-linux.sh update-check
sudo bash lan-linux.sh update
sudo bash lan-linux.sh rollback
```

更新时的操作顺序——**在新文件通过校验之前，不会执行任何替换**：

1. 从仓库中的 `VERSION` 文件请求版本号。
2. 通过 GitHub API 确定 **`main` 分支的确切提交**，并按该提交下载文件。
   这样 CDN 缓存就无法返回基于更早提交的一组文件（这种情况曾出现过）。
3. 下载 `MANIFEST.txt`，核对**每个文件的 sha256**（计算校验和时
   忽略换行符差异，因此 Windows 和 Linux 得到相同结果）。
4. 检查新脚本的语法：PowerShell 使用 `ParseFile`，`.sh` 使用 `bash -n`。
5. 将当前文件复制到 `~/.lan-toolkit/backup/<версия>-<дата>/`。
   **备份是必须的：** 如果无法创建副本，更新将被取消。
6. 只有在此之后才替换文件。第 1–4 步中的任何错误 → 取消，状态不变。

在 Windows 上，文件按名称逐个下载，不展开归档：`tar.exe` 会将西里尔字母
名称（`НАЧАТЬ-Windows.bat`）按 CP866 解码并生成不可读的名称。在 Linux 和 Android
上使用分支归档——那里的 `tar` 能正确读取名称。

**防护边界。** 文件和校验和来自同一来源（通过 HTTPS 的 GitHub），
因此这可以防止连接中断、文件损坏和脚本错误，但不能防止服务器被替换。
如需完全保证，请使用带提交校验的 git 安装。

说明：

* 菜单启动时的更新检查约需 3 秒，不会影响使用；
  在无网络访问时它不会输出任何内容。关闭方式：`no-update` 或 `NOUPDATECHECK=1`。
* 更新后也要更新第二台机器：在“伙伴”模式下两个工具包的哈希必须一致，
  否则第二方会拒绝。
* `update-manifest` 会重新生成 `MANIFEST.txt`——在修改脚本后执行，
  否则其他机器的更新会因校验和不一致而失败。

## 连接组合矩阵

| 从 → 到 | 可用功能 | 方式 |
|---|---|---|
| **Win → Win** | 资源管理器、SMB | 在资源管理器中输入 `\\ПК\LAN` |
| **Win → Linux** | SMB、SSH、HTTP | `\\IP\LAN`；`ssh user@IP`；`http://IP:8080` |
| **Linux → Win** | SMB (cifs)、HTTP | Linux 菜单 → 第 7 项 |
| **Win → Android** | SSH/SCP、HTTP | `scp -P 8022 user@IP:...`；`http://IP:8080` |
| **Android → Win** | 通过 GUI 使用 SMB、HTTP、SSH | Cx File Explorer `smb://IP/LAN`；Android 菜单 → 4 |
| **Android → Linux** | SSH、HTTP、SMB (GUI) | `ssh -p 8022 user@IP` |

## 同一网络中的 Minecraft

Java 和 Bedrock——**是两个不同的世界**：如果不使用 Geyser + Floodgate 插件，它们彼此看不到。

**无服务器的方案（主机为 Windows）。** 在游戏中：`Esc` → “对局域网开放”。其他
参与者通过主机的 IP 连接。限制：主机必须保持游戏运行。

**完整服务器：**

| 端 | 操作 |
|---|---|
| Windows | 菜单 → **6** → **1**（会询问内存大小，单位 GB；如果没有 `server.jar`，会提供下载 Vanilla/Paper/Fabric）。`server.jar` 文件放在 `%PUBLIC%\LANShare\minecraft` |
| Linux | 菜单 → 第 **4** 项（Java/Paper，自动下载）或 **5**（Bedrock 服务器） |
| Android | 菜单 → 第 **6** 项（手机上的服务器，适合 1–2 人；需先执行 `termux-wake-lock`） |

| 游戏版本 | 地址输入位置 |
|---|---|
| Java Edition | Multiplayer → Direct Connection → `<IP>:25565` |
| Bedrock（手机、Win-Store、游戏主机） | Play → Servers → Add Server → `<IP>:19132` |

注意事项：

- 端口 25565 **TCP 和 UDP 都需要**。
- Bedrock 始终使用 **UDP 19132**；手机上的局域网自动发现看不到 PC，地址需手动输入。
- 如果 `eula.txt` 中没有 `eula=true`，服务器会报错退出（脚本会自动创建该文件）。
- 跨平台联机：将 `Geyser-Spigot.jar` 和 `Floodgate.jar` 放入 Paper 服务器的 `plugins/`。
- 手机服务器：不执行 `termux-wake-lock`，Termux 会休眠，服务器会断开。

## 查找正在运行的游戏（“对局域网开放”）

这里说的不是服务器，而是普通的游戏会话：脚本会找到客户端的 java 进程及其
监听端口，然后执行真正的 Minecraft ping——由此确定世界、版本
和玩家列表。

```powershell
.\lan-win.ps1 detect
```

输出示例（数值已匿名化）：

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

本工具包的菜单和输出均为俄语。

工作原理：使用 Server List Ping 协议 ping（`0x00` handshake → `0x00` status →
含 MOTD、版本和玩家列表的 JSON），因此不会把“端口已打开”和“这确实是 Minecraft”
混为一谈。“对局域网开放”的端口**是随机的，并且每次都会变化**，手动
猜测没有意义——`detect` 会从进程中提取它。

同类命令：

- Linux：`sudo bash lan-linux.sh detect`
- Android（扫描子网 + 查找局域网游戏）：`bash lan-android.sh scan`
- 独立工具：`python3 mcping.py ping <IP> <порт>` / `scan <192.168.1>` / `listen`

注意：多播公告 `224.0.2.60:4445`（客户端通过它们在
“多人游戏”菜单中互相看到）经常被 Windows 防火墙和 Wi-Fi 路由器拦截。通过
`<IP>:<порт>` 直接连接始终有效，因此 `detect` 是主要方式，而不是多播。

## 在机器之间迁移世界

世界是一个包含 `level.dat` 的目录（以及 `session.lock`、`region/`、`playerdata/`）。脚本
通过共享文件夹在双向同步它，**按“较新者胜出”的原则**，
并在每次更改前自动备份。

```powershell
.\lan-win.ps1 world -WorldMode list                  # 有哪些世界以及它们在哪里
.\lan-win.ps1 world -WorldMode push  -World "имя" -Remote \\192.168.1.50\LAN\mcworlds
.\lan-win.ps1 world -WorldMode pull  -World "имя" -Remote \\192.168.1.50\LAN\mcworlds
.\lan-win.ps1 world -WorldMode sync  -World "имя" -Remote \\192.168.1.50\LAN\mcworlds
```
```bash
sudo bash lan-linux.sh world list
sudo bash lan-linux.sh world sync "имя мира" /mnt/lan/mcworlds
```

防护措施：

- **世界被游戏占用 → 禁止同步。** `session.lock` 通过独占打开进行
  检查，另外还检查客户端 java 进程是否存在：复制被游戏打开的目录
  必定会产生损坏的世界。绕过方式仅为显式的 `-Force`
  （Windows）/ `FORCE=1`（Linux）。
- **每次运行前备份**：`_backups/<мир>-<дата>.zip`（Windows）或 `.tar.gz`（Linux）。
- **默认模式不删除任何内容**（robocopy `/E /XO`，rsync `--update`）：删除操作
  不会在机器之间传播。镜像模式（`-Mirror` / `MIRROR=1`）存在，
  但它会删除两侧的文件。
- Windows 脚本能找到所有启动器的世界：Prism、MultiMC、原版 `.minecraft`，
  以及 Bedrock 世界（UWP，`levelname.txt` 按 UTF-8 读取）。

## 双向文件夹交换

在两台机器之间持续运行的共享文件夹：文件可双向传输。

```powershell
.\lan-win.ps1 sync -Local "$env:USERPROFILE\Desktop\обмен" -Remote \\192.168.1.50\LAN\обмен -Watch 30
```
```bash
sudo bash lan-linux.sh sync /home/user/обмен /mnt/lan/обмен 30
bash lan-android.sh sync ~/storage/shared/Download user@192.168.1.20:/home/user/обмен 30
```

`-Watch 30`——每 30 秒执行一次（停止方式为 Ctrl+C）；不带数字则只执行一次。
逻辑中不含删除；要完全镜像需添加 `-Mirror`（Windows）或 `MIRROR=1`。

## “伙伴”模式：远程连接到第二台机器

远程同步模式：**发起方通过 SSH 连接到第二台机器，并向其发送执行其那一半同步的
请求。** 两台机器上都必须有同一套
工具包（通过哈希校验）。

工作流程：发起方通过 SSH 在第二台机器上启动 `peer-serve`，将请求传入 stdin，
而第二方**自行决定是否接受它**，并用自己的方式完成工作——
自己的共享、自己的 `robocopy`/`rsync`。

### 配置（4 步）

```powershell
# 1) 在两台机器上安装工具包，在本机生成密钥
.\lan-win.ps1 peer-keygen

# 2) 指定伙伴并将脚本推送到它那里
.\lan-win.ps1 peer-add -Peer pc2 -PeerHost 192.168.1.50 -PeerUser user -PeerPlatform win
.\lan-win.ps1 peer-bootstrap -Peer pc2

# 3) 将自己的公钥添加到第二台机器（参见 peer-keygen 的输出）
#    Windows: C:\Users\<user>\.ssh\authorized_keys
#    Linux/Android: ssh-copy-id -i ~/.lan-toolkit/keys/id_ed25519.pub user@IP

# 4) 在第二台机器上手动启用接收：
#    bash lan-linux.sh peer-arm -t мойКод123 -m 30
```

检查：`.\lan-win.ps1 peer-test -Peer pc2`
同步：`.\lan-win.ps1 peer-sync -Peer pc2 -Local "$env:USERPROFILE\Desktop\обмен" -RemoteDir /srv/lanshare/обмен -Watch 30`

没有第 4 步（启用），第二台机器会**拒绝**——这是主要的防护机制。
无法远程启用接收：`peer-arm`/`peer-disarm` 命令不在白名单中。

### 防护机制

| 防护 | 工作机制 |
|---|---|
| SSH 访问 | 需要已授权的密钥登录。工具包的密钥由那台机器上的人添加。 |
| 手动启用 | 在第二台机器上未执行 `peer-arm` 之前，任何请求都会得到 `denied`。 |
| 令牌 | 比较 SHA-256；不以明文形式存储在任何地方。至少 6 个字符。 |
| 有效期 | 最长 240 分钟，之后接收会自动关闭。 |
| 一次性 | `--once`——启用状态在第一次请求后即失效（在**工作开始之前**就消费掉，以免连接中断后仍保留访问权限）。 |
| 绑定发起方 | `--fp "user@ПК"`——只接受来自某一台特定机器的请求。 |
| 白名单 | 仅允许 `ping, hash, status, detect, world, sync`。禁止任意代码。 |
| 脚本校验 | 两台机器上的工具包哈希必须一致。否则拒绝（绕过：`-AllowVersionDrift` / `ALLOW_DRIFT=1`）。 |
| 日志 | `~/.lan-toolkit/audit.log`——成功请求和带原因的拒绝都会记录。 |
| 撤销 | `peer-disarm` 立即关闭接收；`peer-forget` 删除伙伴。 |

状态（密钥、伙伴列表、启用状态、日志）存储在工具包**之外**——
位于 `~/.lan-toolkit`，因此既不会进入 git，也不会进入共享文件夹的副本。

### 模式的限制

- 不会自行启用第二台机器，也不会索要密码——只使用已经
  授权的 SSH 访问。
- 不执行任意命令——只执行白名单中的操作。
- 不写入自启动，也不保持常驻通道：每个请求使用一次 SSH 连接。
- 不存储密码：只保存工具包的 SSH 密钥。

### Linux 和 Android 示例

```bash
sudo bash lan-linux.sh peer-keygen
sudo bash lan-linux.sh peer-add pc2 192.168.1.50 user 22 win
sudo bash lan-linux.sh peer-bootstrap pc2
sudo bash lan-linux.sh peer-arm -t мойКод123 -m 30        # 在本机接收
sudo bash lan-linux.sh peer-test pc2
sudo bash lan-linux.sh peer-sync pc2 /srv/lanshare/обмен /srv/lanshare/обмен 30
bash lan-android.sh peer-arm -t мойКод123 -m 30           # 手机作为目标
bash lan-android.sh peer-sync pc  ~/storage/shared/lan  ~/lan
```

## 端口

| 端口 | 协议 | 用途 |
|---|---|---|
| 445, 139 | TCP | SMB（共享、文件） |
| 137–138 | UDP | NetBIOS 名称 |
| 5357, 3702 | TCP/UDP | WSD（Windows“网络”中的可见性） |
| 5353 | UDP | mDNS（`.local`，Linux/Android） |
| 4445 | UDP | “对局域网开放”多播（224.0.2.60） |
| 22 / 8022 | TCP | SSH（Linux / Android-Termux） |
| 22 | TCP | Windows 上的 SSH 服务器（“伙伴”模式需要） |
| 8080 | TCP | HTTP 文件交换（可更改） |
| 25565 | TCP+UDP | Minecraft Java |
| 19132, 19133 | UDP | Minecraft Bedrock |
| 4445–65535 | TCP | 客户端的局域网端口（“对局域网开放”，随机） |

## 命令

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
sudo bash lan-linux.sh setup            # 一次完成全部
sudo bash lan-linux.sh mc java          # Paper 服务器
sudo bash lan-linux.sh mc bedrock       # Bedrock 服务器
sudo bash lan-linux.sh mount //192.168.1.50/LAN lan пароль
sudo bash lan-linux.sh remove
```

```bash
bash lan-android.sh setup
bash lan-android.sh mc join
bash lan-android.sh scan                # 在网络中查找服务器/局域网游戏
bash lan-android.sh world list
bash lan-android.sh sync ~/storage/shared/Download user@192.168.1.20:/home/user/обмен 30
bash lan-android.sh get http://192.168.1.50:8080/file.zip
```

独立工具（单条命令，无需脚本）：

```bash
python3 mcping.py ping 192.168.1.20 55534     # 端口上是什么服务器
python3 mcping.py scan 192.168.1              # 谁在 25565 上
python3 mcping.py listen 6                    # 监听“对局域网开放”
python3 mcping.py bedrock 192.168.1.20        # Bedrock 服务器（UDP 19132）
```

## 参数

| 变量 / 参数 | 位置 | 默认值 |
|---|---|---|
| `-ShareName` / `SHARE_NAME` | win / linux | `LAN` |
| `-Path` / `SHARE_DIR` | win / linux | `C:\Users\Public\LANShare` / `/srv/lanshare` |
| `SMB_USER` / `SMB_PASS` | linux | `lan` / 自动生成 |
| `-Port` / `PORT` | 全部 | `8080` |
| `-McPort` / `MC_PORT` | 全部 | `25565` |
| `-BedrockPort` | win | `19132` |
| `-WorldMode` / `world <режим>` | 全部 | `list`（还有：`push`、`pull`、`sync`、`backup`） |
| `-World` | 全部 | 最新的世界 |
| `-Watch` / `sync ... <сек>` | 全部 | `0`（单次执行） |
| `-Mirror` / `MIRROR=1` | 全部 | 关闭（带删除文件的模式） |

## 诊断

1. **无法 ping 通** → 处于不同子网（`ipconfig` / `ip a`）。如果 Wi-Fi 是访客网络，设备
   之间相互隔离：请开启热点（Windows 菜单第 **5** 项）并将其他设备连接到它。
2. **能 ping 通，但看不到共享** → 防火墙：Windows 菜单第 1 项会打开所需的规则。
3. **提示输入密码** → 需要真实的 Windows 账户（空密码在网络上
   会被策略禁止）。
4. **Windows 看不到 Linux** → 在 Linux 上必须运行 `smbd`、`nmbd`、`avahi-daemon`
   （Linux 菜单第 2 项）。
5. **Android 无法打开 `smb://`** → Cx File Explorer / Material Files；或者通过
   浏览器传文件（PC 上使用 `http` + 手机上使用 `get`）。
6. **Windows 11 24H2 要求 SMB 签名** → 在 Linux 客户端上使用 `vers=3.0`（脚本中已包含）。

## 安全

- 共享对整个局域网可见；不建议在公共 Wi-Fi 中使用。
- `remove`（菜单第 **S** → **1** 部分）会回滚所做的更改。
- Linux 上的 SMB 密码是随机生成的，并且只输出一次——请保存它。
