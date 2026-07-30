@echo off
REM Switch the console to UTF-8 so output renders consistently.
REM Note: with a UTF-8 console, cmd's `set /p` cannot read redirected stdin.
REM When scripting the answers, run with SNUHAI_NO_UTF8=1.
if not "%SNUHAI_NO_UTF8%"=="1" chcp 65001 >nul 2>&1
setlocal enabledelayedexpansion
REM ============================================================
REM  snuhai - run Codex CLI against an internal LLM server (air-gapped)
REM  Run this one file. It installs and configures itself on first use.
REM ============================================================
set "HERE=%~dp0"
set "LIB=%HERE%.snuhai"
set "CFG=%USERPROFILE%\.snuhai"
set "CODEX_HOME=%CFG%\codex"
set "DISABLE_AUTOUPDATER=1"

if not exist "%LIB%" ( echo [ERROR] .snuhai folder is missing. Copy the whole folder. & pause & exit /b 1 )
set "NODEDIR="
for /d %%d in ("%LIB%\node\node-v*-win-x64") do set "NODEDIR=%%d"
if not defined NODEDIR ( echo [ERROR] No bundled Node found. & pause & exit /b 1 )
set "PATH=%NODEDIR%;%PATH%"
if not exist "%CFG%" mkdir "%CFG%"
if not exist "%CODEX_HOME%" mkdir "%CODEX_HOME%"

REM ---------- 1) first run only: install Codex offline ----------
if not exist "%LIB%\installed.flag" (
  echo [setup] Installing Codex CLI ^(first run only, no internet needed^)...
  set "MAIN="
  for %%f in ("%LIB%\packages\openai-codex-*.tgz") do (
    echo %%~nf | findstr /i "linux-x64 win32-x64" >nul || set "MAIN=%%f"
  )
  if not defined MAIN ( echo [ERROR] No codex tarball in packages\. & pause & exit /b 1 )
  call npm install -g --offline --no-audit --no-fund "!MAIN!" >"%CFG%\install.log" 2>&1
  if errorlevel 1 ( echo [ERROR] Install failed - see "%CFG%\install.log" & pause & exit /b 1 )
  for %%f in ("%LIB%\packages\openai-codex-*-win32-x64.tgz") do set "NATIVE=%%f"
  if defined NATIVE (
    for /f "delims=" %%r in ('npm root -g') do set "NPMROOT=%%r"
    set "TMPD=%TEMP%\cxv%RANDOM%"
    mkdir "!TMPD!"
    tar -xzf "!NATIVE!" -C "!TMPD!" package/vendor
    if not exist "!NPMROOT!\@openai\codex\vendor" mkdir "!NPMROOT!\@openai\codex\vendor"
    xcopy /e /i /y "!TMPD!\package\vendor" "!NPMROOT!\@openai\codex\vendor" >nul
    rmdir /s /q "!TMPD!"
  )
  echo ok> "%LIB%\installed.flag"
  echo [setup] Done.
)

REM ---------- 2) first run only: server, key, model ----------
if not exist "%CFG%\conf.bat" (
  echo.
  echo ============================================================
  echo   snuhai first-time setup
  echo ============================================================
  echo.
  echo  [1] Internal LLM server URL
  echo      Press Enter to use the Seoul National University Hospital default.
  echo      default: https://llm.snuh.org/llm
  set "EP="
  set /p "EP=Server URL (Enter = default): "
  if not defined EP set "EP=https://llm.snuh.org/llm"
  echo.
  echo  [2] How to get an API key ^(from the intranet^)
  echo      1. Open  https://ai.snuh.org  in your browser
  echo      2. Sign in with your SNUHUB account
  echo      3. Left menu:  MY ^> My Key Management  [나의 키 관리]
  echo         ^(direct link: ai.snuh.org/setting/my-key^)
  echo      4. Click  + Add  [추가]  at the top right
  echo      5. Type = LLM, description e.g. snuhai-cli, then issue it
  echo      6. Copy the key value ^(starts with sk-^) and paste it below
  echo         ^(right-click in this window = paste^)
  echo.
  set /p "KEY=API key: "
  if not defined KEY ( echo [ERROR] A key is required. & pause & exit /b 1 )
  echo.
  echo  Fetching available models...
  curl -s -H "Authorization: Bearer !KEY!" "!EP!/models" > "%CFG%\models.json" 2>nul
  findstr /i "\"id\"" "%CFG%\models.json"
  echo.
  set /p "MODEL=Model name: "
  if not defined MODEL ( echo [ERROR] A model is required. & pause & exit /b 1 )
  echo.
  echo  Checking whether the server supports the Responses API...
  for /f %%c in ('curl -s -o nul -w "%%{http_code}" -X POST -H "Authorization: Bearer !KEY!" -H "Content-Type: application/json" -d "{\"model\":\"!MODEL!\",\"input\":\"hi\"}" "!EP!/responses"') do set "RC=%%c"
  if "!RC!"=="200" ( set "GW=0" & echo   -^> direct connection ^(Responses API supported^) ) else ( set "GW=1" & echo   -^> using the gateway ^(chat-only server, HTTP !RC!^) )
  ^> "%CFG%\conf.bat" echo set "EP=!EP!"
  ^>^> "%CFG%\conf.bat" echo set "KEY=!KEY!"
  ^>^> "%CFG%\conf.bat" echo set "MODEL=!MODEL!"
  ^>^> "%CFG%\conf.bat" echo set "GW=!GW!"
  echo.
  echo  Saved to %CFG%\conf.bat
  echo  ^(delete that file and run again to reconfigure^)
  echo.
)
call "%CFG%\conf.bat"

REM ---------- 3) write the codex config ----------
if "%GW%"=="1" ( set "BASE=http://127.0.0.1:4600/v1" ) else ( set "BASE=%EP%" )
> "%CODEX_HOME%\config.toml" echo model = "%MODEL%"
>> "%CODEX_HOME%\config.toml" echo model_provider = "snuhai"
>> "%CODEX_HOME%\config.toml" echo.
>> "%CODEX_HOME%\config.toml" echo [model_providers.snuhai]
>> "%CODEX_HOME%\config.toml" echo name = "snuhai"
>> "%CODEX_HOME%\config.toml" echo base_url = "%BASE%"
>> "%CODEX_HOME%\config.toml" echo wire_api = "responses"
>> "%CODEX_HOME%\config.toml" echo env_key = "SNUHAI_API_KEY"
>> "%CODEX_HOME%\config.toml" echo.
>> "%CODEX_HOME%\config.toml" echo [model_properties."%MODEL%"]
>> "%CODEX_HOME%\config.toml" echo context_window = 131072
>> "%CODEX_HOME%\config.toml" echo supports_reasoning_summaries = false
>> "%CODEX_HOME%\config.toml" echo input_modalities = ["text"]
set "SNUHAI_API_KEY=%KEY%"

REM ---------- 4) start the gateway if needed ----------
set "GWPID="
if "%GW%"=="1" (
  echo [gateway] starting...
  set "GW_UPSTREAM=%EP%"
  for /f %%p in ('powershell -NoProfile -Command "(Start-Process -FilePath '%NODEDIR%\node.exe' -ArgumentList '\"%LIB%\gateway.js\"' -PassThru -WindowStyle Hidden).Id"') do set "GWPID=%%p"
  timeout /t 2 /nobreak >nul
)

REM ---------- 5) run codex ----------
call codex %*

if defined GWPID taskkill /f /pid %GWPID% >nul 2>&1
endlocal
