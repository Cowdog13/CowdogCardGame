@echo off
rem Starts the Cowdog game server (room codes) on this PC, plus a free Cloudflare tunnel if cloudflared is in this folder.
title Cowdog game server
cd /d "%~dp0"
set PORT=24681
set TUNNEL=
if exist cloudflared.exe set TUNNEL=cloudflared.exe
if exist cloudflared-windows-amd64.exe set TUNNEL=cloudflared-windows-amd64.exe

if not exist CowdogCardGame.console.exe goto nogame
if "%TUNNEL%"=="" goto notunnel

echo Starting the tunnel in a new window.
echo In THAT window, look for an address like https://something.trycloudflare.com
echo Give friends the part after https:// as the game server address.
start "Cowdog tunnel" cmd /k "%TUNNEL% tunnel --url http://127.0.0.1:%PORT%"
goto run

:notunnel
echo No cloudflared file found in this folder, so only players on your own network can connect.
echo They would type this PC's IP address followed by :%PORT%  for example 192.168.1.20:%PORT%
echo For friends elsewhere put cloudflared.exe in this folder - see HOW_TO_PLAY.txt
goto run

:nogame
echo CowdogCardGame.console.exe was not found next to this file.
echo Unzip the whole download into a folder first, then run this file from that folder.
echo.
pause
exit /b 1

:run
echo.
echo Game server running on port %PORT%. Leave this window open while people play. Close it to stop the server.
echo.
CowdogCardGame.console.exe --headless -- --relay --port=%PORT%
echo.
echo The server stopped. Any message above says why.
pause
