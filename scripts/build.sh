#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
echo "Building SwiftAgent..."
swift build
echo "Build successful."
