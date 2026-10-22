@echo off
rem Pushes an exported Windows build to itch.io with butler.
rem
rem   tools\push_to_itch.bat <folder with the unzipped build> <version>
rem   example: tools\push_to_itch.bat C:\itch\cowdog-windows 0.4
rem
rem One-time setup: install butler and run "butler login" (see docs\ITCH.md).
rem Edit the next line: your itch.io user name, the page's URL name, and the channel (keep "windows").
set TARGET=YOUR-USER-NAME/YOUR-GAME-URL-NAME:windows

if "%~1"=="" (echo Usage: push_to_itch.bat ^<build folder^> ^<version^> & exit /b 1)
if "%~2"=="" (echo Usage: push_to_itch.bat ^<build folder^> ^<version^> & exit /b 1)
butler push "%~1" %TARGET% --userversion %2
butler status %TARGET%
