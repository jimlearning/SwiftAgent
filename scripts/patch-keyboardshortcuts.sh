#!/bin/bash
# KeyboardShortcuts 2.4.0 has #Preview macros in Recorder.swift that require the
# PreviewsMacros plugin, which isn't available via SPM `swift build`.
# This strips them so the package builds outside Xcode.
set -euo pipefail

FILE=".build/checkouts/KeyboardShortcuts/Sources/KeyboardShortcuts/Recorder.swift"

if [ ! -f "$FILE" ]; then
    echo "No KeyboardShortcuts checkout found, skipping patch."
    exit 0
fi

if grep -q '#Preview' "$FILE"; then
    echo "Patching KeyboardShortcuts Recorder.swift to remove #Preview blocks..."
    sed -i '' '/^#Preview {/,/^}/d' "$FILE"
    echo "Done."
else
    echo "KeyboardShortcuts already patched, skipping."
fi
