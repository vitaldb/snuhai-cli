#!/usr/bin/env bash
# ============================================================
#  snuhai — run Codex CLI against an internal LLM server (air-gapped)
#  Run this one file. It installs and configures itself on first use.
# ============================================================
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$HERE/.snuhai"
# Some unzip tools drop the executable bit (Windows Explorer, python zipfile...).
# The ZIP stores 0755, but it is not always restored — repair it here.
chmod +x "$0" 2>/dev/null || true
for _f in "$LIB"/node/node-v*/bin/* ; do [ -f "$_f" ] && chmod +x "$_f" 2>/dev/null || true; done
CFG="$HOME/.snuhai"
export CODEX_HOME="$CFG/codex"
export DISABLE_AUTOUPDATER=1

[ -d "$LIB" ] || { echo "[ERROR] .snuhai folder is missing. Copy the whole folder."; exit 1; }
NODEDIR="$(ls -d "$LIB"/node/node-v*-linux-x64 2>/dev/null | head -1)"
[ -n "$NODEDIR" ] || { echo "[ERROR] No bundled Node found."; exit 1; }
export PATH="$NODEDIR/bin:$PATH"
mkdir -p "$CFG" "$CODEX_HOME"

# ---------- 1) first run only: install Codex offline ----------
if [ ! -f "$LIB/installed.flag" ]; then
  echo "[setup] Installing Codex CLI (first run only, no internet needed)..."
  MAIN="$(ls "$LIB"/packages/openai-codex-*.tgz 2>/dev/null | grep -v -- '-linux-x64\|-win32-x64' | head -1)"
  [ -n "$MAIN" ] || { echo "[ERROR] No codex tarball in packages/."; exit 1; }
  # bin/npm is a symlink and may break depending on how the ZIP was extracted,
  # so call npm-cli.js with node directly.
  NPMCLI="$NODEDIR/lib/node_modules/npm/bin/npm-cli.js"
  [ -f "$NPMCLI" ] || NPMCLI="$(command -v npm)"
  if ! node "$NPMCLI" install -g --offline --no-audit --no-fund "$MAIN" >"$CFG/install.log" 2>&1; then
    echo "[ERROR] Install failed — see $CFG/install.log"; tail -5 "$CFG/install.log"; exit 1
  fi
  NATIVE="$(ls "$LIB"/packages/openai-codex-*-linux-x64.tgz 2>/dev/null | head -1)"
  if [ -n "$NATIVE" ]; then
    CODEX_DIR="$(node "$NPMCLI" root -g)/@openai/codex"; TMP="$(mktemp -d)"
    tar -xf "$NATIVE" -C "$TMP" package/vendor
    mkdir -p "$CODEX_DIR/vendor"; cp -a "$TMP/package/vendor/." "$CODEX_DIR/vendor/"; rm -rf "$TMP"
    chmod -R +x "$CODEX_DIR"/vendor/*/bin "$CODEX_DIR"/vendor/*/codex-path 2>/dev/null || true
  fi
  echo ok > "$LIB/installed.flag"
  echo "[setup] Done."
fi

# ---------- 2) first run only: server, key, model ----------
if [ ! -f "$CFG/conf.sh" ]; then
  echo
  echo "============================================================"
  echo "  snuhai first-time setup"
  echo "============================================================"
  echo
  echo " [1] Internal LLM server URL"
  echo "     Press Enter to use the Seoul National University Hospital default."
  echo "     default: https://llm.snuh.org/llm"
  read -r -p "Server URL (Enter = default): " EP
  EP="${EP:-https://llm.snuh.org/llm}"
  echo
  echo " [2] How to get an API key (from the intranet)"
  echo "     1. Open  https://ai.snuh.org  in your browser"
  echo "     2. Sign in with your SNUHUB account"
  echo "     3. Left menu:  MY > My Key Management  [나의 키 관리]"
  echo "        (direct link: ai.snuh.org/setting/my-key)"
  echo "     4. Click  + Add  [추가]  at the top right"
  echo "     5. Type = LLM, description e.g. snuhai-cli, then issue it"
  echo "     6. Copy the key value (starts with sk-) and paste it below"
  echo
  read -r -p "API key: " KEY
  [ -n "${KEY:-}" ] || { echo "[ERROR] A key is required."; exit 1; }
  echo
  echo " Fetching available models..."
  curl -s -H "Authorization: Bearer $KEY" "$EP/models" \
    | grep -o '"id"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)"$/  \1/' \
    | grep -viE 'asr|embed|tts|speech|whisper' || echo "  (could not fetch the list)"
  echo
  read -r -p "Model name: " MODEL
  [ -n "${MODEL:-}" ] || { echo "[ERROR] A model is required."; exit 1; }
  echo
  echo " Checking whether the server supports the Responses API..."
  RC="$(curl -s -o /dev/null -w '%{http_code}' -X POST \
        -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' \
        -d "{\"model\":\"$MODEL\",\"input\":\"hi\"}" "$EP/responses" 2>/dev/null)"
  if [ "$RC" = "200" ]; then GW=0; echo "  -> direct connection (Responses API supported)"
  else GW=1; echo "  -> using the gateway (chat-only server, HTTP $RC)"; fi
  umask 077
  { echo "EP=$EP"; echo "KEY=$KEY"; echo "MODEL=$MODEL"; echo "GW=$GW"; } > "$CFG/conf.sh"
  echo
  echo " Saved to $CFG/conf.sh"
  echo " (delete that file and run again to reconfigure)"
  echo
fi
# shellcheck disable=SC1090
. "$CFG/conf.sh"

# ---------- 3) write the codex config ----------
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

# ---------- 4) start the gateway if needed ----------
if [ "$GW" = "1" ]; then
  echo "[gateway] starting..."
  GW_UPSTREAM="$EP" node "$LIB/gateway.js" >"$CFG/gateway.log" 2>&1 &
  GWPID=$!
  trap 'kill $GWPID 2>/dev/null' EXIT
  sleep 2
fi

# ---------- 5) run codex ----------
codex "$@"
