@echo off
rem ===================================================================
rem  DOUBLE-CLICK THIS FILE. It opens a Russian menu. No typing needed.
rem  Keep this file next to lan-win.ps1
rem  (ASCII only on purpose: non-ASCII text in .bat breaks on some PCs)
rem ===================================================================
title Local network + Minecraft
setlocal
set "PSEXE=powershell"
where pwsh >nul 2>&1 && set "PSEXE=pwsh"
"%PSEXE%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0lan-win.ps1" -Action menu
if errorlevel 1 (
  echo.
  echo   [!] Could not start the menu.
  echo       Make sure lan-win.ps1 is in the same folder as this .bat
  echo       and that PowerShell is allowed to run scripts.
  echo.
  pause
)
endlocal