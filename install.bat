@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0app\install.ps1"
echo.
echo Done. Sign in with Google in the widget.
timeout /t 5
