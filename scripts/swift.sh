#!/usr/bin/env bash
# Runs a SwiftPM command with build output kept outside the checkout (see
# scripts/env.sh). Example: scripts/swift.sh run papernest-samples Samples
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/env.sh
command="$1"
shift
exec swift "$command" --scratch-path "$SCRATCH" "$@"
