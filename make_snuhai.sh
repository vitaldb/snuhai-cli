#!/usr/bin/env bash
# ============================================================================
#  make_snuhai.sh — build the distributable bundle (snuhai-cli).
#
#  Run this ONCE on a machine with internet access.
#    Then copy the resulting snuhai-cli.zip to the air-gapped machine and
#    run snuhai.bat (Windows) / snuhai.sh (Linux) inside it.
#
#    ./make_snuhai.sh [win|linux|both]      default: both
# ============================================================================
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$HERE/src"
TARGET="${1:-both}"
OUT="$HERE/snuhai-cli"
LIB="$OUT/.snuhai"

CODEX_VER="${CODEX_VER:-0.145.0}"
NODE_VER="${NODE_VER:-24.18.0}"

command -v npm  >/dev/null || { echo "[ERROR] npm is required (run this on a machine with internet)"; exit 1; }
command -v curl >/dev/null || { echo "[ERROR] curl is required"; exit 1; }

echo "============================================================"
echo "  Building snuhai bundle  (codex ${CODEX_VER} / node ${NODE_VER} / target=${TARGET})"
echo "============================================================"
rm -rf "$OUT"
mkdir -p "$LIB/packages" "$LIB/node"

# ---------- 1. Codex CLI (verbatim npm tarballs) ----------
echo
echo "[1/4] Downloading Codex CLI..."
cd "$LIB/packages"
specs=("@openai/codex@${CODEX_VER}")
[ "$TARGET" = "win"   ] || [ "$TARGET" = "both" ] && specs+=("@openai/codex@${CODEX_VER}-win32-x64")
[ "$TARGET" = "linux" ] || [ "$TARGET" = "both" ] && specs+=("@openai/codex@${CODEX_VER}-linux-x64")
npm pack "${specs[@]}" >/dev/null

echo "[1/4] Verifying integrity against the npm registry hashes..."
{ echo "# Verbatim npm artifacts — fetched $(date -u +%Y-%m-%dT%H:%MZ)"
  echo "# local sha512 MUST equal the registry integrity"; } > PROVENANCE.txt
fail=0
for spec in "${specs[@]}"; do
  reg=$(npm view "$spec" dist.integrity)
  # npm pack stores scoped packages with '@' removed and '/' replaced by '-'.
  #   @openai/codex@0.145.0-linux-x64  ->  openai-codex-0.145.0-linux-x64.tgz
  pkg="${spec%@*}"; ver="${spec##*@}"
  fname="$(printf '%s' "$pkg" | sed 's/^@//; s#/#-#g')-${ver}.tgz"
  [ -f "$fname" ] || { echo "[ERROR] File not found: $fname"; exit 1; }
  loc="sha512-$(openssl dgst -sha512 -binary "$fname" | base64 -w0)"
  if [ "$reg" = "$loc" ]; then st="OK  "; else st="FAIL"; fail=1; fi
  echo "       $st $spec"
  printf '%s\n  registry: %s\n  local:    %s\n  file:     %s\n' \
         "$spec" "$reg" "$loc" "$fname" >> PROVENANCE.txt
done
sha256sum ./*.tgz > SHA256SUMS
[ "$fail" = 0 ] || { echo "[ERROR] Integrity mismatch — aborting"; exit 1; }

# ---------- 2. Portable Node ----------
echo
echo "[2/4] Downloading portable Node.js..."
cd "$LIB/node"
base="https://nodejs.org/dist/v${NODE_VER}"
curl -fsSL "${base}/SHASUMS256.txt" -o SHASUMS256.txt
get() {
  curl -fsSLO "${base}/$1"
  grep " $1\$" SHASUMS256.txt | sha256sum -c - >/dev/null
  echo "       OK   $1"
}
if [ "$TARGET" = "linux" ] || [ "$TARGET" = "both" ]; then
  get "node-v${NODE_VER}-linux-x64.tar.xz"; tar xf "node-v${NODE_VER}-linux-x64.tar.xz"
  rm -f "node-v${NODE_VER}-linux-x64.tar.xz"
fi
if [ "$TARGET" = "win" ] || [ "$TARGET" = "both" ]; then
  get "node-v${NODE_VER}-win-x64.zip"
  if command -v unzip >/dev/null; then unzip -q "node-v${NODE_VER}-win-x64.zip"
  else python3 -c "import zipfile;zipfile.ZipFile('node-v${NODE_VER}-win-x64.zip').extractall('.')"; fi
  rm -f "node-v${NODE_VER}-win-x64.zip"
fi
rm -f SHASUMS256.txt

# ---------- 3. Lay out the bundle ----------
echo
echo "[3/4] Laying out the bundle..."
cp "$SRC/gateway.js" "$LIB/gateway.js"
cp "$HERE/NOTICE" "$LIB/NOTICE" 2>/dev/null || true
cp "$HERE/LICENSE" "$LIB/LICENSE" 2>/dev/null || true
# only the launcher is visible at the top level
cp "$SRC/snuhai.bat" "$OUT/snuhai.bat"
cp "$SRC/snuhai.sh"  "$OUT/snuhai.sh"
chmod +x "$OUT/snuhai.sh"
cat > "$OUT/README.txt" <<'EOF'
snuhai - run Codex CLI against an internal LLM server

  Windows : double-click  snuhai.bat
  Linux   : run  ./snuhai.sh

On first run it asks once for the server URL, your API key and a model.
After that it starts straight away. No internet required.

(.snuhai holds everything it needs to run - do not delete it.)
EOF

# ---------- 4. Pack into a ZIP ----------
echo
echo "[4/4] Creating the ZIP..."
cd "$HERE"
python3 - "$OUT" <<'PY'
import os, sys, zipfile
src = sys.argv[1]; base = os.path.dirname(src)
out = src + ".zip"
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as z:
    for root, dirs, files in os.walk(src):
        for n in sorted(files):
            fp = os.path.join(root, n)
            arc = os.path.relpath(fp, base)
            if os.path.islink(fp):
                # store symlinks as symlinks.
                # (dereferencing them breaks shims such as node/bin/npm)
                zi = zipfile.ZipInfo(arc)
                zi.create_system = 3                      # Unix
                zi.external_attr = (0o120777 << 16)       # S_IFLNK | 0777
                z.writestr(zi, os.readlink(fp))
                continue
            # ZipInfo.from_file carries st_mode into external_attr -> exec bits preserved
            zi = zipfile.ZipInfo.from_file(fp, arc)
            zi.compress_type = zipfile.ZIP_DEFLATED
            with open(fp, "rb") as fh:
                z.writestr(zi, fh.read())
print(f"  {out}  ({os.path.getsize(out)/1048576:.0f} MB)")
PY
sha256sum "$(basename "$OUT").zip" > "$(basename "$OUT").zip.sha256"
if [ "${KEEP_DIR:-0}" != "1" ]; then rm -rf "$OUT"; fi

echo
echo "============================================================"
echo " Done"
echo "============================================================"
ls -lh "$OUT.zip" | awk '{print "  file:", $NF, "("$5")"}'
echo "  sha256: $(cut -c1-16 < "$OUT.zip.sha256")…  (full value in $(basename "$OUT").zip.sha256)"
echo
echo "  Copy this single ZIP to the air-gapped machine:"
echo "    1) unzip it"
echo "    2) Windows: double-click snuhai.bat   Linux: ./snuhai.sh"
echo
echo "  (keep the unzipped folder too:  KEEP_DIR=1 ./make_snuhai.sh)"
