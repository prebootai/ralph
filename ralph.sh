#!/bin/bash
set -euo pipefail

if [ -z "${1:-}" ]; then
  echo "Usage: $0 <prd-file> [max-iterations]"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PRD="$1"
PROGRESS="${PRD%.md}.progress.txt"
LOG="${PRD%.md}.log"
COMPLETION_SIGIL="<promise>COMPLETE</promise>"
FORMATTER="$SCRIPT_DIR/format-log.mjs"

if [ ! -f "$PRD" ]; then
  echo "ERROR: PRD file not found at $PRD"
  exit 1
fi

TASK_COUNT=$(grep -c '^\- \[ \]' "$PRD" || true)
MAX_ITERATIONS="${2:-$TASK_COUNT}"

if [ "$MAX_ITERATIONS" -eq 0 ]; then
  echo "ERROR: No incomplete tasks found in $PRD"
  exit 1
fi

touch "$PROGRESS"
: > "$LOG"

echo "=== Preboot Ralph ==="
echo "PRD:            $PRD"
echo "Progress:       $PROGRESS"
echo "Log:            $LOG"
echo "Tasks found:    $TASK_COUNT"
echo "Max iterations: $MAX_ITERATIONS"
echo ""

for ((i = 1; i <= MAX_ITERATIONS; i++)); do
  echo "--- Iteration $i of $MAX_ITERATIONS ---"

  {
    echo "========================================"
    echo "ITERATION $i of $MAX_ITERATIONS"
    echo "STARTED: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo "========================================"
  } >> "$LOG"

  agent -p \
    --model gpt-5.3-codex-xhigh \
    --output-format stream-json \
    --stream-partial-output \
    --yolo \
    --trust \
    "Read the file at $PRD and the progress file at $PROGRESS.
You are executing a Preboot Ralph loop on this PRD.

Rules:
- Read the PRD and the progress file.
- Find the NEXT incomplete task (unchecked checkbox).
- Implement that ONE task fully. Do not skip ahead.
- Run npm run check from the project root after making changes.
- Commit your changes with a descriptive message.
- Append a single line to $PROGRESS summarizing what you completed and the current date/time.
- Mark the task as complete in the PRD by changing [ ] to [x].
- ONLY DO ONE TASK PER ITERATION.
- If ALL tasks in the PRD are complete, output $COMPLETION_SIGIL and nothing else after it." \
    2>&1 \
    | tee -a "$LOG" \
    | node "$FORMATTER"

  {
    echo ""
    echo "ENDED: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo ""
  } >> "$LOG"

  echo ""

  if grep '"type":"assistant"' "$LOG" | grep -q "$COMPLETION_SIGIL"; then
    echo "=== PRD complete after $i iteration(s). ==="
    exit 0
  fi
done

echo "=== Reached max iterations ($MAX_ITERATIONS). Review progress in $PROGRESS ==="
exit 0
