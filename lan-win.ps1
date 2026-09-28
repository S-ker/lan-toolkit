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
  [ValidateSet('setup','status','http','hotspot','mount','unmount','remove','minecraft','mc','menu')]
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
  [switch]$On
)

$ErrorActionPreference = 'Continue'

# ---------- self-elevate ----------
function Test-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
}
if (-not (Test-Admin) -and $Action -ne 'menu' -and $Action -ne 'status' -and $Action -ne 'mc') {
  Write-Host "" ; Write-Host "  Сейчас Windows спросит разрешение — нажми ДА." -ForegroundColor Yellow
  $exe = (Get-Process -Id $PID).Path
  $arg = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Action $Action " +
         "-ShareName `"$ShareName`" -Path `"$Path`" -Port $Port -Drive $Drive"
  if ($Remote) { $arg += " -Remote `"$Remote`"" }
  if ($User)   { $arg += " -User `"$User`"" }
  if ($McDir)  { $arg += " -McDir `"$McDir`" -McMem `"$McMem`" -McPort $McPort" }
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
  Write-Host "  [+] firewall: $name ($proto/$ports)"
}

function Open-Firewall {
  Enable-NetFirewallRule -DisplayGroup 'File and Printer Sharing' -ErrorAction SilentlyContinue
  Enable-NetFirewallRule -DisplayGroup 'Network Discovery'       -ErrorAction SilentlyContinue
  Add-FwRule 'LAN Toolkit SMB'      'TCP' '445,139'
  Add-FwRule 'LAN Toolkit NetBIOS'  'UDP' '137,138'
  Add-FwRule 'LAN Toolkit WSD'      'TCP' '5357'
  Add-FwRule 'LAN Toolkit WSD-UDP'  'UDP' '3702'
  Add-FwRule 'LAN Toolkit mDNS'     'UDP' '5353'
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
      '0' { return }
      default { Write-Host "  Не понял. Введи цифру из списка." -ForegroundColor Yellow; Start-Sleep 2 }
    }
    if ($c -in '1','2','3','4','5','7','8') {
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
  'status'  { Do-Status }
  'http'    { Do-Http }
  'hotspot' { Do-Hotspot }
  'mount'   { Do-Mount }
  'unmount' { Do-Unmount }
  'remove'  { Do-Remove }
}
