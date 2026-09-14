#!/usr/bin/env bash
# Builds pulpmesh natively on a Linux amd64 host.
#
# This is the counterpart to build-linux.sh: same output, no VM. spinel hands
# its generated C to the system `cc`, so running the build here is enough —
# the binary already matches the host. If `spin` is not on PATH, spinel is
# built from source first (SPINEL_SRC, default ../spinel) and its bin/ is
# prepended to PATH for this script only.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SPINEL_SRC="${SPINEL_SRC:-$ROOT/../spinel}"
OUT_DIR="$ROOT/build/linux"

[ "$(uname -s)" = "Linux" ] || {
  echo "this script builds on Linux; use tools/build-linux.sh to cross-build from macOS" >&2
  exit 1
}
case "$(uname -m)" in
  x86_64 | amd64) ;;
  *)
    echo "this script targets amd64; host is $(uname -m)" >&2
    exit 1
    ;;
esac
command -v cc >/dev/null || {
  echo "no C compiler on PATH (apt-get install build-essential)" >&2
  exit 1
}

if ! command -v spin >/dev/null; then
  if [ ! -d "$SPINEL_SRC" ]; then
    echo "spin not on PATH and no spinel source at $SPINEL_SRC (set SPINEL_SRC=/path/to/spinel)" >&2
    exit 1
  fi
  make -C "$SPINEL_SRC" deps
  make -C "$SPINEL_SRC" -j"$(nproc)"
  PATH="$SPINEL_SRC/bin:$PATH"
  export PATH
fi

cd "$ROOT"
spin build

mkdir -p "$OUT_DIR"
cp build/bin/pulpmesh "$OUT_DIR/pulpmesh-linux-$(uname -m)"

echo "Linux binary: $OUT_DIR/pulpmesh-linux-$(uname -m)"
