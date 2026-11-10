#!/usr/bin/env bash
# The staged Horizon ladder at the campaign pin (stage -> check -> test -> build).
# Path-relative, so the same command runs on the campaign tree or the remote box:
#   ports/tools/build-slot.sh run --job ma-ladder --port ports/mysticalagriculture \
#       --step build -- bash ports/mysticalagriculture/tools/embed_ladder.sh
#   ports/tools/remote-slot.sh run --job ma-ladder --port ports/mysticalagriculture \
#       --step build -- bash ports/mysticalagriculture/tools/embed_ladder.sh
set -euo pipefail
PORT=$(cd "$(dirname "$0")/.." && pwd)
CAMPAIGN=$(cd "$PORT/../.." && pwd)
PIN=${HORIZON:-$CAMPAIGN/ports/_shared/pins/horizon-1d63e0a}
LOG=$CAMPAIGN/ports/_shared/evidence/mysticalagriculture
cd "$PORT"
mkdir -p target/logs "$LOG"

{
    for step in stage check test build; do
        echo "== horizon.py $step =="
        python3 tools/horizon.py "$step" --horizon "$PIN"
        echo "${step}_exit:$?"
    done
} 2>&1 | tee "$LOG/embed-ladder.log"
