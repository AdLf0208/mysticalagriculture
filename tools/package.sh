#!/usr/bin/env bash
# Package both artifacts of the slice:
#  - the content `.hmod` via the pin's own cargo-horizon-mod (build + check), delivered in content/
#  - the built content inside the bundle (mixins/<id>/data/<id>-content.hmod, the AE2 pattern)
#  - the source-only `.hnmod` (tools/package.py, deterministic bytes, in the port root)
# Run inside a build slot (it compiles the packaging tool):
#   ports/tools/build-slot.sh run --job ma-pack --port ports/mysticalagriculture \
#       --step build -- env CARGO_INCREMENTAL=0 tools/package.sh
set -euo pipefail

PORT=$(cd "$(dirname "$0")/.." && pwd)
HORIZON=${HORIZON:-${CAMPAIGN_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}/ports/_shared/pins/horizon-1d63e0a}
MOD=mysticalagriculture
VERSION=0.1.0
LOGS=$PORT/target/ladder
mkdir -p "$LOGS"
cd "$PORT"

CARGO_TARGET_DIR=$PORT/target/carry-tools
export CARGO_TARGET_DIR
(cd content && cargo run --locked --offline --quiet \
    --manifest-path "$HORIZON/crates/cargo-horizon-mod/Cargo.toml" -- horizon-mod build) \
    2>&1 | tee "$LOGS/package-hmod.log"
cp "content/target/horizon-mod/$MOD.hmod" "content/$MOD.hmod"
(cd content && cargo run --locked --offline --quiet \
    --manifest-path "$HORIZON/crates/cargo-horizon-mod/Cargo.toml" -- horizon-mod check "$MOD.hmod") \
    2>&1 | tee -a "$LOGS/package-hmod.log"

# One file installs both halves: the built content travels in the bundle's data/.
mkdir -p "mixins/$MOD/data"
cp "content/$MOD.hmod" "mixins/$MOD/data/$MOD-content.hmod"

python3 tools/package.py | tee "$LOGS/package-hnmod.log"
cp "target/$MOD-$VERSION.hnmod" "$MOD.hnmod"
(cd content && cargo run --locked --offline --quiet \
    --manifest-path "$HORIZON/crates/cargo-horizon-mod/Cargo.toml" -- \
    horizon-mod check "$PORT/$MOD.hnmod" --kind native-mod) \
    2>&1 | tee -a "$LOGS/package-hnmod.log"

echo "== artifacts =="
for f in "content/$MOD.hmod" "$MOD.hnmod"; do
    [ -f "$f" ] || { echo "missing $f"; exit 1; }
    size=$(stat -c %s "$f")
    sha=$(sha256sum "$f" | cut -d' ' -f1)
    entries=$(python3 -c "import zipfile,sys; print(len(zipfile.ZipFile(sys.argv[1]).namelist()))" "$f")
    echo "$f size=$size sha256=$sha entries=$entries"
done
python3 - "$MOD.hnmod" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as archive:
    for name in archive.namelist():
        print(f"  {name} ({archive.getinfo(name).file_size} B)")
PY
