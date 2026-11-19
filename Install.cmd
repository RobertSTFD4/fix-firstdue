@echo off
rem Installs the "Fix First Due" shortcut for everyone on this PC. Windows will ask for administrator rights.
net session >nul 2>&1
if errorlevel 1 (
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\Install.ps1" %*
if errorlevel 1 (
  echo.
  echo Install FAILED. Send a screenshot of this window to your IT support.
) else (
  echo.
  echo Done. The "Fix First Due" shortcut is now on the desktop and in the Start menu.
)
echo.
pause
