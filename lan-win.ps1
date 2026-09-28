<#
.SYNOPSIS
  LAN Toolkit — сторона Windows. Поднимает SMB-шару, сеть Private, firewall,
  быстрый HTTP-обмен, мобильный хот-спот и монтирование чужих шар.

.DESCRIPTION
  Связки: Win<->Win, Win<->Linux, Win<->Android.
  Требует прав администратора (скрипт сам перезапустится через UAC).

.EXAMPLES
  .\lan-win.ps1 setup
  .\lan-win.ps1 setup -Path D:\Share -ShareName LAN
  .\lan-win.ps1 http -Port 8080
  .\lan-win.ps1 hotspot -On
  .\lan-win.ps1 mount -Remote \\192.168.1.50\LAN -User lan
  .\lan-win.ps1 status
  .\lan-win.ps1 remove
#>
[CmdletBinding()]
param(
  [ValidateSet('setup','status','http','hotspot','mount','unmount','remove','minecraft','mc','menu','detect','world','sync',
               'peer-keygen','peer-add','peer-list','peer-forget','peer-arm','peer-disarm','peer-test','peer-bootstrap',
               'peer-run','peer-sync','peer-serve','peer-log',
               'update','update-check','update-manifest','rollback','no-update')]
  [string]$Action = 'menu',

  [string]$ShareName = 'LAN',
  [string]$Path      = "$env:PUBLIC\LANShare",
  [string]$Remote    = '',        # \\IP\Share для mount
  [string]$User      = '',        # логин на удалённой машине
  [string]$Drive     = 'Z',
  [int]   $Port      = 8080,
  [string]$McDir     = '',        # папка сервера Minecraft
  [string]$McMem     = '2G',      # память для Java-сервера
  [int]   $McPort    = 25565,     # Java Edition
  [int]   $BedrockPort = 19132,   # Bedrock Edition (UDP)
  [string]$World     = '',        # имя мира для синхронизации
  [ValidateSet('list','push','pull','sync','backup')]
  [string]$WorldMode = 'list',    # что делать с миром
  [string]$Local     = '',        # локальная папка для двустороннего обмена
  [int]   $Watch     = 0,         # секунд между проходами (0 = один проход)
  [switch]$Mirror,
  [switch]$Force,
  [switch]$NoBackup,
  # --- peer (удалённая синхронизация) ---
  [string]$Peer     = '',
  [string]$PeerHost = '',
  [string]$PeerUser = '',
  [int]   $PeerPort = 22,
  [ValidateSet('win','linux','android')]
  [string]$PeerPlatform = 'linux',
  [string]$PeerToolkit = 'lan-toolkit',
  [string]$Token    = '',
  [int]   $Minutes  = 30,
  [string]$Cmd      = '',
  [string]$RemoteDir = '',
  [string]$AllowFp  = '',
  [string]$RequestFile = '',
  [switch]$Once,
  [switch]$AllowVersionDrift,
  # --- автообновление ---
  [string]$UpdateRepo = 'S-ker/lan-toolkit',
  [string]$UpdateBranch = 'main',
  [switch]$NoUpdateCheck,
  [switch]$On
)

$ErrorActionPreference = 'Continue'

