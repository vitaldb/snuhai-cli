@echo off
chcp 65001 >nul 2>&1
setlocal enabledelayedexpansion
REM ============================================================
REM  snuhai — 사내 LLM 서버로 Codex CLI 실행 (폐쇄망용)
REM  이 파일 하나만 실행하면 된다. 최초 실행 시 설치·설정을 자동으로 한다.
REM ============================================================
set "HERE=%~dp0"
set "LIB=%HERE%.snuhai"
set "CFG=%USERPROFILE%\.snuhai"
set "CODEX_HOME=%CFG%\codex"
set "DISABLE_AUTOUPDATER=1"

if not exist "%LIB%" ( echo [ERROR] .snuhai 폴더가 없습니다. 번들이 손상되었습니다. & pause & exit /b 1 )
set "NODEDIR="
for /d %%d in ("%LIB%\node\node-v*-win-x64") do set "NODEDIR=%%d"
if not defined NODEDIR ( echo [ERROR] 번들에 Node 가 없습니다. & pause & exit /b 1 )
set "PATH=%NODEDIR%;%PATH%"
if not exist "%CFG%" mkdir "%CFG%"
if not exist "%CODEX_HOME%" mkdir "%CODEX_HOME%"

REM ---------- 1) 최초 1회: codex 오프라인 설치 ----------
if not exist "%LIB%\installed.flag" (
  echo [설치] Codex CLI 를 설치합니다 ^(최초 1회, 인터넷 불필요^)...
  set "MAIN="
  for %%f in ("%LIB%\packages\openai-codex-*.tgz") do (
    echo %%~nf | findstr /i "linux-x64 win32-x64" >nul || set "MAIN=%%f"
  )
  if not defined MAIN ( echo [ERROR] packages 에 codex tarball 이 없습니다. & pause & exit /b 1 )
  call npm install -g --offline --no-audit --no-fund "!MAIN!" >nul 2>&1
  if errorlevel 1 ( echo [ERROR] 설치 실패 & pause & exit /b 1 )
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
  echo [설치] 완료
)

REM ---------- 2) 최초 1회: 서버·키·모델 설정 ----------
if not exist "%CFG%\conf.bat" (
  echo.
  echo ============================================================
  echo   snuhai 최초 설정
  echo ============================================================
  echo.
  echo  [1] 사내 LLM 서버 주소
  echo      그냥 Enter 를 누르면 서울대학교병원 기본값을 사용합니다.
  echo      기본값: https://llm.snuh.org/llm
  set "EP="
  set /p "EP=서버 주소 (Enter=기본값): "
  if not defined EP set "EP=https://llm.snuh.org/llm"
  echo.
  echo  [2] API 키 발급 방법 ^(원내망에서^)
  echo      1. 브라우저로  https://ai.snuh.org  접속
  echo      2. SNUHUB 계정으로 로그인
  echo      3. 왼쪽 메뉴  MY ^> 나의 키 관리   ^(주소: ai.snuh.org/setting/my-key^)
  echo      4. 오른쪽 위  + 추가  클릭
  echo      5. 구분 LLM 선택, 설명에 snuhai-cli 등을 입력하고 발급
  echo      6. 만들어진 키 값 ^(sk- 로 시작^) 을 복사해 아래에 붙여넣기
  echo         ^(이 창에서 마우스 오른쪽 클릭 = 붙여넣기^)
  echo.
  set /p "KEY=API 키: "
  if not defined KEY ( echo [ERROR] 키가 필요합니다. & pause & exit /b 1 )
  echo.
  echo  사용 가능한 모델을 조회합니다...
  curl -s -H "Authorization: Bearer !KEY!" "!EP!/models" > "%CFG%\models.json" 2>nul
  findstr /i "\"id\"" "%CFG%\models.json"
  echo.
  set /p "MODEL=사용할 모델 이름: "
  if not defined MODEL ( echo [ERROR] 모델이 필요합니다. & pause & exit /b 1 )
  echo.
  echo  서버가 Responses API 를 지원하는지 확인합니다...
  for /f %%c in ('curl -s -o nul -w "%%{http_code}" -X POST -H "Authorization: Bearer !KEY!" -H "Content-Type: application/json" -d "{\"model\":\"!MODEL!\",\"input\":\"hi\"}" "!EP!/responses"') do set "RC=%%c"
  if "!RC!"=="200" ( set "GW=0" & echo   -^> 직결 가능 ^(Responses API 지원^) ) else ( set "GW=1" & echo   -^> 게이트웨이 사용 ^(Chat 전용 서버, HTTP !RC!^) )
  ^> "%CFG%\conf.bat" echo set "EP=!EP!"
  ^>^> "%CFG%\conf.bat" echo set "KEY=!KEY!"
  ^>^> "%CFG%\conf.bat" echo set "MODEL=!MODEL!"
  ^>^> "%CFG%\conf.bat" echo set "GW=!GW!"
  echo.
  echo  설정이 저장되었습니다: %CFG%\conf.bat
  echo  ^(다시 설정하려면 이 파일을 지우고 실행하세요^)
  echo.
)
call "%CFG%\conf.bat"

REM ---------- 3) codex 설정 파일 생성 ----------
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

REM ---------- 4) 필요하면 게이트웨이 기동 ----------
set "GWPID="
if "%GW%"=="1" (
  echo [gateway] 시작 중...
  set "GW_UPSTREAM=%EP%"
  for /f %%p in ('powershell -NoProfile -Command "(Start-Process -FilePath '%NODEDIR%\node.exe' -ArgumentList '\"%LIB%\gateway.js\"' -PassThru -WindowStyle Hidden).Id"') do set "GWPID=%%p"
  timeout /t 2 /nobreak >nul
)

REM ---------- 5) codex 실행 ----------
call codex %*

if defined GWPID taskkill /f /pid %GWPID% >nul 2>&1
endlocal
