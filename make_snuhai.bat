@echo off
chcp 65001 >nul 2>&1
setlocal enabledelayedexpansion
REM ============================================================================
REM  make_snuhai.bat - build the distributable bundle (snuhai-cli).
REM
REM  Run this ONCE on a machine with internet access.
REM    Then copy the resulting snuhai-cli.zip to the air-gapped machine and
REM    run snuhai.bat inside it.
REM
REM    make_snuhai.bat [win^|linux^|both]      default: win
REM ============================================================================
set "HERE=%~dp0"
set "SRC=%HERE%src"
set "TARGET=%~1"
if "%TARGET%"=="" set "TARGET=win"
set "OUT=%HERE%snuhai-cli"
set "LIB=%OUT%\.snuhai"
if not defined CODEX_VER set "CODEX_VER=0.145.0"
if not defined NODE_VER  set "NODE_VER=24.18.0"

where npm  >nul 2>&1 || ( echo [ERROR] npm is required ^(run on a machine with internet^) & pause & exit /b 1 )
where curl >nul 2>&1 || ( echo [ERROR] curl is required & pause & exit /b 1 )

echo ============================================================
echo   Building snuhai bundle  ^(codex %CODEX_VER% / node %NODE_VER% / target=%TARGET%^)
echo ============================================================
if exist "%OUT%" rmdir /s /q "%OUT%"
mkdir "%LIB%\packages" 2>nul
mkdir "%LIB%\node" 2>nul

echo.
echo [1/4] Downloading Codex CLI...
pushd "%LIB%\packages"
call npm pack "@openai/codex@%CODEX_VER%" >nul 2>&1
if /i not "%TARGET%"=="linux" call npm pack "@openai/codex@%CODEX_VER%-win32-x64" >nul 2>&1
if /i not "%TARGET%"=="win"   call npm pack "@openai/codex@%CODEX_VER%-linux-x64" >nul 2>&1
dir /b *.tgz
popd

echo.
echo [2/4] Downloading portable Node.js...
pushd "%LIB%\node"
if /i not "%TARGET%"=="linux" (
  curl -fsSLO "https://nodejs.org/dist/v%NODE_VER%/node-v%NODE_VER%-win-x64.zip"
  if errorlevel 1 ( echo [ERROR] Node download failed & popd & pause & exit /b 1 )
  tar -xf "node-v%NODE_VER%-win-x64.zip"
  del /q "node-v%NODE_VER%-win-x64.zip"
)
if /i not "%TARGET%"=="win" (
  curl -fsSLO "https://nodejs.org/dist/v%NODE_VER%/node-v%NODE_VER%-linux-x64.tar.xz"
  tar -xf "node-v%NODE_VER%-linux-x64.tar.xz"
  del /q "node-v%NODE_VER%-linux-x64.tar.xz"
)
popd

echo.
echo [3/4] Laying out the bundle...
copy /y "%SRC%\gateway.js" "%LIB%\gateway.js" >nul
if exist "%HERE%NOTICE"  copy /y "%HERE%NOTICE"  "%LIB%\NOTICE"  >nul
if exist "%HERE%LICENSE" copy /y "%HERE%LICENSE" "%LIB%\LICENSE" >nul
copy /y "%SRC%\snuhai.bat" "%OUT%\snuhai.bat" >nul
copy /y "%SRC%\snuhai.sh"  "%OUT%\snuhai.sh"  >nul
> "%OUT%\README.txt" echo snuhai - run Codex CLI against an internal LLM server
>>"%OUT%\README.txt" echo.
>>"%OUT%\README.txt" echo   Windows : double-click  snuhai.bat
>>"%OUT%\README.txt" echo   Linux   : run  ./snuhai.sh
>>"%OUT%\README.txt" echo.
>>"%OUT%\README.txt" echo On first run it asks once for the server URL, your API key and a model.
>>"%OUT%\README.txt" echo After that it starts straight away. No internet required.
>>"%OUT%\README.txt" echo.
>>"%OUT%\README.txt" echo (.snuhai holds everything it needs to run - do not delete it.)
attrib +h "%LIB%" 2>nul

echo.
echo [4/4] Creating the ZIP...
pushd "%HERE%"
if exist "snuhai-cli.zip" del /q "snuhai-cli.zip"
tar -a -c -f "snuhai-cli.zip" "snuhai-cli" 2>nul
if not exist "snuhai-cli.zip" powershell -NoProfile -Command "Compress-Archive -Path 'snuhai-cli' -DestinationPath 'snuhai-cli.zip' -Force"
certutil -hashfile "snuhai-cli.zip" SHA256 | findstr /v ":" | findstr /r "[0-9a-f]" > "snuhai-cli.zip.sha256"
if /i not "%KEEP_DIR%"=="1" rmdir /s /q "snuhai-cli"
popd

echo.
echo ============================================================
echo  Done
echo ============================================================
echo   file: %HERE%snuhai-cli.zip
echo   sha256: snuhai-cli.zip.sha256
echo.
echo   Copy this single ZIP to the air-gapped machine:
echo     1^) unzip it
echo     2^) double-click snuhai.bat
echo.
echo   ^(keep the unzipped folder too: set KEEP_DIR=1 first^)
pause