# ---------- self-elevate ----------
function Test-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
}
if (-not (Test-Admin) -and $Action -in 'setup','hotspot','mount','unmount','remove','http','minecraft') {
  Write-Host "" ; Write-Host "  Сейчас Windows спросит разрешение — нажми ДА." -ForegroundColor Yellow
  $exe = (Get-Process -Id $PID).Path
  $arg = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Action $Action " +
         "-ShareName `"$ShareName`" -Path `"$Path`" -Port $Port -Drive $Drive"
  if ($Remote) { $arg += " -Remote `"$Remote`"" }
  if ($User)   { $arg += " -User `"$User`"" }
  if ($McDir)  { $arg += " -McDir `"$McDir`" -McMem `"$McMem`" -McPort $McPort" }
  if ($World)  { $arg += " -World `"$World`" -WorldMode $WorldMode" }
  if ($Local)  { $arg += " -Local `"$Local`"" }
  if ($Watch)  { $arg += " -Watch $Watch" }
  if ($Mirror) { $arg += " -Mirror" }
  if ($Force)  { $arg += " -Force" }
  if ($NoBackup) { $arg += " -NoBackup" }
  if ($On)     { $arg += " -On" }
  Start-Process -FilePath $exe -Verb RunAs -ArgumentList $arg
  exit
}

# ---------- helpers ----------
function Get-LanIP {
  Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object {
      $_.IPAddress -notmatch '^(127\.|169\.254\.)' -and
      $_.PrefixOrigin -ne 'WellKnown'
    } |
    Select-Object -ExpandProperty IPAddress -Unique
}

function Show-IP {
  $ips = Get-LanIP
  if (-not $ips) { Write-Host "  (нет активных IPv4 интерфейсов)" -ForegroundColor Red; return }
  foreach ($ip in $ips) { Write-Host "  -> $ip" -ForegroundColor Green }
}

function Set-PrivateNet {
  Get-NetConnectionProfile -ErrorAction SilentlyContinue | ForEach-Object {
    if ($_.NetworkCategory -ne 'Private') {
      try {
        Set-NetConnectionProfile -InterfaceIndex $_.InterfaceIndex -NetworkCategory Private
        Write-Host "  [+] '$($_.Name)' -> Private"
      } catch { Write-Host "  [!] не смог переключить '$($_.Name)'" -ForegroundColor Yellow }
    }
  }
}

function Add-FwRule([string]$name, [string]$proto, [string]$ports) {
  if (Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue) { return }
  New-NetFirewallRule -DisplayName $name -Direction Inbound -Action Allow `
    -Protocol $proto -LocalPort $ports -Profile Any -ErrorAction SilentlyContinue | Out-Null
  if (Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue) {
    Write-Host "  [+] firewall: $name ($proto/$ports)"
  } elseif (Test-Admin) {
    Write-Host "  [!] не удалось создать правило firewall: $name" -ForegroundColor Yellow
  }
}

function Open-Firewall {
  Enable-NetFirewallRule -DisplayGroup 'File and Printer Sharing' -ErrorAction SilentlyContinue
  Enable-NetFirewallRule -DisplayGroup 'Network Discovery'       -ErrorAction SilentlyContinue
  Add-FwRule 'LAN Toolkit SMB'      'TCP' '445,139'
  Add-FwRule 'LAN Toolkit NetBIOS'  'UDP' '137,138'
  Add-FwRule 'LAN Toolkit WSD'      'TCP' '5357'
  Add-FwRule 'LAN Toolkit WSD-UDP'  'UDP' '3702'
  Add-FwRule 'LAN Toolkit mDNS'     'UDP' '5353'
  Add-FwRule 'LAN Toolkit MC LAN-Broadcast' 'UDP' '4445'   # «Открыть для сети»: 224.0.2.60
  Add-FwRule "LAN Toolkit HTTP $Port" 'TCP' "$Port"
}

function New-Share {
  if (-not (Test-Path $Path)) { New-Item -ItemType Directory -Force -Path $Path | Out-Null }
  try { icacls $Path /grant '*S-1-1-0:(OI)(CI)M' /T /C | Out-Null } catch {}
  if (Get-SmbShare -Name $ShareName -ErrorAction SilentlyContinue) {
    Remove-SmbShare -Name $ShareName -Force -ErrorAction SilentlyContinue
  }
  try {
    New-SmbShare -Name $ShareName -Path $Path -FullAccess 'Everyone' -ErrorAction Stop | Out-Null
    Write-Host "  [+] шара \\$env:COMPUTERNAME\$ShareName -> $Path" -ForegroundColor Green
  } catch {
    Write-Host "  [!] не создал шару: $($_.Exception.Message)" -ForegroundColor Yellow
  }
  # SMB2+, подпись не мешает Linux/Android
  Set-SmbServerConfiguration -EnableSMB2Protocol $true -Confirm:$false -ErrorAction SilentlyContinue
}

function Get-HostName {
  $env:COMPUTERNAME
}

# ---------- actions ----------
function Do-Setup {
  Write-Host "`n=== LAN Toolkit: Windows setup ===" -ForegroundColor Cyan
  Write-Host "[1] Сетевой профиль -> Private"
  Set-PrivateNet
  Write-Host "[2] Firewall"
  Open-Firewall
  Write-Host "[3] SMB-шара"
  New-Share
  Write-Host "[4] Службы"
  foreach ($svc in 'LanmanServer','LanmanWorkstation','FDResPub','SSDPSRV','upnphost') {
    try { Set-Service $svc -StartupType Automatic -ErrorAction Stop
          if ((Get-Service $svc).Status -ne 'Running') { Start-Service $svc }
          Write-Host "  [+] $svc запущена" } catch {}
  }
  Write-Host "[5] Адреса" -ForegroundColor Cyan
  Show-IP

  $h = Get-HostName
  $info = @"

=== ГОТОВО. Как подключаться ===
Windows : \\$h\$ShareName      (или \\<IP>\$ShareName)
Linux   : smb://<IP>/$ShareName   |  sudo mount -t cifs //<IP>/$ShareName /mnt/lan -o user=<WinUser>,vers=3.0
Android : SMB-клиент (Cx File Explorer / Material Files): smb://<IP>/$ShareName, логин = учётка Windows
HTTP    : .\lan-win.ps1 http -Port $Port   ->  http://<IP>:$Port  (любой браузер, без логина)

Быстрая папка обмена: $Path
"@
  Write-Host $info -ForegroundColor Gray
}

function Do-Status {
  Write-Host "`n=== LAN Toolkit: status ===" -ForegroundColor Cyan
  Write-Host "Host: $(Get-HostName)"
  Write-Host "IPv4:"; Show-IP
  Write-Host "`nПрофили сети:"
  Get-NetConnectionProfile | Format-Table Name,InterfaceAlias,NetworkCategory -AutoSize
  Write-Host "SMB-шары:"
  Get-SmbShare | Where-Object { $_.Name -notlike '*$' } | Format-Table Name,Path -AutoSize
  Write-Host "Службы:"
  Get-Service LanmanServer,LanmanWorkstation,FDResPub,SSDPSRV -ErrorAction SilentlyContinue |
    Format-Table Name,Status,StartType -AutoSize
}

function Do-Http {
  $exe = $null
  foreach ($name in 'python','python3') {
    $c = Get-Command $name -ErrorAction SilentlyContinue
    if ($c) { $exe = $c.Source; break }
  }
  if (-not $exe) {
    Write-Host "[!] Python не найден — ставлю мини-сервер на .NET" -ForegroundColor Yellow
    Start-DotNetHttpServer
    return
  }
  if (-not (Test-Path $Path)) { New-Item -ItemType Directory -Force -Path $Path | Out-Null }
  Open-Firewall
  Write-Host "HTTP-обмен из $Path" -ForegroundColor Green
  Write-Host "Открой с телефона/линукса:" ; Show-IP
  Write-Host "  http://<IP>:$Port`n"
  Start-Process -FilePath $exe -ArgumentList @('-m','http.server',"$Port",'--bind','0.0.0.0') -WorkingDirectory $Path
}

function Start-DotNetHttpServer {
  # резервный вариант без Python
  Add-Type -AssemblyName System.Net.HttpListener -ErrorAction SilentlyContinue
  $prefix = "http://+:$Port/"
  $listener = New-Object System.Net.HttpListener
  $listener.Prefixes.Add($prefix)
  try { $listener.Start() } catch { Write-Host "[!] $($_.Exception.Message)"; return }
  Open-Firewall
  Write-Host "HTTP (native) на порту $Port, каталог $Path" -ForegroundColor Green
  Write-Host "Ctrl+C для остановки.`n"
  while ($listener.IsListening) {
    $ctx = $listener.GetContext()
    $rel = [Uri]::UnescapeDataString($ctx.Request.Url.LocalPath.TrimStart('/'))
    $file = Join-Path $Path $rel
    if (Test-Path $file -PathType Container) {
      $items = Get-ChildItem $file | ForEach-Object {
        "<li><a href=`"/$rel$($_.Name)`">$($_.Name)</a></li>" }
      $html = "<html><body><h3>$rel</h3><ul>$($items -join '')</ul></body></html>"
      $buf = [Text.Encoding]::UTF8.GetBytes($html)
      $ctx.Response.ContentType = 'text/html; charset=utf-8'
    } elseif (Test-Path $file -PathType Leaf) {
      $buf = [IO.File]::ReadAllBytes($file)
    } else {
      $buf = [Text.Encoding]::UTF8.GetBytes('404')
      $ctx.Response.StatusCode = 404
    }
    try { $ctx.Response.OutputStream.Write($buf,0,$buf.Length); $ctx.Response.Close() } catch {}
  }
}

function Do-Hotspot {
  $want = $On.IsPresent -or ($Action -eq 'hotspot' -and $On.IsPresent)
  try {
    [void][Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager,Windows.Networking.NetworkOperators,ContentType=WindowsRuntime]
    $netProf = [Windows.Networking.Connectivity.NetworkInformation]::GetInternetConnectionProfile()
    if (-not $netProf) { throw 'net-profile-missing' }
    $mgr = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager]::CreateFromConnectionProfile($netProf)
    if ($want) {
      $mgr.StartTetheringAsync() | Out-Null
      Write-Host "[+] Хот-спот включён (имя/пароль — Параметры > Сеть > Мобильный хот-спот)" -ForegroundColor Green
      Write-Host "    SSID: $($mgr.GetCurrentAccessPointConfiguration().Ssid)" -ForegroundColor Green
    } else {
      $mgr.StopTetheringAsync() | Out-Null
      Write-Host "[-] Хот-спот выключен"
    }
  } catch {
    Write-Host "[!] WinRT-хот-спот недоступен: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "    Открой: Параметры > Сеть и Интернет > Мобильный хот-спот (Win10/11)" -ForegroundColor Gray
  }
}

function Do-Mount {
  if (-not $Remote) { Write-Host "[!] Укажи -Remote \\IP\Share"; return }
  $cred = $null
  if ($User) { $cred = Get-Credential -UserName $User -Message "Пароль для $Remote" }
  if (Get-PSDrive -Name $Drive -ErrorAction SilentlyContinue) { net use "${Drive}:" /delete /y | Out-Null }
  if ($cred) {
    New-PSDrive -Name $Drive -PSProvider FileSystem -Root $Remote -Credential $cred -Persist
  } else {
    net use "${Drive}:" $Remote /persistent:yes
  }
  $sel = "$($Drive):"
  if (Get-PSDrive -Name $Drive -ErrorAction SilentlyContinue) { Write-Host "[+] $Remote -> $sel" -ForegroundColor Green }
}

function Do-Unmount {
  if (Get-PSDrive -Name $Drive -ErrorAction SilentlyContinue) { net use "${Drive}:" /delete /y }
  Write-Host "[-] отмонтировано $($Drive):"
}

function Do-Remove {
  Write-Host "=== Удаление настроек LAN Toolkit ===" -ForegroundColor Cyan
  if (Get-SmbShare -Name $ShareName -ErrorAction SilentlyContinue) {
    Remove-SmbShare -Name $ShareName -Force; Write-Host "[-] шара $ShareName удалена"
  }
  Get-NetFirewallRule -DisplayName 'LAN Toolkit*' -ErrorAction SilentlyContinue |
    ForEach-Object { Remove-NetFirewallRule -Name $_.Name; Write-Host "[-] правило $($_.DisplayName)" }
}

function Do-Minecraft {
  Write-Host "`n=== LAN Toolkit: Minecraft (Java + Bedrock) ===" -ForegroundColor Cyan
  Set-PrivateNet
  Add-FwRule 'LAN Toolkit MC Java TCP' 'TCP' "$McPort"
  Add-FwRule 'LAN Toolkit MC Java UDP' 'UDP' "$McPort"
  Add-FwRule 'LAN Toolkit MC Bedrock'  'UDP' "$BedrockPort,19133"
  Add-FwRule 'LAN Toolkit MC LAN-Broadcast' 'UDP' '4445'
  Write-Host "  [+] firewall: TCP/UDP $McPort (Java), UDP $BedrockPort (Bedrock)"

  $mcDir = $McDir
  if (-not $mcDir) { $mcDir = Join-Path $Path 'minecraft' }
  if (-not (Test-Path $mcDir)) { New-Item -ItemType Directory -Force -Path $mcDir | Out-Null }
  $jar   = Join-Path $mcDir 'server.jar'
  $props = Join-Path $mcDir 'server.properties'

  if (Test-Path $jar) {
    'eula=true' | Set-Content -Path (Join-Path $mcDir 'eula.txt') -Encoding ASCII
    $want = [ordered]@{
      'server-port'      = $McPort
      'enable-query'     = 'true'
      'query.port'       = $McPort
      'online-mode'      = 'true'
      'motd'             = 'LAN server'
      'max-players'      = '20'
      'view-distance'    = '8'
      'spawn-protection' = '0'
      'white-list'       = 'false'
    }
    $lines = @()
    if (Test-Path $props) { $lines = @(Get-Content $props) }
    foreach ($k in $want.Keys) {
      $rx = "^\s*" + [regex]::Escape($k) + "\s*="
      if ($lines -match $rx) {
        $lines = $lines | ForEach-Object { if ($_ -match $rx) { "$k=$($want[$k])" } else { $_ } }
      } else { $lines += "$k=$($want[$k])" }
    }
    Set-Content -Path $props -Value $lines -Encoding ASCII
    Write-Host "  [+] server.properties настроен (порт $McPort, eula=true)" -ForegroundColor Green

    $java = $null
    foreach ($n in 'javaw','java') {
      $c = Get-Command $n -ErrorAction SilentlyContinue
      if ($c) { $java = $c.Source; break }
    }
    if ($java) {
      Write-Host "  [+] запускаю: java -Xmx$McMem -jar server.jar nogui" -ForegroundColor Green
      Start-Process -FilePath $java -ArgumentList @("-Xmx$McMem","-Xms$McMem",'-jar','server.jar','nogui') -WorkingDirectory $mcDir
    } else {
      Write-Host "  [!] Java не найдена. Поставь Java 21 (Adoptium), затем:" -ForegroundColor Yellow
      Write-Host "      cd `"$mcDir`"; java -Xmx$McMem -jar server.jar nogui" -ForegroundColor Gray
    }
  } else {
    Write-Host "  [i] server.jar не найден в $mcDir" -ForegroundColor Yellow
    Write-Host "      Положи server.jar (Paper/Fabric/vanilla) туда и повтори:" -ForegroundColor Gray
    Write-Host "        .\lan-win.ps1 minecraft -McDir `"$mcDir`" -McMem 4G" -ForegroundColor Gray
    Write-Host "      Или в игре: Esc -> 'Открыть для сети' (Open to LAN) — друзья зайдут по IP." -ForegroundColor Gray
  }

  Write-Host "`n=== Адреса для друзей ===" -ForegroundColor Cyan
  Show-IP
  $h = Get-HostName
  Write-Host (@(
    '',
    "Java Edition : Multiplayer -> Direct Connection -> <IP>:$McPort",
    "Bedrock      : Add Server -> <IP>:$BedrockPort   (UDP)",
    "Эта машина   : localhost:$McPort",
    "По имени     : $h : $McPort   /   $h.local : $McPort (Linux/Android-клиенты)",
    '',
    'Java и Bedrock НЕ играют вместе. Для кросс-плея на Java-сервер ставят',
    'плагины Geyser + Floodgate — тогда Bedrock-игроки заходят на Java-порт.',
    'Android-телефон может быть и сервером (Termux), но обычно он КЛИЕНТ.',
    ''
  ) -join "`n") -ForegroundColor Gray
}

function Do-McJoin {
  Write-Host "`n=== Minecraft: куда подключаться ===" -ForegroundColor Cyan
  Show-IP
  Write-Host "  Java    : <IP>:$McPort" -ForegroundColor Green
  Write-Host "  Bedrock : <IP>:$BedrockPort (UDP)" -ForegroundColor Green
  Write-Host "  LAN-поиск в мобильной/консольной версии часто не видит ПК — вводи адрес вручную." -ForegroundColor Gray
}

# ================= MINECRAFT: LAN-сессия клиента + миры =================
# --- Minecraft Server List Ping (реальный протокол, а не «порт открыт») ---
function Get-VarIntBytes([uint32]$v) {
  $o = New-Object System.Collections.Generic.List[byte]
  while ($true) {
    if (($v -band 0xFFFFFF80) -eq 0) { $o.Add([byte]$v); break }
    $o.Add([byte](($v -band 0x7F) -bor 0x80)); $v = $v -shr 7
  }
  return ,$o.ToArray()
}
function Get-McStringBytes([string]$s) {
  $b = [Text.Encoding]::UTF8.GetBytes($s)
  return ,((Get-VarIntBytes ([uint32]$b.Length)) + $b)
}
function Read-VarIntFrom($Stream) {
  $num = 0; $shift = 0
  while ($true) {
    $b = $Stream.ReadByte(); if ($b -lt 0) { throw 'eof' }
    $num = $num -bor (($b -band 0x7F) -shl $shift)
    if (($b -band 0x80) -eq 0) { break }
    $shift += 7; if ($shift -gt 35) { throw 'varint' }
  }
  return $num
}

function Invoke-McPing {
  param([string]$Target = '127.0.0.1', [int]$PingPort = 25565, [int]$TimeoutMs = 2500)
  $client = New-Object Net.Sockets.TcpClient
  try {
    $client.ReceiveTimeout = $TimeoutMs; $client.SendTimeout = $TimeoutMs
    $iar = $client.BeginConnect($Target, $PingPort, $null, $null)
    if (-not $iar.AsyncWaitHandle.WaitOne($TimeoutMs)) { return $null }
    $client.EndConnect($iar)
    $st = $client.GetStream()
    $payload = @([byte]0x00) + (Get-VarIntBytes ([uint32]::MaxValue)) + (Get-McStringBytes $Target) +
               @([byte](($PingPort -shr 8) -band 0xFF), [byte]($PingPort -band 0xFF), [byte]0x01)
    $frame = (Get-VarIntBytes ([uint32]$payload.Length)) + $payload
    $st.Write($frame, 0, $frame.Length)
    $st.Write(@([byte]0x01, [byte]0x00), 0, 2)   # Status Request: длина 1, пакет 0x00
    $st.Flush()
    $len = Read-VarIntFrom $st
    if ($len -le 0 -or $len -gt 1MB) { return $null }
    $buf = New-Object byte[] $len; $rd = 0
    while ($rd -lt $len) { $r = $st.Read($buf, $rd, $len - $rd); if ($r -le 0) { break }; $rd += $r }
    $txt = [Text.Encoding]::UTF8.GetString($buf)
    $i = $txt.IndexOf('{'); $j = $txt.LastIndexOf('}')
    if ($i -lt 0 -or $j -le $i) { return $null }
    $json = $txt.Substring($i, $j - $i + 1) | ConvertFrom-Json
    $motd = $txt.Substring($i, $j - $i + 1)
    if ($motd -match '"text"\s*:\s*"([^"]*)"') { $motd = $Matches[1] }
    elseif ($motd -match '"description"\s*:\s*"([^"]*)"') { $motd = $Matches[1] }
    else { $motd = '' }
    [pscustomobject]@{
      Ok      = $true
      Motd    = ($motd -replace '§.', '')
      Version = $json.version.name
      Proto   = $json.version.protocol
      Online  = $json.players.online
      Max     = $json.players.max
      Who     = if ($json.players.sample) { ($json.players.sample | ForEach-Object { $_.name }) -join ', ' } else { '' }
      Port    = $PingPort
    }
  } catch { return $null } finally { try { $client.Close() } catch {} }
}

function Get-McProcess {
  $list = @()
  $procs = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^(javaw?|java)\.exe$' -and $_.CommandLine -match 'minecraft|net\.minecraft|prismlauncher\.EntryPoint' }
  foreach ($p in $procs) {
    $cl = $p.CommandLine
    $inst = $null; $ver = $null; $gameDir = $null
    if ($cl -match '(?:PrismLauncher|MultiMC)[\\/]instances[\\/]([^\\/]+)') {
      $inst = $Matches[1]
      $gameDir = Join-Path (Join-Path (Join-Path $env:APPDATA 'PrismLauncher') 'instances') (Join-Path $inst '.minecraft')
      if (-not (Test-Path $gameDir)) {
        $gameDir = Join-Path (Join-Path (Join-Path $env:APPDATA 'MultiMC') 'instances') (Join-Path $inst '.minecraft')
      }
    }
    if ($cl -match 'minecraft-([0-9][^\\/\s;]*)-client\.jar') { $ver = $Matches[1] }
    $ports = @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
               Where-Object { $_.OwningProcess -eq $p.ProcessId } |
               Select-Object -ExpandProperty LocalPort -Unique)
    $list += [pscustomobject]@{
      Pid      = $p.ProcessId
      Instance = $inst
      Version  = $ver
      GameDir  = $gameDir
      Ports    = $ports
      IsServer = [bool]($cl -match 'net\.minecraft\.server|minecraft_server')
      Started  = (Get-Process -Id $p.ProcessId -ErrorAction SilentlyContinue).StartTime
    }
  }
  return $list
}

function Find-McWorlds {
  $out = @()
  $roots = @(
    @{ Path = (Join-Path $env:APPDATA '.minecraft\saves'); Kind = 'Java'; Launcher = 'Vanilla' },
    @{ Path = (Join-Path $env:APPDATA 'PrismLauncher\instances'); Kind = 'Java'; Launcher = 'Prism'; Nested = $true },
    @{ Path = (Join-Path $env:APPDATA 'MultiMC\instances'); Kind = 'Java'; Launcher = 'MultiMC'; Nested = $true }
  )
  foreach ($r in $roots) {
    if (-not (Test-Path $r.Path)) { continue }
    if ($r.Nested) {
      foreach ($inst in Get-ChildItem $r.Path -Directory -ErrorAction SilentlyContinue) {
        $saves = Join-Path $inst.FullName '.minecraft\saves'
        if (-not (Test-Path $saves)) { continue }
        foreach ($w in Get-ChildItem $saves -Directory -ErrorAction SilentlyContinue) {
          if (-not (Test-Path (Join-Path $w.FullName 'level.dat'))) { continue }
          $out += [pscustomobject]@{
            Name = $w.Name; Path = $w.FullName; Kind = 'Java'
            Instance = $inst.Name; Modified = $w.LastWriteTime
            SizeMB = [math]::Round(((Get-ChildItem $w.FullName -Recurse -File -ErrorAction SilentlyContinue |
                      Measure-Object Length -Sum).Sum / 1MB), 1)
          }
        }
      }
    } else {
      foreach ($w in Get-ChildItem $r.Path -Directory -ErrorAction SilentlyContinue) {
        if (-not (Test-Path (Join-Path $w.FullName 'level.dat'))) { continue }
        $out += [pscustomobject]@{
          Name = $w.Name; Path = $w.FullName; Kind = 'Java'; Instance = $r.Launcher
          Modified = $w.LastWriteTime
          SizeMB = [math]::Round(((Get-ChildItem $w.FullName -Recurse -File -ErrorAction SilentlyContinue |
                    Measure-Object Length -Sum).Sum / 1MB), 1)
        }
      }
    }
  }
  # Bedrock (телефон/UWP) — на случай, если мир лежит локально
  $bd = Join-Path $env:LOCALAPPDATA 'Packages'
  if (Test-Path $bd) {
    foreach ($pkg in Get-ChildItem $bd -Directory -Filter 'Microsoft.MinecraftUWP*' -ErrorAction SilentlyContinue) {
      $wroot = Join-Path $pkg.FullName 'LocalState\games\com.mojang\minecraftWorlds'
      if (-not (Test-Path $wroot)) { continue }
      foreach ($w in Get-ChildItem $wroot -Directory -ErrorAction SilentlyContinue) {
        $lvl = Join-Path $w.FullName 'levelname.txt'
        $nm = if (Test-Path $lvl) { ([IO.File]::ReadAllText($lvl, [Text.Encoding]::UTF8)).Trim() } else { $w.Name }
        $out += [pscustomobject]@{
          Name = $nm; Path = $w.FullName; Kind = 'Bedrock'; Instance = 'Minecraft UWP'
          Modified = $w.LastWriteTime
          SizeMB = [math]::Round(((Get-ChildItem $w.FullName -Recurse -File -ErrorAction SilentlyContinue |
                    Measure-Object Length -Sum).Sum / 1MB), 1)
        }
      }
    }
  }
  return ($out | Sort-Object Modified -Descending)
}

function Test-WorldInUse([string]$WorldPath) {
  $lock = Join-Path $WorldPath 'session.lock'
  if (-not (Test-Path $lock)) { return $false }
  try {
    $fs = [IO.File]::Open($lock, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    $fs.Close(); return $false
  } catch { return $true }
}

function Get-LanAnnouncement {
  # Мультикаст-объявления «Открыть для сети»: 224.0.2.60:4445
  $found = @()
  try {
    $udp = New-Object Net.Sockets.UdpClient
    $udp.Client.SetSocketOption([Net.Sockets.SocketOptionLevel]::Socket,
      [Net.Sockets.SocketOptionName]::ReuseAddress, $true)
    $udp.Client.Bind((New-Object Net.IPEndPoint([Net.IPAddress]::Any, 4445)))
    $joined = $false
    foreach ($ip in (Get-LanIP)) {
      try { $udp.JoinMulticastGroup([Net.IPAddress]::Parse('224.0.2.60'), [Net.IPAddress]::Parse($ip)); $joined = $true } catch {}
    }
    if (-not $joined) { try { $udp.JoinMulticastGroup([Net.IPAddress]::Parse('224.0.2.60')); $joined = $true } catch {} }
    $udp.Client.ReceiveTimeout = 2500
    $deadline = (Get-Date).AddSeconds(3)
    while ((Get-Date) -lt $deadline) {
      try {
        $ep = New-Object Net.IPEndPoint([Net.IPAddress]::Any, 0)
        $b = $udp.Receive([ref]$ep)
        $txt = [Text.Encoding]::UTF8.GetString($b)
        if ($txt -match '\[MOTD\](.*?)\[/MOTD\]') {
          $motd = $Matches[1]
          $port = if ($txt -match '\[AD\](\d+)\[/AD\]') { [int]$Matches[1] } else { 0 }
          $found += [pscustomobject]@{ From = $ep.Address.ToString(); Motd = $motd; Port = $port }
        }
      } catch { break }
    }
    $udp.Close()
  } catch {}
  return $found
}

function Do-Detect {
  Write-Host "`n=== Поиск запущенного Minecraft (клиент-клиент, «Открыть для сети») ===" -ForegroundColor Cyan
  $procs = Get-McProcess
  if (-not $procs) {
    Write-Host "  Minecraft сейчас не запущен (java-процессов игры нет)." -ForegroundColor Yellow
  }
  $anyLan = $false
  foreach ($p in $procs) {
    $kind = if ($p.IsServer) { 'СЕРВЕР' } else { 'КЛИЕНТ (игра)' }
    Write-Host ""
    Write-Host "  Найдено: $kind  PID $($p.Pid)" -ForegroundColor Green
    if ($p.Instance) { Write-Host "    Инстанс : $($p.Instance)" }
    if ($p.Version)  { Write-Host "    Версия  : $($p.Version)" }
    if ($p.Started)  { Write-Host "    Запущен : $($p.Started)" }
    if ($p.GameDir)  { Write-Host "    Миры    : $($p.GameDir)\saves" }

    $lanPorts = @($p.Ports | Where-Object { $_ -ne 25565 })
    foreach ($port in $p.Ports) {
      $ping = Invoke-McPing -Target '127.0.0.1' -PingPort $port
      if ($ping -and $ping.Ok) {
        $anyLan = $true
        Write-Host "    ЛОКАЛЬНАЯ СЕТЬ ОТКРЫТА -> порт $port" -ForegroundColor Green
        Write-Host "      Мир      : $($ping.Motd)"
        Write-Host "      Версия   : $($ping.Version) (protocol $($ping.Proto))"
        Write-Host "      Игроки   : $($ping.Online)/$($ping.Max)" -ForegroundColor $(if ($ping.Online -gt 0) { 'Green' } else { 'Gray' })
        if ($ping.Who) { Write-Host "      Сейчас в игре: $($ping.Who)" }
        Add-FwRule "LAN Toolkit MC LAN $port" 'TCP' "$port" 2>$null
        Write-Host "      Адрес для друзей:" -ForegroundColor Yellow
        foreach ($ip in (Get-LanIP)) { Write-Host "        $ip`:$port" -ForegroundColor Yellow }
      }
    }
    if ($p.Ports.Count -eq 0 -and -not $p.IsServer) {
      Write-Host "    LAN не открыт. В игре: Esc -> «Открыть для сети» (Open to LAN)" -ForegroundColor Yellow
    }
  }

  Write-Host ""
  Write-Host "  --- Поиск чужих LAN-игр в сети (мультикаст 224.0.2.60) ---" -ForegroundColor Cyan
  $ann = Get-LanAnnouncement
  if ($ann) { foreach ($a in $ann) { Write-Host "    $($a.From) -> $($a.Motd) (порт $($a.Port))" -ForegroundColor Green } }
  else { Write-Host "    Объявлений не слышно (это нормально: видно только когда хост открыл LAN и сеть не режет мультикаст)." -ForegroundColor Gray }

  if ($anyLan) {
    Write-Host ""
    Write-Host "  Друзья заходят: Multiplayer -> Direct Connection -> <IP>:<порт выше>" -ForegroundColor Green
    Write-Host "  Порт меняется каждый раз при новом «Открыть для сети»." -ForegroundColor Gray
  }
}

function Get-RobocopyCode([int]$code) {
  if ($code -ge 8) { return "ОШИБКА (код $code)" }
  if ($code -ge 1) { return "скопировано (код $code)" }
  return "уже актуально (код 0)"
}

function Do-World {
  param([string]$Mode = 'list')
  $remote = if ($Remote) { $Remote } else { Join-Path $Path 'mcworlds' }
  Write-Host "`n=== Minecraft: миры ===" -ForegroundColor Cyan

  if ($Mode -eq 'list') {
    $worlds = Find-McWorlds
    if (-not $worlds) { Write-Host "  Миры не найдены." -ForegroundColor Yellow; return }
    Write-Host "  Найдено миров: $($worlds.Count)"
    $i = 0
    foreach ($w in $worlds) {
      $i++
      $busy = if (Test-WorldInUse $w.Path) { ' [ЗАНЯТ игрой]' } else { '' }
      Write-Host ("   {0,2}) {1}  ({2}, {3} МБ, изменён {4}){5}" -f $i, $w.Name, $w.Kind, $w.SizeMB, $w.Modified.ToString('dd.MM HH:mm'), $busy)
      Write-Host ("       $($w.Path)") -ForegroundColor DarkGray
    }
    Write-Host ""
    Write-Host "  Синхронизировать: .\lan-win.ps1 world sync -World `"имя мира`" -Remote `"\\IP\LAN`"" -ForegroundColor Gray
    return
  }

  # выбор мира
  $worlds = Find-McWorlds
  if (-not $worlds) { Write-Host "  Миры не найдены." -ForegroundColor Yellow; return }
  $w = $null
  if ($World) {
    $w = $worlds | Where-Object { $_.Name -eq $World } | Select-Object -First 1
    if (-not $w) { $w = $worlds | Where-Object { $_.Name -like "*$World*" } | Select-Object -First 1 }
  } else {
    $w = $worlds | Select-Object -First 1
  }
  if (-not $w) { Write-Host "  Мир '$World' не найден." -ForegroundColor Red; return }

  Write-Host "  Мир: $($w.Name)  ($($w.Path))" -ForegroundColor Green
  if (Test-WorldInUse $w.Path) {
    Write-Host "  [!] Мир сейчас используется игрой (session.lock занят)." -ForegroundColor Yellow
    if (-not $Force) {
      Write-Host "      Закрой Minecraft (или выйди в главное меню) и повтори. Либо -Force, если уверен." -ForegroundColor Yellow
      return
    }
    Write-Host "      Продолжаю по -Force." -ForegroundColor Yellow
  }

  $dest = Join-Path $remote $w.Name
  if (-not (Test-Path $remote)) { New-Item -ItemType Directory -Force -Path $remote | Out-Null }

  # бэкап перед изменениями
  if (-not $NoBackup) {
    $bdir = Join-Path $remote '_backups'
    if (-not (Test-Path $bdir)) { New-Item -ItemType Directory -Force -Path $bdir | Out-Null }
    $zip = Join-Path $bdir ("{0}-{1}.zip" -f ($w.Name -replace '[\\/:*?"<>|]', '_'), (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Write-Host "  Бэкап: $zip" -ForegroundColor Gray
    try { Compress-Archive -Path (Join-Path $w.Path '*') -DestinationPath $zip -CompressionLevel Optimal -Force }
    catch { Write-Host "  [!] Бэкап не сделался: $($_.Exception.Message)" -ForegroundColor Yellow }
  }

  $rcArgs = @('/E','/XO','/R:1','/W:1','/NFL','/NDL','/NJH','/NJS','/NP','/XF','session.lock')
  if ($Mirror) { $rcArgs += '/MIR' }

  if ($Mode -in 'push','sync') {
    Write-Host "  Отдаю мир в общую папку..." -ForegroundColor Cyan
    $null = robocopy $w.Path $dest @rcArgs
    Write-Host "    -> $(Get-RobocopyCode $LASTEXITCODE)"
  }
  if ($Mode -in 'pull','sync') {
    if (-not (Test-Path $dest)) { Write-Host "  [!] В общей папке нет мира '$($w.Name)' — нечего забирать." -ForegroundColor Yellow; return }
    Write-Host "  Забираю мир из общей папки..." -ForegroundColor Cyan
    $null = robocopy $dest $w.Path @rcArgs
    Write-Host "    -> $(Get-RobocopyCode $LASTEXITCODE)"
  }
  if ($Mode -eq 'backup') { Write-Host "  Бэкап готов." -ForegroundColor Green }
  Write-Host "  Готово. Общая папка мира: $dest" -ForegroundColor Green
}

function Invoke-SyncPass {
  param([string]$LocalDir, [string]$RemoteDir, [switch]$Mirror)
  $rc = @('/E','/XO','/R:1','/W:1','/NFL','/NDL','/NJH','/NJS','/NP')
  if ($Mirror) { $rc += '/MIR' }
  $null = robocopy $LocalDir $RemoteDir @rc; $to = $LASTEXITCODE
  $null = robocopy $RemoteDir $LocalDir @rc; $back = $LASTEXITCODE
  return [pscustomobject]@{ ToRemote = $to; ToLocal = $back }
}

function Do-Sync {
  Write-Host "`n=== Двусторонний обмен папками ===" -ForegroundColor Cyan
  $localDir = if ($Local) { $Local } else { $Path }
  $remoteDir = $Remote
  if (-not $remoteDir) { Write-Host "  [!] Укажи -Remote `"\\IP\LAN\папка`" (или локальный путь)."; return }
  if (-not (Test-Path $localDir)) { New-Item -ItemType Directory -Force -Path $localDir | Out-Null }
  Write-Host "  Локально : $localDir"
  Write-Host "  Удалённо : $remoteDir"
  if ($Mirror) { Write-Host "  Режим    : ЗЕРКАЛО (удаляет лишнее на обеих сторонах!)" -ForegroundColor Yellow }
  else { Write-Host "  Режим    : безопасный (новее побеждает, ничего не удаляется)" -ForegroundColor Green }

  $pass = {
    Write-Host ("  [{0}] туда и обратно..." -f (Get-Date -Format 'HH:mm:ss')) -ForegroundColor Cyan
    $res = Invoke-SyncPass -LocalDir $localDir -RemoteDir $remoteDir -Mirror:$Mirror
    Write-Host "     -> туда: $(Get-RobocopyCode $res.ToRemote) | обратно: $(Get-RobocopyCode $res.ToLocal)"
  }
  & $pass
  if ($Watch -and [int]$Watch -gt 0) {
    Write-Host "  Слежение каждые $Watch сек. Ctrl+C — стоп." -ForegroundColor Green
    while ($true) { Start-Sleep -Seconds ([int]$Watch); & $pass }
  } else {
    Write-Host "  Один проход завершён. Для постоянного обмена: -Watch 30" -ForegroundColor Gray
  }
}

# ================= PEER: удалённая синхронизация через SSH =================
# Идея: на обоих устройствах лежит ОДИН И ТОТ ЖЕ скрипт. Инициатор заходит по SSH
# и просит вторую сторону сделать её половину работы. Защиты (по порядку проверки):
#   1) SSH-доступ уже разрешён администратором той машины (ключ в authorized_keys);
#   2) принимающая сторона ВЗВЕДЕНА вручную: peer-arm -Token XXX -Minutes 30
#      (взвести удалённо нельзя — команды arm/disarm в белом списке нет);
#   3) токен + срок жизни + опционально «одноразово»;
#   4) белый список команд: ping, hash, status, detect, world, sync, mcjoin;
#   5) сверка хеша тулкита — на обеих машинах должен быть одинаковый скрипт;
#   6) всё пишется в audit.log, включая отказы.

function Get-PeerHome {
  $h = Join-Path $env:USERPROFILE '.lan-toolkit'
  if (-not (Test-Path $h)) { New-Item -ItemType Directory -Force -Path $h | Out-Null }
  return $h
}
function Get-PeerFile([string]$n) { return (Join-Path (Get-PeerHome) $n) }
function Get-PeerKeyPath { return (Join-Path (Get-PeerHome) 'keys\id_ed25519') }
function Get-PeerKnownHosts { return (Get-PeerFile 'known_hosts_peers') }

function Get-PeerList {
  $f = Get-PeerFile 'peers.json'
  if (-not (Test-Path $f)) { return @() }
  try { return @(Get-Content $f -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return @() }
}
function Save-PeerList($list) {
  $arr = @($list)
  if ($arr.Count -eq 0) { '[]' | Set-Content -Path (Get-PeerFile 'peers.json') -Encoding UTF8; return }
  ($arr | ConvertTo-Json -Depth 6) | Set-Content -Path (Get-PeerFile 'peers.json') -Encoding UTF8
}
function Get-Peer([string]$name) {
  if (-not $name) { return $null }
  return (Get-PeerList | Where-Object { $_.Name -eq $name } | Select-Object -First 1)
}
function Write-PeerAudit([string]$line) {
  Add-Content -Path (Get-PeerFile 'audit.log') -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + "  " + $line) -Encoding UTF8
}
function Get-StrHash([string]$s) {
  $sha = [Security.Cryptography.SHA256]::Create()
  return (($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($s)) | ForEach-Object { $_.ToString('x2') }) -join '')
}
function Get-NormalizedHash([string]$path) {
  # sha256 содержимого с переводами строк, приведёнными к LF.
  # Так Windows (CRLF в рабочей копии) и Linux (LF) дают одинаковый хеш,
  # и он же совпадает с содержимым архива GitHub (там всегда LF).
  $bytes = [IO.File]::ReadAllBytes($path)
  $ms = New-Object IO.MemoryStream
  for ($i = 0; $i -lt $bytes.Length; $i++) {
    if ($bytes[$i] -eq 13 -and ($i + 1) -lt $bytes.Length -and $bytes[$i + 1] -eq 10) { continue }
    $ms.WriteByte($bytes[$i])
  }
  $sha = [Security.Cryptography.SHA256]::Create()
  $h = (($sha.ComputeHash($ms.ToArray()) | ForEach-Object { $_.ToString('x2') }) -join '')
  $ms.Dispose()
  return $h
}
function Get-ToolkitHash {
  # Фиксированный список файлов — так хеш совпадает и в PowerShell, и в bash.
  # Отсутствующий файл считается пустым ('-'), поэтому Linux без lan-win.ps1
  # даст тот же хеш, что и Windows. Переводы строк не влияют (LF-нормализация).
  $names = @('lan-win.ps1','lan-linux.sh','lan-android.sh','mcping.py')
  $sb = New-Object Text.StringBuilder
  foreach ($n in $names) {
    $fp = Join-Path $PSScriptRoot $n
    $h = if (Test-Path $fp) { (Get-NormalizedHash $fp) } else { '-' }
    [void]$sb.Append($n).Append(':').Append($h).Append("`n")
  }
  return (Get-StrHash $sb.ToString())
}
function Get-ArmState {
  $f = Get-PeerFile 'armed.json'
  if (-not (Test-Path $f)) { return $null }
  try { return (Get-Content $f -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
}

function Do-PeerKeygen {
  $key = Get-PeerKeyPath
  if (Test-Path $key) { Write-Host "Ключ уже есть: $key" -ForegroundColor Green }
  else {
    $dir = Split-Path $key -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    & ssh-keygen -t ed25519 -N '""' -C "lan-toolkit@$env:COMPUTERNAME" -f $key 2>&1 | Out-Null
    Write-Host "Создан ключ тулкита: $key" -ForegroundColor Green
  }
  Write-Host "`nПубличный ключ — добавить на ВТОРОЙ машине:" -ForegroundColor Yellow
  Get-Content "$key.pub"
  Write-Host "`n  Windows-цель : строка в C:\Users\<user>\.ssh\authorized_keys" -ForegroundColor Gray
  Write-Host "                 (если user в группе админов — в C:\ProgramData\ssh\administrators_authorized_keys," -ForegroundColor Gray
  Write-Host "                  права только Administrators и SYSTEM, иначе sshd ключ проигнорирует)" -ForegroundColor Gray
  Write-Host "  Linux/Android: ssh-copy-id -i `"$key.pub`" user@IP" -ForegroundColor Gray
}

function Do-PeerAdd {
  if (-not $Peer) { Write-Host "Укажи -Peer имя -PeerHost IP [-PeerUser user]"; return }
  if (-not $PeerHost) { Write-Host "Укажи -PeerHost IP"; return }
  $plat = if ($PeerPlatform) { $PeerPlatform } else { 'linux' }
  $usr  = if ($PeerUser) { $PeerUser } else { $env:USERNAME }
  $prt  = if ($PeerPort) { $PeerPort } else { 22 }
  $tk   = if ($PeerToolkit) { $PeerToolkit } else { 'lan-toolkit' }

  Write-Host "Пинную host key (ssh-keyscan)..." -ForegroundColor Cyan
  $kh = Get-PeerKnownHosts
  $scan = & ssh-keyscan -p $prt $PeerHost 2>$null
  if (-not $scan) { Write-Host "[!] host key не прочитан — машина недоступна?" -ForegroundColor Yellow }
  else { $scan | Set-Content -Path $kh -Encoding ASCII; Write-Host "  [+] host key сохранён: $kh" -ForegroundColor Green }
  $fp = ''
  try { $line = ($scan | Select-String 'ssh-ed25519' | Select-Object -First 1).Line; $fp = ($line -split ' ')[1] } catch {}

  $list = @(Get-PeerList | Where-Object { $_.Name -ne $Peer })
  $list += [pscustomobject]@{
    Name = $Peer; Host = $PeerHost; User = $usr; Port = [int]$prt
    Platform = $plat; Toolkit = $tk; Fingerprint = $fp; Added = (Get-Date -Format 'yyyy-MM-dd HH:mm')
  }
  Save-PeerList $list
  Write-Host "  [+] peer '$Peer' -> $usr@$PeerHost`:$prt ($plat)" -ForegroundColor Green
  Write-Host "`nДальше:" -ForegroundColor Cyan
  Write-Host "  1) .\lan-win.ps1 peer-bootstrap -Peer $Peer     # залить тулкит на ту машину"
  Write-Host "  2) .\lan-win.ps1 peer-keygen                    # и добавить ключ на ту машину"
  Write-Host "  3) НА ТОЙ МАШИНЕ человек взводит: peer-arm -Token <код> -Minutes 30"
  Write-Host "  4) .\lan-win.ps1 peer-test -Peer $Peer"
}

function Do-PeerListCmd {
  $list = Get-PeerList
  if (-not $list) { Write-Host "Партнёров нет. Добавь: -Action peer-add -Peer имя -PeerHost IP" -ForegroundColor Yellow }
  else {
    Write-Host "`nИзвестные партнёры:" -ForegroundColor Cyan
    $list | Format-Table Name, Host, User, Port, Platform -AutoSize
  }
  $arm = Get-ArmState
  Write-Host "Состояние ЭТОЙ машины (приём удалённых команд):" -ForegroundColor Cyan
  if (-not $arm) { Write-Host "  не взведена — удалённые команды отклоняются" -ForegroundColor Gray }
  else {
    $left = [math]::Round((([datetime]$arm.Expires) - (Get-Date)).TotalMinutes, 1)
    if ($left -le 0) { Write-Host "  взведена, но срок истёк ($($arm.Expires))" -ForegroundColor Yellow }
    else {
      $fpTxt = if ($arm.AllowFp) { $arm.AllowFp } else { 'любой' }
      Write-Host "  ВЗВЕДЕНА ещё $left мин (одноразово: $($arm.Once), инициатор: $fpTxt)" -ForegroundColor Green
    }
  }
}

function Do-PeerForget {
  if (-not $Peer) { Write-Host "Укажи -Peer имя"; return }
  Save-PeerList @(Get-PeerList | Where-Object { $_.Name -ne $Peer })
  Write-PeerAudit "peer-forget $Peer"
  Write-Host "[-] партнёр '$Peer' удалён"
}

function Do-PeerArm {
  if (-not $Token) { Write-Host "[!] Нужен -Token <код>." -ForegroundColor Yellow; return }
  if ($Token.Length -lt 6) { Write-Host "[!] Токен короче 6 символов." -ForegroundColor Red; return }
  $min = if ($Minutes -gt 0) { $Minutes } else { 30 }
  if ($min -gt 240) { Write-Host "[!] Максимум 240 минут." -ForegroundColor Red; return }
  $state = [pscustomobject]@{
    TokenHash   = (Get-StrHash $Token)
    Expires     = (Get-Date).AddMinutes($min).ToString('yyyy-MM-dd HH:mm:ss')
    Once        = [bool]$Once
    Uses        = 0
    AllowFp     = $(if ($AllowFp) { $AllowFp } else { '' })
    ToolkitHash = (Get-ToolkitHash)
    ArmedBy     = "$env:USERNAME@$env:COMPUTERNAME"
  }
  ($state | ConvertTo-Json) | Set-Content -Path (Get-PeerFile 'armed.json') -Encoding UTF8
  Write-PeerAudit "ARM на $min мин, once=$($Once)"
  Write-Host "[+] Машина взведена на $min мин — принимаю удалённую синхронизацию." -ForegroundColor Green
  Write-Host "    Отключить: .\lan-win.ps1 peer-disarm" -ForegroundColor Gray
  Write-Host "    Токен хранится только как SHA-256." -ForegroundColor Gray
}

function Do-PeerDisarm {
  $f = Get-PeerFile 'armed.json'
  if (Test-Path $f) { Remove-Item $f -Force }
  Write-PeerAudit "DISARM"
  Write-Host "[-] Машина больше не принимает удалённые команды." -ForegroundColor Green
}

function Get-RemoteRunner($p) {
  $tk = ($p.Toolkit -replace '/', '\')
  if ($p.Platform -eq 'win') {
    return 'powershell -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\' + $tk + '\lan-win.ps1" -Action peer-serve'
  }
  if ($p.Platform -eq 'android') { return 'bash "$HOME/' + $p.Toolkit + '/lan-android.sh" peer-serve' }
  return 'bash "$HOME/' + $p.Toolkit + '/lan-linux.sh" peer-serve'
}

function Invoke-PeerServeRemote {
  param($PeerObj, [string]$RequestText)
  $key = Get-PeerKeyPath
  if (-not (Test-Path $key)) { throw "Нет SSH-ключа тулкита. Запусти: -Action peer-keygen" }
  $argList = @('-i', $key, '-p', "$($PeerObj.Port)",
               '-o', "UserKnownHostsFile=$(Get-PeerKnownHosts)",
               '-o', 'StrictHostKeyChecking=yes',
               '-o', 'BatchMode=yes',
               '-o', 'ConnectTimeout=8',
               "$($PeerObj.User)@$($PeerObj.Host)",
               (Get-RemoteRunner $PeerObj))
  $psi = New-Object Diagnostics.ProcessStartInfo
  $psi.FileName = (Get-Command ssh).Source
  $quoted = foreach ($a in $argList) { if ($a -match '[\s"]') { '"' + ($a -replace '"', '\"') + '"' } else { $a } }
  $psi.Arguments = ($quoted -join ' ')
  $psi.RedirectStandardInput = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.UseShellExecute = $false
  $psi.StandardOutputEncoding = [Text.Encoding]::UTF8
  $psi.StandardErrorEncoding = [Text.Encoding]::UTF8
  $proc = [Diagnostics.Process]::Start($psi)
  $proc.StandardInput.Write($RequestText)
  $proc.StandardInput.Close()
  $outTask = $proc.StandardOutput.ReadToEndAsync()
  $errTask = $proc.StandardError.ReadToEndAsync()
  $proc.WaitForExit(600000) | Out-Null
  return [pscustomobject]@{ Exit = $proc.ExitCode; Out = $outTask.Result; Err = $errTask.Result }
}

function New-PeerRequest([string]$CmdName, [hashtable]$Args, [string]$TokenText) {
  $sb = New-Object Text.StringBuilder
  [void]$sb.AppendLine('v=1')
  [void]$sb.AppendLine("cmd=$CmdName")
  [void]$sb.AppendLine("token=$TokenText")
  [void]$sb.AppendLine("from=$env:USERNAME@$env:COMPUTERNAME")
  [void]$sb.AppendLine("hash=$(Get-ToolkitHash)")
  foreach ($k in $Args.Keys) { [void]$sb.AppendLine("arg.$k=$($Args[$k])") }
  [void]$sb.AppendLine('')
  return $sb.ToString()
}

function Read-PeerResult([string]$Out) {
  $res = @{}
  foreach ($line in ($Out -split "`r?`n")) {
    if ($line -match '^([A-Za-z_]+)=(.*)$') { $res[$Matches[1]] = $Matches[2] }
  }
  return $res
}

function Do-PeerBootstrap {
  if (-not $Peer) { Write-Host "Укажи -Peer имя"; return }
  $p = Get-Peer $Peer
  if (-not $p) { Write-Host "Партнёр '$Peer' не найден"; return }
  Write-Host "Копирую тулкит на $($p.User)@$($p.Host) ($($p.Platform))..." -ForegroundColor Cyan
  $key = Get-PeerKeyPath
  $kh = Get-PeerKnownHosts
  $base = @('-i', $key, '-P', "$($p.Port)", '-o', "UserKnownHostsFile=$kh", '-o', 'StrictHostKeyChecking=yes', '-o', 'BatchMode=yes')
  $remoteDir = ($p.Toolkit -replace '\\', '/')
  $target = "$($p.User)@$($p.Host)"
  if ($p.Platform -eq 'win') {
    & ssh @base $target ("mkdir `"$($p.Toolkit)`" 2>nul & echo ok") | Out-Null
  } else {
    & ssh @base $target ("mkdir -p `"`$HOME/$remoteDir`"") | Out-Null
  }
  if ($LASTEXITCODE -ne 0) { Write-Host "[!] SSH не пускает — ключ добавлен на той машине?" -ForegroundColor Red; return }
  $files = Get-ChildItem $PSScriptRoot -File | Where-Object { $_.Name -notlike '.*' -and $_.Extension -ne '.pyc' }
  $okCount = 0
  foreach ($f in $files) {
    & scp @base $f.FullName "$target`:$remoteDir/$($f.Name)" 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { $okCount++ }
  }
  if ($p.Platform -ne 'win') {
    & ssh @base $target ("chmod +x `"`$HOME/$remoteDir`"/*.sh 2>/dev/null; echo ok") | Out-Null
  }
  Write-Host "  [+] отправлено файлов: $okCount из $($files.Count)" -ForegroundColor Green
  Write-PeerAudit "bootstrap $Peer ($okCount файлов)"
  Write-Host "Теперь НА ТОЙ машине человек выполняет: peer-arm -Token <код>" -ForegroundColor Yellow
}

function Do-PeerTest {
  if (-not $Peer) { Write-Host "Укажи -Peer имя"; return }
  $p = Get-Peer $Peer
  if (-not $p) { Write-Host "Партнёр '$Peer' не найден"; return }
  $r = Invoke-PeerServeRemote -PeerObj $p -RequestText (New-PeerRequest 'ping' @{} '')
  if ($r.Exit -ne 0 -and -not $r.Out) {
    Write-Host "[!] SSH не отвечает (exit $($r.Exit)): $($r.Err)" -ForegroundColor Red
    Write-PeerAudit "test $Peer -> SSH FAIL $($r.Exit)"
    return
  }
  $res = Read-PeerResult $r.Out
  Write-Host "`nОтвет второй стороны:" -ForegroundColor Cyan
  Write-Host "  RESULT: $($res['RESULT'])" -ForegroundColor $(if ($res['RESULT'] -eq 'ok') { 'Green' } else { 'Yellow' })
  if ($res['RESULT'] -ne 'ok' -and $res['MSG']) {
    Write-Host "  MSG   : $($res['MSG'])" -ForegroundColor Yellow
    switch -Wildcard ($res['MSG']) {
      '*не взведена*'   { Write-Host "  -> На той машине: bash lan-linux.sh peer-arm -Token <код> -Minutes 30" -ForegroundColor Gray }
      '*токен*'         { Write-Host "  -> Токен не совпал. Возьми тот, что вводили на той машине." -ForegroundColor Gray }
      '*разные*'        { Write-Host "  -> Обнови тулкит на обеих машинах (peer-bootstrap)." -ForegroundColor Gray }
    }
  }
  if ($res['hash']) {
    $mine = Get-ToolkitHash
    if ($res['hash'] -eq $mine) { Write-Host "  Скрипты совпадают: $($mine.Substring(0,12))..." -ForegroundColor Green }
    else { Write-Host "  [!] Версии скриптов разные.`n      моя: $mine`n      чужая: $($res['hash'])" -ForegroundColor Red }
  }
  Write-PeerAudit "test $Peer -> $($res['RESULT']) $($res['MSG'])"
}

function Do-PeerRun {
  if (-not $Peer -or -not $Cmd) { Write-Host "Укажи -Peer имя -Cmd status|detect|world|mcjoin"; return }
  $p = Get-Peer $Peer
  if (-not $p) { Write-Host "Партнёр '$Peer' не найден"; return }
  $a = @{}
  if ($WorldMode) { $a['mode'] = $WorldMode }
  if ($World) { $a['world'] = $World }
  $r = Invoke-PeerServeRemote -PeerObj $p -RequestText (New-PeerRequest $Cmd $a $Token)
  Write-Host "`n=== Вывод второй машины ($Peer) ===" -ForegroundColor Cyan
  Write-Host $r.Out
  if ($r.Err) { Write-Host $r.Err -ForegroundColor Yellow }
  $res = Read-PeerResult $r.Out
  Write-PeerAudit "run $Peer cmd=$Cmd -> $($res['RESULT'])"
}

function Do-PeerSync {
  if (-not $Peer) { Write-Host "Укажи -Peer имя"; return }
  $p = Get-Peer $Peer
  if (-not $p) { Write-Host "Партнёр '$Peer' не найден"; return }
  $localDir  = if ($Local) { $Local } else { Join-Path $Path 'обмен' }
  $remoteDir = if ($RemoteDir) { $RemoteDir } else { Join-Path $Path 'обмен' }
  $sec = if ($Watch -gt 0) { $Watch } else { 0 }
  $shareName = Split-Path $Path -Leaf
  $subName = Split-Path $localDir -Leaf
  Write-Host "`n=== Двусторонняя синхронизация с '$Peer' ===" -ForegroundColor Cyan
  Write-Host "  моя папка      : $localDir"
  Write-Host "  папка на $Peer : $remoteDir"
  Write-Host "  интервал       : $(if ($sec -gt 0) { "$sec сек" } else { 'один проход' })"

  $pass = {
    $myIp = (Get-LanIP | Select-Object -First 1)
    $a = @{ local = $remoteDir; remote = "\\$myIp\$shareName\$subName"; watch = 0 }
    if ($Mirror) { $a['mirror'] = 1 }
    $r = Invoke-PeerServeRemote -PeerObj $p -RequestText (New-PeerRequest 'sync' $a $Token)
    $res = Read-PeerResult $r.Out
    if ($res['RESULT'] -eq 'ok') { Write-Host "  [$(Get-Date -Format 'HH:mm:ss')] вторая сторона: ок ($($res['MSG']))" -ForegroundColor Green }
    else { Write-Host "  [$(Get-Date -Format 'HH:mm:ss')] вторая сторона: $($res['RESULT']) — $($res['MSG'])" -ForegroundColor Yellow }
    $mine = Invoke-SyncPass -LocalDir $localDir -RemoteDir "\\$($p.Host)\$shareName\$subName" -Mirror:$Mirror
    Write-Host "  [$(Get-Date -Format 'HH:mm:ss')] моя сторона: туда=$($mine.ToRemote) обратно=$($mine.ToLocal)" -ForegroundColor Green
    Write-PeerAudit "sync $Peer local=$localDir remote=$remoteDir"
  }
  & $pass
  if ($sec -gt 0) {
    Write-Host "  Слежение каждые $sec сек. Ctrl+C — стоп." -ForegroundColor Green
    while ($true) { Start-Sleep -Seconds $sec; & $pass }
  }
}

function Do-PeerLog {
  $f = Get-PeerFile 'audit.log'
  if (-not (Test-Path $f)) { Write-Host "Журнал пуст."; return }
  Write-Host "`n=== Журнал ($f) ===" -ForegroundColor Cyan
  Get-Content $f -Tail 40
}

# --- принимающая сторона: выполняется на второй машине ---
function Do-PeerServe {
  param([string]$RequestFile)
  $raw = ''
  if ($RequestFile -and (Test-Path $RequestFile)) { $raw = Get-Content $RequestFile -Raw -Encoding UTF8 }
  else { try { $raw = [Console]::In.ReadToEnd() } catch {} }

  $req = @{}
  foreach ($line in ($raw -split "`r?`n")) {
    if ($line -match '^([A-Za-z_.]+)=(.*)$') { $req[$Matches[1]] = $Matches[2] }
  }
  $cmd = $req['cmd']; $token = $req['token']; $from = $req['from']; $theirHash = $req['hash']

  function Deny([string]$why) {
    Write-PeerAudit "DENY cmd=$cmd from=${from}: $why"
    Write-Output 'RESULT=denied'
    Write-Output "MSG=$why"
  }

  $arm = Get-ArmState
  if (-not $arm) { Deny 'машина не взведена: нужно выполнить peer-arm -Token <код>'; return }
  if ((Get-Date) -gt [datetime]$arm.Expires) { Deny "срок взведения истёк ($($arm.Expires))"; return }
  if (-not $token) { Deny 'не передан токен'; return }
  if ((Get-StrHash $token) -ne $arm.TokenHash) { Deny 'неверный токен'; return }
  if ($arm.AllowFp -and $arm.AllowFp -ne $from) { Deny "инициатор $from не разрешён"; return }

  $allowed = @('ping','hash','status','detect','world','sync','mcjoin')
  if ($allowed -notcontains $cmd) { Deny "команда '$cmd' не в белом списке"; return }

  $myHash = Get-ToolkitHash
  if ($theirHash -and $theirHash -ne $myHash -and -not $AllowVersionDrift) {
    Write-PeerAudit "DENY cmd=$cmd from=${from}: hash mismatch"
    Write-Output 'RESULT=denied'
    Write-Output "MSG=версии скриптов разные: у меня $myHash, у инициатора $theirHash"
    return
  }
  if ($arm.Once -and [int]$arm.Uses -ge 1) { Deny 'взведение одноразовое и уже использовано'; return }

  # одноразовое взведение сжигаем ДО работы: обрыв связи не должен оставлять доступ живым
  if ($arm.Once) { Remove-Item (Get-PeerFile 'armed.json') -Force -ErrorAction SilentlyContinue }

  Write-PeerAudit "ACCEPT cmd=$cmd from=$from"
  Write-Output 'RESULT=ok'
  Write-Output "hash=$myHash"
  Write-Output "host=$env:COMPUTERNAME"

  switch ($cmd) {
    'ping'   { Write-Output 'MSG=готов' }
    'status' { Do-Status; Write-Output 'MSG=status выполнен' }
    'detect' { Do-Detect; Write-Output 'MSG=detect выполнен' }
    'mcjoin' { Do-McJoin; Write-Output 'MSG=mcjoin выполнен' }
    'world'  {
      $mode = if ($req['arg.mode']) { $req['arg.mode'] } else { 'list' }
      if ($req['arg.world'])  { $script:World = $req['arg.world'] }
      if ($req['arg.remote']) { $script:Remote = $req['arg.remote'] }
      Do-World -Mode $mode
      Write-Output "MSG=world $mode выполнен"
    }
    'sync'   {
      $ld = $req['arg.local']; $rd = $req['arg.remote']
      $mir = ($req['arg.mirror'] -eq '1')
      if (-not $ld -or -not $rd) { Write-Output 'MSG=нужны arg.local и arg.remote' }
      else {
        Write-Host "Синхронизация: $ld <-> $rd"
        $sres = Invoke-SyncPass -LocalDir $ld -RemoteDir $rd -Mirror:$mir
        Write-Output "MSG=туда=$($sres.ToRemote) обратно=$($sres.ToLocal)"
      }
    }
  }

  Write-PeerAudit "DONE cmd=$cmd"
  if ($RequestFile -and (Test-Path $RequestFile)) { Remove-Item $RequestFile -Force -ErrorAction SilentlyContinue }
}

# ================= АВТООБНОВЛЕНИЕ ИЗ GITHUB =================
# Версия лежит в файле VERSION, содержимое — в MANIFEST.txt (sha256 по каждому файлу).
# Порядок: узнать версию -> скачать архив -> ПРОВЕРИТЬ сумму и синтаксис -> бэкап -> замена.
# Ничего не заменяется, пока новый набор файлов не проверен целиком.

function Get-LocalVersion {
  $f = Join-Path $PSScriptRoot 'VERSION'
  if (Test-Path $f) { return (Get-Content $f -Raw -Encoding UTF8).Trim() }
  return '0.0.0'
}
function Compare-VersionNewer([string]$remote, [string]$local) {
  try { return ([version]$remote -gt [version]$local) } catch { return ($remote -ne $local) }
}
function Test-UpdateAllowed {
  return -not (Test-Path (Get-PeerFile 'noupdate'))
}
function Get-RemoteFileText([string]$path, [int]$TimeoutSec = 8) {
  # ?nocache — иначе CDN GitHub отдаёт файл на коммит-другой старше
  $url = "https://raw.githubusercontent.com/$UpdateRepo/$UpdateBranch/$path`?nocache=$([DateTime]::UtcNow.Ticks)"
  try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $r = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec $TimeoutSec
    return [string]$r.Content
  } catch { return $null }
}
function Get-RemoteVersion([int]$TimeoutSec = 8) {
  $t = Get-RemoteFileText 'VERSION' $TimeoutSec
  if (-not $t) { return $null }
  return $t.Trim()
}

function Do-UpdateCheck {
  param([switch]$Quiet)
  $local = Get-LocalVersion
  $remote = Get-RemoteVersion $(if ($Quiet) { 3 } else { 8 })
  if (-not $remote) {
    if (-not $Quiet) { Write-Host "  Проверить не удалось (нет интернета?) — работаю как есть." -ForegroundColor Yellow }
    return $null
  }
  if (Compare-VersionNewer $remote $local) {
    if (-not $Quiet) {
      Write-Host "  Доступна новая версия: $remote (у тебя $local)" -ForegroundColor Green
      Write-Host "  Обновить: пункт 16 меню или -Action update" -ForegroundColor Gray
    }
    return $remote
  }
  if (-not $Quiet) { Write-Host "  Версия $local — самая свежая." -ForegroundColor Green }
  return ''
}

function Do-Update {
  param([switch]$Force)
  $local = Get-LocalVersion
  Write-Host "`n=== Обновление ===" -ForegroundColor Cyan
  Write-Host "  Сейчас установлено: $local"

  $remote = Get-RemoteVersion 10
  if (-not $remote) {
    Write-Host "  [!] Не смог узнать версию на GitHub. Проверь интернет." -ForegroundColor Red
    return
  }
  Write-Host "  На GitHub          : $remote"
  if (-not $Force -and -not (Compare-VersionNewer $remote $local)) {
    Write-Host "  Обновление не нужно." -ForegroundColor Green
    return
  }

  # 1) скачиваем архив во временную папку — рабочую копию пока не трогаем
  $tmp = Join-Path $env:TEMP ('lt-upd-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
  New-Item -ItemType Directory -Force -Path $tmp | Out-Null
  $tgz = Join-Path $tmp 'lt.tar.gz'
  $url = "https://codeload.github.com/$UpdateRepo/tar.gz/refs/heads/$UpdateBranch"
  Write-Host "  Скачиваю архив..." -ForegroundColor Cyan
  try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $url -OutFile $tgz -UseBasicParsing -TimeoutSec 120
  } catch {
    Write-Host "  [!] Скачать не удалось: $($_.Exception.Message)" -ForegroundColor Red
    Remove-Item $tmp -Recurse -Force -EA SilentlyContinue
    return
  }

  $tar = Join-Path $env:SystemRoot 'System32\tar.exe'
  if (-not (Test-Path $tar)) {
    Write-Host "  [!] Нет tar.exe (нужен Windows 10 1803+). Обнови вручную: git clone репозитория." -ForegroundColor Red
    Remove-Item $tmp -Recurse -Force -EA SilentlyContinue
    return
  }
  & $tar -xzf $tgz -C $tmp 2>$null
  $root = Get-ChildItem $tmp -Directory | Select-Object -First 1
  if (-not $root) {
    Write-Host "  [!] Архив распаковался пустым." -ForegroundColor Red
    Remove-Item $tmp -Recurse -Force -EA SilentlyContinue
    return
  }
  Write-Host "  Проверяю содержимое..." -ForegroundColor Cyan

  # 2) сверяем sha256 каждого файла с MANIFEST.txt из репозитория
  # берём MANIFEST.txt ИЗ САМОГО АРХИВА: читаем с диска как UTF-8 (сеть ненадёжно
  # декодирует кириллические имена) и это гарантированно тот же коммит, что и файлы
  $manPath = Join-Path $root.FullName 'MANIFEST.txt'
  if (-not (Test-Path $manPath)) {
    Write-Host "  [!] В архиве нет MANIFEST.txt — проверить целостность не могу, отменяю." -ForegroundColor Red
    Remove-Item $tmp -Recurse -Force -EA SilentlyContinue
    return
  }
  $manifest = [IO.File]::ReadAllText($manPath, [Text.Encoding]::UTF8)
  $bad = 0; $checked = 0
  foreach ($line in ($manifest -split "`r?`n")) {
    if ($line -notmatch '^([0-9a-fA-F]{64})\s+(.+)$') { continue }
    $sum = $Matches[1].ToLower(); $name = $Matches[2].Trim()
    $fp = Join-Path $root.FullName $name
    if (-not (Test-Path -LiteralPath $fp)) { Write-Host "    [!] нет файла $name" -ForegroundColor Red; $bad++; continue }
    # LF-нормализация: архив отдаёт .ps1/.bat с CRLF, а суммы считаются без CR
    $got = Get-NormalizedHash $fp
    if ($got -ne $sum) { Write-Host "    [!] не сходится сумма: $name" -ForegroundColor Red; $bad++; continue }
    $checked++
  }
  if ($bad -gt 0 -or $checked -eq 0) {
    Write-Host "  [!] Проверка не прошла ($bad ошибок). Ничего не меняю." -ForegroundColor Red
    Remove-Item $tmp -Recurse -Force -EA SilentlyContinue
    return
  }
  Write-Host "    [+] суммы сошлись: $checked файлов" -ForegroundColor Green

  # 3) проверяем, что новые скрипты вообще рабочие (синтаксис)
  $newPs = Join-Path $root.FullName 'lan-win.ps1'
  if (Test-Path $newPs) {
    $err = $null; $tok = $null
    [System.Management.Automation.Language.Parser]::ParseFile($newPs, [ref]$tok, [ref]$err) | Out-Null
    if ($err -and $err.Count -gt 0) {
      Write-Host "  [!] Новый lan-win.ps1 не разбирается — отменяю обновление." -ForegroundColor Red
      Remove-Item $tmp -Recurse -Force -EA SilentlyContinue
      return
    }
  }
  $bash = Get-Command bash -EA SilentlyContinue
  if ($bash) {
    foreach ($sh in @('lan-linux.sh','lan-android.sh','start-linux.sh')) {
      $fp = Join-Path $root.FullName $sh
      if (Test-Path $fp) {
        & $bash.Source -n $fp 2>$null
        if ($LASTEXITCODE -ne 0) {
          Write-Host "  [!] Новый $sh с ошибкой синтаксиса — отменяю." -ForegroundColor Red
          Remove-Item $tmp -Recurse -Force -EA SilentlyContinue
          return
        }
      }
    }
  }

  # 4) бэкап текущих файлов, затем замена
  $bk = Join-Path (Get-PeerFile "backup\$local-$(Get-Date -Format 'yyyyMMdd-HHmmss')")
  New-Item -ItemType Directory -Force -Path $bk | Out-Null
  Get-ChildItem $PSScriptRoot -File | Where-Object { $_.Name -notlike '.*' } |
    ForEach-Object { Copy-Item $_.FullName (Join-Path $bk $_.Name) -Force }
  Write-Host "  Бэкап: $bk" -ForegroundColor Gray

  $n = 0
  foreach ($f in (Get-ChildItem $root.FullName -File -Recurse)) {
    $rel = $f.FullName.Substring($root.FullName.Length + 1)
    if ($rel -match '^\.git') { continue }
    $destDir = Split-Path (Join-Path $PSScriptRoot $rel) -Parent
    if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Force -Path $destDir | Out-Null }
    Copy-Item $f.FullName (Join-Path $PSScriptRoot $rel) -Force
    $n++
  }
  Remove-Item $tmp -Recurse -Force -EA SilentlyContinue
  Write-PeerAudit "update $local -> $remote ($n файлов)"
  Write-Host "`n  [+] Обновлено до $remote (файлов: $n)" -ForegroundColor Green
  Write-Host "      Откатить: .\lan-win.ps1 rollback" -ForegroundColor Gray
  Write-Host "      Вторую машину тоже обнови — иначе режим «партнёр» откажет по хешу." -ForegroundColor Yellow
}

function New-Manifest {
  $names = @('VERSION','lan-win.ps1','lan-linux.sh','lan-android.sh','mcping.py',
             'start-linux.sh','START-Windows.bat','НАЧАТЬ-Windows.bat','НАЧАТЬ-Linux.desktop',
             'README.md','.gitattributes','.gitignore')
  $lines = New-Object Collections.Generic.List[string]
  foreach ($n in $names) {
    $fp = Join-Path $PSScriptRoot $n
    if (Test-Path $fp) {
      $lines.Add(((Get-NormalizedHash $fp) + '  ' + $n))
    }
  }
  $out = Join-Path $PSScriptRoot 'MANIFEST.txt'
  [IO.File]::WriteAllText($out, (($lines -join "`n") + "`n"), (New-Object Text.UTF8Encoding($false)))
  Write-Host "[+] MANIFEST.txt обновлён: $($lines.Count) файлов" -ForegroundColor Green
}

function New-Rollback {
  $base = Get-PeerFile 'backup'
  if (-not (Test-Path $base)) { Write-Host "Бэкапов нет." -ForegroundColor Yellow; return }
  $last = Get-ChildItem $base -Directory | Sort-Object Name -Descending | Select-Object -First 1
  if (-not $last) { Write-Host "Бэкапов нет." -ForegroundColor Yellow; return }
  Write-Host "Откатываю из $($last.FullName)..." -ForegroundColor Cyan
  $n = 0
  foreach ($f in (Get-ChildItem $last.FullName -File)) {
    Copy-Item $f.FullName (Join-Path $PSScriptRoot $f.Name) -Force; $n++
  }
  Write-PeerAudit "rollback из $($last.Name) ($n файлов)"
  Write-Host "[+] Восстановлено файлов: $n (версия $(Get-LocalVersion))" -ForegroundColor Green
}

function Disable-UpdateCheck {
  'noupdate' | Set-Content -Path (Get-PeerFile 'noupdate') -Encoding UTF8
  Write-Host "[-] Проверка обновлений при запуске меню выключена." -ForegroundColor Green
}

# ================= ПРОСТОЕ МЕНЮ (для тех, кто не любит командную строку) =================
function Start-Action([string]$act, [string]$extra, [switch]$AsAdmin) {
  $exe = (Get-Process -Id $PID).Path
  $a = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"",'-Action',$act)
  if ($extra) { $a += $extra.Split(' ') }
  if ($AsAdmin) {
    Start-Process -FilePath $exe -Verb RunAs -ArgumentList $a
  } else {
    Start-Process -FilePath $exe -ArgumentList $a -Wait
  }
}

function Do-Menu {
  # один раз за запуск: тихая проверка обновлений (можно выключить: -Action no-update)
  $script:UpdateOffer = ''
  if (-not $NoUpdateCheck -and (Test-UpdateAllowed)) {
    Write-Host "  Проверяю обновления..." -ForegroundColor DarkGray
    $script:UpdateOffer = Do-UpdateCheck -Quiet
  }
  while ($true) {
    Clear-Host
    Write-Host ""
    Write-Host "  ==============================================================" -ForegroundColor Cyan
    Write-Host "        ЛОКАЛЬНАЯ СЕТЬ + MINECRAFT   (Windows)   v$(Get-LocalVersion)" -ForegroundColor Cyan
    Write-Host "  ==============================================================" -ForegroundColor Cyan
    if ($script:UpdateOffer) {
      Write-Host "   >>> ДОСТУПНО ОБНОВЛЕНИЕ $($script:UpdateOffer) — пункт 16 <<<" -ForegroundColor Green
    }
    Write-Host ""
    Write-Host "   1  Подготовить сеть (папка обмена + видимость в сети)" -ForegroundColor White
    Write-Host "   2  Показать мои адреса и состояние" -ForegroundColor White
    Write-Host "   3  Раздать файлы через браузер (телефон/линукс откроет ссылку)" -ForegroundColor White
    Write-Host "   4  Minecraft: настроить и запустить сервер" -ForegroundColor Green
    Write-Host "   5  Minecraft: показать адрес для друзей" -ForegroundColor Green
    Write-Host "   6  Включить мобильный хот-спот (если нет Wi-Fi/роутера)" -ForegroundColor White
    Write-Host "   7  Подключиться к чужой папке в сети (по IP)" -ForegroundColor White
    Write-Host "   9  Minecraft: найти запущенную игру и LAN-порт (клиент-клиент)" -ForegroundColor Green
    Write-Host "  10  Minecraft: перенести/синхронизировать мир между машинами" -ForegroundColor Green
    Write-Host "  11  Двусторонняя общая папка (файлы туда-обратно, с автообновлением)" -ForegroundColor White
    Write-Host "  12  ПАРТНЁР по SSH: ключ, залить скрипты, проверить связь" -ForegroundColor Magenta
    Write-Host "  13  Разрешить приём с другой машины на N минут (взвести)" -ForegroundColor Magenta
    Write-Host "  14  Синхронизация с партнёром по SSH (обе стороны сами)" -ForegroundColor Magenta
    Write-Host "  15  Журнал удалённых действий" -ForegroundColor DarkGray
    Write-Host "  16  Проверить и установить обновление" -ForegroundColor Cyan
    Write-Host "   8  Убрать все настройки этой программы" -ForegroundColor DarkGray
    Write-Host "   0  Выход" -ForegroundColor DarkGray
    Write-Host ""
    $c = Read-Host "  Введи цифру и нажми Enter"

    switch ($c) {
      '1' { Start-Action 'setup' '' -AsAdmin }
      '2' { Start-Action 'status' '' }
      '3' {
        $p = Read-Host "  Порт для раздачи (Enter = 8080)"
        if (-not $p) { $p = '8080' }
        Start-Action 'http' "-Port $p" -AsAdmin
      }
      '4' {
        $mem = Read-Host "  Сколько памяти дать серверу в ГБ (Enter = 2)"
        if (-not $mem) { $mem = '2' }
        Start-Action 'minecraft' "-McMem ${mem}G" -AsAdmin
      }
      '5' { Start-Action 'mc' '' }
      '6' { Start-Action 'hotspot' '-On' -AsAdmin }
      '7' {
        Write-Host "  Пример адреса: \\192.168.1.50\LAN" -ForegroundColor Gray
        $r = Read-Host "  Введи адрес чужой папки"
        if ($r) { Start-Action 'mount' "-Remote `"$r`"" -AsAdmin }
      }
      '8' { Start-Action 'remove' '' -AsAdmin }
      '9' { Start-Action 'detect' '' -AsAdmin }
      '12' {
        Write-Host "`n  Что делаем с партнёром?" -ForegroundColor Cyan
        Write-Host "   1 — создать ключ тулкита (нужно один раз)"
        Write-Host "   2 — добавить партнёра по IP"
        Write-Host "   3 — залить скрипты на партнёра"
        Write-Host "   4 — проверить связь"
        Write-Host "   5 — показать список партнёров"
        $s = Read-Host "  Цифра"
        switch ($s) {
          '1' { Do-PeerKeygen }
          '2' {
            $n = Read-Host "  Имя партнёра (латиницей, например pc2)"
            $h = Read-Host "  IP партнёра"
            $u = Read-Host "  Логин на партнёре (Enter = как тут: $env:USERNAME)"
            $pl = Read-Host "  Система партнёра: [1] Windows [2] Linux [3] Android (Enter=2)"
            $script:Peer = $n; $script:PeerHost = $h
            if ($u) { $script:PeerUser = $u }
            $script:PeerPlatform = switch ($pl) { '1' { 'win' } '3' { 'android' } default { 'linux' } }
            Do-PeerAdd
          }
          '3' { $script:Peer = (Read-Host "  Имя партнёра"); Do-PeerBootstrap }
          '4' { $script:Peer = (Read-Host "  Имя партнёра"); Do-PeerTest }
          '5' { Do-PeerListCmd }
        }
      }
      '13' {
        Write-Host "`n  Придумай код (6+ символов) и скажи его тому, кто будет подключаться." -ForegroundColor Yellow
        Write-Host "  Пока код действует, та машина сможет попросить эту синхронизироваться." -ForegroundColor Gray
        $t = Read-Host "  Код (не показывается на экране — можно так и оставить пустым и отменить)"
        if ($t) {
          $m = Read-Host "  На сколько минут (Enter = 30, максимум 240)"
          $script:Token = $t
          if ($m) { $script:Minutes = [int]$m }
          Do-PeerArm
        }
      }
      '14' {
        Do-PeerListCmd
        $n = Read-Host "  Имя партнёра"
        if ($n) {
          $script:Peer = $n
          $ld = Read-Host "  Моя папка (Enter = общая папка программы\обмен)"
          $rd = Read-Host "  Папка на партнёре (Enter = то же имя у него)"
          $sec = Read-Host "  Обновлять каждые N секунд? (Enter = один раз)"
          if ($ld) { $script:Local = $ld }
          if ($rd) { $script:RemoteDir = $rd }
          if ($sec) { $script:Watch = [int]$sec }
          $tk = Read-Host "  Код, который сказал человек на той машине (нужен, если там взведено)"
          if ($tk) { $script:Token = $tk }
          Do-PeerSync
        }
      }
      '15' { Do-PeerLog }
      '16' {
        Do-Update
        $script:UpdateOffer = ''
      }
      '10' {
        Write-Host "  Сначала посмотри список миров:"
        Start-Action 'world' '-WorldMode list' -AsAdmin
        Write-Host ""
        $wname = Read-Host "  Имя мира (Enter = самый свежий)"
        $raddr = Read-Host "  Общая папка другой машины (\\IP\LAN) или Enter = своя"
        $mode  = Read-Host "  Что делать: [1] отдать  [2] забрать  [3] синхронизировать (Enter=3)"
        $m = switch ($mode) { '1' { 'push' } '2' { 'pull' } default { 'sync' } }
        $ex = "-WorldMode $m"
        if ($wname) { $ex += " -World `"$wname`"" }
        if ($raddr) { $ex += " -Remote `"$raddr\mcworlds`"" }
        Start-Action 'world' $ex -AsAdmin
      }
      '11' {
        $ldir = Read-Host "  Локальная папка (Enter = общая папка программы)"
        $rdir = Read-Host "  Папка на другом ПК (\\IP\LAN\обмен)"
        if (-not $rdir) { Write-Host "  Нужен адрес второй машины." -ForegroundColor Yellow; Start-Sleep 2 }
        else {
          $sec = Read-Host "  Обновлять каждые N секунд? (Enter = один раз)"
          $ex = "-Remote `"$rdir`""
          if ($ldir) { $ex += " -Local `"$ldir`"" }
          if ($sec)  { $ex += " -Watch $sec" }
          Start-Action 'sync' $ex -AsAdmin
        }
      }
      '0' { return }
      default { Write-Host "  Не понял. Введи цифру из списка." -ForegroundColor Yellow; Start-Sleep 2 }
    }
    if ($c -in '1','2','3','4','5','7','8','9','10','11','12','13','14','15','16') {
      Write-Host ""
      Read-Host "  Готово. Нажми Enter, чтобы вернуться в меню"
    }
  }
}

switch ($Action) {
  'menu'      { Do-Menu }
  'setup'   { Do-Setup }
  'minecraft' { Do-Minecraft }
  'mc'        { Do-McJoin }
  'detect'    { Do-Detect }
  'world'     { Do-World -Mode $WorldMode }
  'sync'      { Do-Sync }
  'status'  { Do-Status }
  'http'    { Do-Http }
  'hotspot' { Do-Hotspot }
  'mount'   { Do-Mount }
  'unmount' { Do-Unmount }
  'remove'  { Do-Remove }
  'peer-keygen'    { Do-PeerKeygen }
  'peer-add'       { Do-PeerAdd }
  'peer-list'      { Do-PeerListCmd }
  'peer-forget'    { Do-PeerForget }
  'peer-arm'       { Do-PeerArm }
  'peer-disarm'    { Do-PeerDisarm }
  'peer-test'      { Do-PeerTest }
  'peer-bootstrap' { Do-PeerBootstrap }
  'peer-run'       { Do-PeerRun }
  'peer-sync'      { Do-PeerSync }
  'peer-serve'     { Do-PeerServe -RequestFile $RequestFile }
  'peer-log'       { Do-PeerLog }
  'update'         { Do-Update }
  'update-check'   { Do-UpdateCheck | Out-Null }
  'update-manifest'{ New-Manifest }
  'rollback'       { New-Rollback }
  'no-update'      { Disable-UpdateCheck }
}
