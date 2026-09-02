#!/usr/bin/env bash
# Cross-builds pulpmesh into a Linux binary from macOS.
#
# spinel generates C and hands it to the system `cc`, so the binary it
# produces always matches the machine spinel itself runs on. To get a Linux
# binary from macOS, this builds spinel and pulpmesh natively inside a
# throwaway Linux VM (via smolvm: https://smolvm.dev) and copies the result
# back out. The VM persists between runs so only the first build pays for
# `apt-get` and a full spinel build; later runs just re-sync sources and
# rebuild incrementally.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SPINEL_SRC="${SPINEL_SRC:-$ROOT/../spinel}"
VM_NAME="${VM_NAME:-pulpmesh-linux}"
OUT_DIR="$ROOT/build/linux"

if [ ! -d "$SPINEL_SRC" ]; then
  echo "spinel source not found at $SPINEL_SRC (set SPINEL_SRC=/path/to/spinel)" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

if ! smolvm machine status --name "$VM_NAME" >/dev/null 2>&1; then
  smolvm machine create --name "$VM_NAME" --image debian:bookworm-slim --net \
    -v "$SPINEL_SRC:/host/spinel:ro" \
    -v "$ROOT:/host/pulpmesh:ro" \
    -v "$OUT_DIR:/output" \
    --cpus 4 --mem 4096
fi

smolvm machine start --name "$VM_NAME"

smolvm machine exec --name "$VM_NAME" -- sh -c '
  set -e
  command -v cc >/dev/null || (apt-get update -qq && apt-get install -y -qq build-essential curl ca-certificates rsync)
  rsync -a --exclude="/build/" --exclude="/bin/" --exclude="/spinel" /host/spinel/ /root/spinel/
  rsync -a --exclude="/build/" /host/pulpmesh/ /root/pulpmesh/
  cd /root/spinel && make deps && make -j"$(nproc)"
  export PATH=/root/spinel/bin:$PATH
  cd /root/pulpmesh && spin build
  cp build/bin/pulpmesh "/output/pulpmesh-linux-$(uname -m)"
'

echo "Linux binary: $OUT_DIR/pulpmesh-linux-$(smolvm machine exec --name "$VM_NAME" -- uname -m)"
