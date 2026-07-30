#!/usr/bin/env bash
# ============================================================================
#  make_snuhai.sh — 배포 폴더(snuhai-cli)를 만든다.
#
#  ★ 인터넷이 되는 PC에서 한 번만 실행한다.
#    만들어진 snuhai-cli 폴더를 통째로 폐쇄망 PC로 옮기고,
#    그 안의 snuhai.bat (Windows) / snuhai.sh (Linux) 를 실행하면 끝이다.
#
#    ./make_snuhai.sh [win|linux|both]      기본값: both
# ============================================================================
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$HERE/src"
TARGET="${1:-both}"
OUT="$HERE/snuhai-cli"
LIB="$OUT/.snuhai"

CODEX_VER="${CODEX_VER:-0.145.0}"
NODE_VER="${NODE_VER:-24.18.0}"

command -v npm  >/dev/null || { echo "[ERROR] npm 이 필요합니다 (인터넷 되는 PC에서 실행하세요)"; exit 1; }
command -v curl >/dev/null || { echo "[ERROR] curl 이 필요합니다"; exit 1; }

echo "============================================================"
echo "  snuhai 번들 생성  (codex ${CODEX_VER} / node ${NODE_VER} / target=${TARGET})"
echo "============================================================"
rm -rf "$OUT"
mkdir -p "$LIB/packages" "$LIB/node"

# ---------- 1. Codex CLI (npm 원본 tarball) ----------
echo
echo "[1/4] Codex CLI 내려받기..."
cd "$LIB/packages"
specs=("@openai/codex@${CODEX_VER}")
[ "$TARGET" = "win"   ] || [ "$TARGET" = "both" ] && specs+=("@openai/codex@${CODEX_VER}-win32-x64")
[ "$TARGET" = "linux" ] || [ "$TARGET" = "both" ] && specs+=("@openai/codex@${CODEX_VER}-linux-x64")
npm pack "${specs[@]}" >/dev/null

echo "[1/4] 무결성 검증 (npm 레지스트리 해시와 대조)..."
{ echo "# Verbatim npm artifacts — fetched $(date -u +%Y-%m-%dT%H:%MZ)"
  echo "# local sha512 MUST equal the registry integrity"; } > PROVENANCE.txt
fail=0
for spec in "${specs[@]}"; do
  reg=$(npm view "$spec" dist.integrity)
  # npm pack 은 스코프 패키지를 '@' 제거 + '/'→'-' 로 바꿔 저장한다.
  #   @openai/codex@0.145.0-linux-x64  ->  openai-codex-0.145.0-linux-x64.tgz
  pkg="${spec%@*}"; ver="${spec##*@}"
  fname="$(printf '%s' "$pkg" | sed 's/^@//; s#/#-#g')-${ver}.tgz"
  [ -f "$fname" ] || { echo "[ERROR] 파일을 찾을 수 없습니다: $fname"; exit 1; }
  loc="sha512-$(openssl dgst -sha512 -binary "$fname" | base64 -w0)"
  if [ "$reg" = "$loc" ]; then st="OK  "; else st="FAIL"; fail=1; fi
  echo "       $st $spec"
  printf '%s\n  registry: %s\n  local:    %s\n  file:     %s\n' \
         "$spec" "$reg" "$loc" "$fname" >> PROVENANCE.txt
done
sha256sum ./*.tgz > SHA256SUMS
[ "$fail" = 0 ] || { echo "[ERROR] 무결성 불일치 — 중단합니다"; exit 1; }

# ---------- 2. 포터블 Node ----------
echo
echo "[2/4] 포터블 Node.js 내려받기..."
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

# ---------- 3. 실행 파일 배치 ----------
echo
echo "[3/4] 실행 파일 배치..."
cp "$SRC/gateway.js" "$LIB/gateway.js"
cp "$HERE/NOTICE" "$LIB/NOTICE" 2>/dev/null || true
cp "$HERE/LICENSE" "$LIB/LICENSE" 2>/dev/null || true
# 루트에는 실행 파일만 노출한다
cp "$SRC/snuhai.bat" "$OUT/snuhai.bat"
cp "$SRC/snuhai.sh"  "$OUT/snuhai.sh"
chmod +x "$OUT/snuhai.sh"
cat > "$OUT/읽어보세요.txt" <<'EOF'
snuhai — 사내 LLM 서버로 Codex CLI 쓰기

  Windows : snuhai.bat 을 더블클릭하세요.
  Linux   : ./snuhai.sh 를 실행하세요.

처음 실행하면 서버 주소·API 키·모델을 한 번만 물어봅니다.
그 다음부터는 바로 실행됩니다. 인터넷은 필요하지 않습니다.

(.snuhai 폴더에는 실행에 필요한 파일이 들어 있습니다. 지우지 마세요.)
EOF

# ---------- 4. ZIP 으로 묶기 ----------
echo
echo "[4/4] ZIP 만드는 중..."
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
                # 심볼릭 링크를 링크 그대로 저장한다.
                # (따라가서 내용을 복사하면 node/bin/npm 같은 shim 의 require 경로가 깨진다)
                zi = zipfile.ZipInfo(arc)
                zi.create_system = 3                      # Unix
                zi.external_attr = (0o120777 << 16)       # S_IFLNK | 0777
                z.writestr(zi, os.readlink(fp))
                continue
            # ZipInfo.from_file 이 st_mode 를 external_attr 로 넣어준다 -> 실행권한 보존
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
echo " 완료"
echo "============================================================"
ls -lh "$OUT.zip" | awk '{print "  파일:", $NF, "("$5")"}'
echo "  해시: $(cut -c1-16 < "$OUT.zip.sha256")…  (전체는 $(basename "$OUT").zip.sha256)"
echo
echo "  이 ZIP 하나만 폐쇄망 PC 로 옮기면 됩니다."
echo "    1) 압축을 풉니다"
echo "    2) Windows 는 snuhai.bat 더블클릭 / Linux 는 ./snuhai.sh 실행"
echo
echo "  (폴더도 남기려면  KEEP_DIR=1 ./make_snuhai.sh)"
