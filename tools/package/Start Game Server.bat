@echo off
rem Starts the Cowdog game server (room codes) on this PC, and a free Cloudflare tunnel if cloudflared.exe is next to this file.
title Cowdog game server
cd /d "%~dp0"
set PORT=24681

if exist cloudflared.exe (
  echo Starting the tunnel in a new window. Look there for an address like https://something.trycloudflare.com
  echo Give friends that address (without the https://) - they type it as the "game server" in the Multiplayer screen.
  start "Cowdog tunnel" cmd /k cloudflared.exe tunnel --url http://127.0.0.1:%PORT%
) else (
  echo cloudflared.exe not found next to this file, so only players on your own network can connect:
  echo give them this PC's IP address followed by :%PORT%   e.g. 192.168.1.20:%PORT%
  echo For friends elsewhere, download cloudflared.exe - see HOW_TO_PLAY.txt.
)
echo.
echo Game server running. Close this window to stop it.
echo.
CowdogCardGame.console.exe --headless -- --relay --port=%PORT%
pause
