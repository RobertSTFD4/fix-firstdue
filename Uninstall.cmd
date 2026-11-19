@echo off
rem Removes the "Fix First Due" shortcut from this PC. Windows will ask for administrator rights.
net session >nul 2>&1
if errorlevel 1 (
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\Uninstall.ps1" %*
echo.
echo Fix First Due has been removed from this PC.
echo.
pause
