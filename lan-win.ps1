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
  [ValidateSet('setup','status','http','hotspot','mount','unmount','remove','minecraft','mc','menu','detect','world','sync')]
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
  [switch]$On
)

$ErrorActionPreference = 'Continue'

# ---------- self-elevate ----------
function Test-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
}
if (-not (Test-Admin) -and $Action -notin 'menu','status','mc','detect','world','sync') {
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

  $rc = @('/E','/XO','/R:1','/W:1','/NFL','/NDL','/NJH','/NJS','/NP')
  if ($Mirror) { $rc += '/MIR' }

  $pass = {
    Write-Host ("  [{0}] туда..." -f (Get-Date -Format 'HH:mm:ss')) -ForegroundColor Cyan
    $null = robocopy $localDir $remoteDir @rc; Write-Host "     -> $(Get-RobocopyCode $LASTEXITCODE)"
    Write-Host ("  [{0}] обратно..." -f (Get-Date -Format 'HH:mm:ss')) -ForegroundColor Cyan
    $null = robocopy $remoteDir $localDir @rc; Write-Host "     -> $(Get-RobocopyCode $LASTEXITCODE)"
  }
  & $pass
  if ($Watch -and [int]$Watch -gt 0) {
    Write-Host "  Слежение каждые $Watch сек. Ctrl+C — стоп." -ForegroundColor Green
    while ($true) { Start-Sleep -Seconds ([int]$Watch); & $pass }
  } else {
    Write-Host "  Один проход завершён. Для постоянного обмена: -Watch 30" -ForegroundColor Gray
  }
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
  while ($true) {
    Clear-Host
    Write-Host ""
    Write-Host "  ==============================================================" -ForegroundColor Cyan
    Write-Host "        ЛОКАЛЬНАЯ СЕТЬ + MINECRAFT   (Windows)                  " -ForegroundColor Cyan
    Write-Host "  ==============================================================" -ForegroundColor Cyan
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
    if ($c -in '1','2','3','4','5','7','8','9','10','11') {
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
}
