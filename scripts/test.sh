#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
echo "Testing SwiftAgent..."
swift test
echo "All tests passed."
