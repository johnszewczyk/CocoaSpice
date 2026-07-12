#!/bin/bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <scan-root>" >&2
  exit 64
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
export COCOASPICE_SCAN_ROOT="$1"
export COCOASPICE_SCAN_PERSIST="${COCOASPICE_SCAN_PERSIST:-0}"
cd "$ROOT_DIR"
swift test --filter scanPipelineCommandLineProbe
