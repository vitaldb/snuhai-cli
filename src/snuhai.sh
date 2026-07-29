#!/usr/bin/env bash
# ============================================================
#  snuhai — 사내 LLM 서버로 Codex CLI 실행 (폐쇄망용)
#  이 파일 하나만 실행하면 된다. 최초 실행 시 설치·설정을 자동으로 한다.
# ============================================================
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$HERE/.snuhai"
CFG="$HOME/.snuhai"
export CODEX_HOME="$CFG/codex"
export DISABLE_AUTOUPDATER=1

[ -d "$LIB" ] || { echo "[ERROR] .snuhai 폴더가 없습니다. 번들이 손상되었습니다."; exit 1; }
NODEDIR="$(ls -d "$LIB"/node/node-v*-linux-x64 2>/dev/null | head -1)"
[ -n "$NODEDIR" ] || { echo "[ERROR] 번들에 Node 가 없습니다."; exit 1; }
export PATH="$NODEDIR/bin:$PATH"
mkdir -p "$CFG" "$CODEX_HOME"

# ---------- 1) 최초 1회: codex 오프라인 설치 ----------
if [ ! -f "$LIB/installed.flag" ]; then
  echo "[설치] Codex CLI 를 설치합니다 (최초 1회, 인터넷 불필요)..."
  MAIN="$(ls "$LIB"/packages/openai-codex-*.tgz 2>/dev/null | grep -v -- '-linux-x64\|-win32-x64' | head -1)"
  [ -n "$MAIN" ] || { echo "[ERROR] packages 에 codex tarball 이 없습니다."; exit 1; }
  npm install -g --offline --no-audit --no-fund "$MAIN" >/dev/null 2>&1 \
    || { echo "[ERROR] 설치 실패"; exit 1; }
  NATIVE="$(ls "$LIB"/packages/openai-codex-*-linux-x64.tgz 2>/dev/null | head -1)"
  if [ -n "$NATIVE" ]; then
    CODEX_DIR="$(npm root -g)/@openai/codex"; TMP="$(mktemp -d)"
    tar -xf "$NATIVE" -C "$TMP" package/vendor
    mkdir -p "$CODEX_DIR/vendor"; cp -a "$TMP/package/vendor/." "$CODEX_DIR/vendor/"; rm -rf "$TMP"
    chmod +x "$CODEX_DIR"/vendor/*/bin/codex 2>/dev/null || true
  fi
  echo ok > "$LIB/installed.flag"
  echo "[설치] 완료"
fi

# ---------- 2) 최초 1회: 서버·키·모델 설정 ----------
if [ ! -f "$CFG/conf.sh" ]; then
  echo
  echo "============================================================"
  echo "  snuhai 최초 설정"
  echo "============================================================"
  echo
  echo " 사내 LLM 서버 주소를 입력하세요. 예) https://llm.example.org/v1"
  read -r -p "서버 주소: " EP
  [ -n "${EP:-}" ] || { echo "[ERROR] 주소가 필요합니다."; exit 1; }
  echo
  read -r -p "API 키: " KEY
  [ -n "${KEY:-}" ] || { echo "[ERROR] 키가 필요합니다."; exit 1; }
  echo
  echo " 사용 가능한 모델을 조회합니다..."
  curl -s -H "Authorization: Bearer $KEY" "$EP/models" \
    | grep -o '"id"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)"$/  \1/' \
    | grep -viE 'asr|embed|tts|speech|whisper' || echo "  (목록을 가져오지 못했습니다)"
  echo
  read -r -p "사용할 모델 이름: " MODEL
  [ -n "${MODEL:-}" ] || { echo "[ERROR] 모델이 필요합니다."; exit 1; }
  echo
  echo " 서버가 Responses API 를 지원하는지 확인합니다..."
  RC="$(curl -s -o /dev/null -w '%{http_code}' -X POST \
        -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' \
        -d "{\"model\":\"$MODEL\",\"input\":\"hi\"}" "$EP/responses" 2>/dev/null)"
  if [ "$RC" = "200" ]; then GW=0; echo "  -> 직결 가능 (Responses API 지원)"
  else GW=1; echo "  -> 게이트웨이 사용 (Chat 전용 서버, HTTP $RC)"; fi
  umask 077
  { echo "EP=$EP"; echo "KEY=$KEY"; echo "MODEL=$MODEL"; echo "GW=$GW"; } > "$CFG/conf.sh"
  echo
  echo " 설정이 저장되었습니다: $CFG/conf.sh"
  echo " (다시 설정하려면 이 파일을 지우고 실행하세요)"
  echo
fi
# shellcheck disable=SC1090
. "$CFG/conf.sh"

# ---------- 3) codex 설정 파일 생성 ----------
if [ "$GW" = "1" ]; then BASE="http://127.0.0.1:4600/v1"; else BASE="$EP"; fi
cat > "$CODEX_HOME/config.toml" <<TOML
model = "$MODEL"
model_provider = "snuhai"

[model_providers.snuhai]
name = "snuhai"
base_url = "$BASE"
wire_api = "responses"
env_key = "SNUHAI_API_KEY"

[model_properties."$MODEL"]
context_window = 131072
supports_reasoning_summaries = false
input_modalities = ["text"]
TOML
export SNUHAI_API_KEY="$KEY"

# ---------- 4) 필요하면 게이트웨이 기동 ----------
if [ "$GW" = "1" ]; then
  echo "[gateway] 시작 중..."
  GW_UPSTREAM="$EP" node "$LIB/gateway.js" >"$CFG/gateway.log" 2>&1 &
  GWPID=$!
  trap 'kill $GWPID 2>/dev/null' EXIT
  sleep 2
fi

# ---------- 5) codex 실행 ----------
codex "$@"
