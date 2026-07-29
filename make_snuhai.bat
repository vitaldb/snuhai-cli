@echo off
chcp 65001 >nul 2>&1
setlocal enabledelayedexpansion
REM ============================================================================
REM  make_snuhai.bat — 배포 폴더(snuhai-cli)를 만든다.
REM
REM  ★ 인터넷이 되는 PC에서 한 번만 실행한다.
REM    만들어진 snuhai-cli 폴더를 통째로 폐쇄망 PC로 옮기고,
REM    그 안의 snuhai.bat 을 실행하면 끝이다.
REM
REM    make_snuhai.bat [win^|linux^|both]      기본값: win
REM ============================================================================
set "HERE=%~dp0"
set "SRC=%HERE%src"
set "TARGET=%~1"
if "%TARGET%"=="" set "TARGET=win"
set "OUT=%HERE%snuhai-cli"
set "LIB=%OUT%\.snuhai"
if not defined CODEX_VER set "CODEX_VER=0.145.0"
if not defined NODE_VER  set "NODE_VER=24.18.0"

where npm  >nul 2>&1 || ( echo [ERROR] npm 이 필요합니다 ^(인터넷 되는 PC에서 실행^) & pause & exit /b 1 )
where curl >nul 2>&1 || ( echo [ERROR] curl 이 필요합니다 & pause & exit /b 1 )

echo ============================================================
echo   snuhai 번들 생성  ^(codex %CODEX_VER% / node %NODE_VER% / target=%TARGET%^)
echo ============================================================
if exist "%OUT%" rmdir /s /q "%OUT%"
mkdir "%LIB%\packages" 2>nul
mkdir "%LIB%\node" 2>nul

echo.
echo [1/4] Codex CLI 내려받기...
pushd "%LIB%\packages"
call npm pack "@openai/codex@%CODEX_VER%" >nul 2>&1
if /i not "%TARGET%"=="linux" call npm pack "@openai/codex@%CODEX_VER%-win32-x64" >nul 2>&1
if /i not "%TARGET%"=="win"   call npm pack "@openai/codex@%CODEX_VER%-linux-x64" >nul 2>&1
dir /b *.tgz
popd

echo.
echo [2/4] 포터블 Node.js 내려받기...
pushd "%LIB%\node"
if /i not "%TARGET%"=="linux" (
  curl -fsSLO "https://nodejs.org/dist/v%NODE_VER%/node-v%NODE_VER%-win-x64.zip"
  if errorlevel 1 ( echo [ERROR] Node 다운로드 실패 & popd & pause & exit /b 1 )
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
echo [3/4] 실행 파일 배치...
copy /y "%SRC%\gateway.js" "%LIB%\gateway.js" >nul
if exist "%HERE%NOTICE"  copy /y "%HERE%NOTICE"  "%LIB%\NOTICE"  >nul
if exist "%HERE%LICENSE" copy /y "%HERE%LICENSE" "%LIB%\LICENSE" >nul
copy /y "%SRC%\snuhai.bat" "%OUT%\snuhai.bat" >nul
copy /y "%SRC%\snuhai.sh"  "%OUT%\snuhai.sh"  >nul
> "%OUT%\읽어보세요.txt" echo snuhai - 사내 LLM 서버로 Codex CLI 쓰기
>>"%OUT%\읽어보세요.txt" echo.
>>"%OUT%\읽어보세요.txt" echo   Windows : snuhai.bat 을 더블클릭하세요.
>>"%OUT%\읽어보세요.txt" echo   Linux   : ./snuhai.sh 를 실행하세요.
>>"%OUT%\읽어보세요.txt" echo.
>>"%OUT%\읽어보세요.txt" echo 처음 실행하면 서버 주소, API 키, 모델을 한 번만 물어봅니다.
>>"%OUT%\읽어보세요.txt" echo 그 다음부터는 바로 실행됩니다. 인터넷은 필요하지 않습니다.
>>"%OUT%\읽어보세요.txt" echo.
>>"%OUT%\읽어보세요.txt" echo (.snuhai 폴더에는 실행에 필요한 파일이 들어 있습니다. 지우지 마세요.)
attrib +h "%LIB%" 2>nul

echo.
echo [4/4] 완료
echo.
echo 만들어진 폴더:  %OUT%
echo   이 폴더를 통째로 폐쇄망 PC 로 옮긴 뒤 snuhai.bat 을 실행하세요.
pause
