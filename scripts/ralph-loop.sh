#!/usr/bin/env bash
# Ralph Wiggum Loop — Autonomous spec-driven development
# Based on Geoffrey Huntley's iterative bash loop pattern
#
# Usage:
#   ./scripts/ralph-loop.sh          # Build mode: pick spec, implement
#   ./scripts/ralph-loop.sh 20       # With max 20 iterations
#   ./scripts/ralph-loop.sh plan     # Plan mode: create detailed task breakdown

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SPECS_DIR="$PROJECT_DIR/specs"
LOGS_DIR="$PROJECT_DIR/logs"
HISTORY_FILE="$PROJECT_DIR/ralph_history.txt"
PRODUCT_DOC="$PROJECT_DIR/.mavis/plans/swiftagent-macos-product-doc.md"
MAX_ITERATIONS="${1:-10}"
MODE="${2:-build}"
SESSION_ID="ralph_$(date +%Y%m%d_%H%M%S)"

# Ensure directories exist
mkdir -p "$LOGS_DIR" "$SPECS_DIR"

# Initialize history file if needed
if [[ ! -f "$HISTORY_FILE" ]]; then
    cat > "$HISTORY_FILE" <<'HISTORY'
# Ralph Wiggum History
## Project: SwiftAgent
## Started: $(date)
---
HISTORY
fi

SESSION_LOG="$LOGS_DIR/${SESSION_ID}_session.log"

log() {
    echo "[$(date '+%H:%M:%S')] $*" | tee -a "$SESSION_LOG"
}

get_pending_specs() {
    # Find spec files not marked DONE in history
    local specs=()
    for spec in "$SPECS_DIR"/*.md; do
        local spec_name
        spec_name="$(basename "$spec")"
        if ! grep -q "DONE.*$spec_name" "$HISTORY_FILE" 2>/dev/null; then
            specs+=("$spec")
        fi
    done
    # Sort by phase number
    printf '%s\n' "${specs[@]}" | sort -V
}

run_iteration() {
    local spec_file="$1"
    local spec_name="$2"
    local iter="$3"
    local iter_log="$LOGS_DIR/${SESSION_ID}_iter_${iter}_$(basename "$spec_file" .md).log"

    log "=== Iteration $iter: $spec_name ==="
    log "Spec: $spec_file"

    # Read the spec content
    local spec_content
    spec_content="$(cat "$spec_file")"

    # Read the full product doc reference (contains detailed specs for all sections)
    local product_doc_content=""
    if [[ -f "$PRODUCT_DOC" ]]; then
        product_doc_content="

---

# Full Product Specification (reference)

The spec above is a phase-level checklist. The COMPLETE product specification with detailed SwiftUI code, color tokens, ASCII layout diagrams, anti-patterns list (25 items), and screenshots index lives here:

$PRODUCT_DOC

Read it before implementing — especially the sections cited in the spec (e.g. §3.3 for right panel, §4 for design tokens, §11 for DeepSeek). When in doubt, the product doc is authoritative.
"
    fi

    # Build the prompt for Claude Code
    local prompt
    prompt=$(cat <<PROMPT
You are implementing the following specification for the SwiftAgent project.

IMPORTANT: Work in /Users/jim/SwiftAgent/

${spec_content}
${product_doc_content}

---

Your task:
1. Read the current project state (Sources/, Package.swift, CLAUDE.md) to understand what exists
2. Read the product doc sections cited in the spec (e.g. §3.3, §4.1, §5.4, §11.3) for full details
3. Implement ALL acceptance criteria in the specification
4. Build and test: run \`swift build --disable-sandbox\` and \`swift test --disable-sandbox --no-parallel\`
5. Fix any issues until all tests pass with zero warnings
6. When ALL criteria are met, output EXACTLY: <promise>DONE</promise>

Do NOT stop until every checkbox is verified. If you hit a blocker, document it in ralph_history.txt and continue with what you can.
PROMPT
)

    log "Prompt prepared, launching Claude Code..."

    # Run Claude Code with the prompt
    # --print for non-interactive mode, -p for prompt
    # --dangerously-skip-permissions: YOLO mode for autonomous iteration (per Ralph methodology)
    # --bare: skip hooks/LSP/auto-memory; faster + more predictable for batch runs
    claude --print --dangerously-skip-permissions --bare -p "$prompt" 2>&1 | tee -a "$iter_log" || {
        log "Claude Code exited with error (code: $?)"
    }

    # Check if DONE signal was in output
    if grep -q '<promise>DONE</promise>' "$iter_log" 2>/dev/null; then
        log "✓ DONE signal received for $spec_name"
        echo "DONE - $spec_name - $(date)" >> "$HISTORY_FILE"
        return 0
    else
        log "✗ No DONE signal for $spec_name"
        echo "ATTEMPTED - $spec_name - iter=$iter - $(date)" >> "$HISTORY_FILE"
        return 1
    fi
}

# Main loop
main() {
    log "============================================"
    log "Ralph Wiggum Loop Started"
    log "Session: $SESSION_ID"
    log "Mode: $MODE"
    log "Max iterations: $MAX_ITERATIONS"
    log "============================================"

    local iter=0
    while [[ $iter -lt $MAX_ITERATIONS ]]; do
        iter=$((iter + 1))

        # Get pending specs
        local pending
        pending="$(get_pending_specs)"

        if [[ -z "$pending" ]]; then
            log "No pending specs found. All done!"
            break
        fi

        # Pick the first pending spec
        local next_spec
        next_spec="$(echo "$pending" | head -1)"
        local next_name
        next_name="$(basename "$next_spec")"

        log "Next spec: $next_name ($(echo "$pending" | wc -l | tr -d ' ') remaining)"

        if run_iteration "$next_spec" "$next_name" "$iter"; then
            log "Iteration $iter succeeded"
        else
            log "Iteration $iter did not complete. Retrying next loop..."
        fi

        # Small pause between iterations
        sleep 2
    done

    log "============================================"
    log "Ralph Wiggum Loop Complete"
    log "Iterations: $iter"
    log "Session log: $SESSION_LOG"
    log "============================================"
}

main "$@"
