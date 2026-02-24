#!/bin/bash
set -euo pipefail

COMMAND_NAME="$(basename "$0")"
COMPLETION_SIGIL="<promise>COMPLETE</promise>"
DEFAULT_AGENT_FALLBACK="cursor"
DEFAULT_CURSOR_MODEL="gpt-5.3-codex-xhigh"
INSTALL_COMMAND_NAME="ralph"
INSTALL_FORMATTER_NAME="ralph-format-log.mjs"
INSTALL_SCRIPT_URL="https://raw.githubusercontent.com/prebootai/ralph/refs/heads/main/install.sh"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/preboot-ralph"
CONFIG_FILE="$CONFIG_DIR/config"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FORMATTER_DEFAULT="$SCRIPT_DIR/format-log.mjs"
FORMATTER_INSTALLED="$SCRIPT_DIR/ralph-format-log.mjs"
FORMATTER=""
TMP_FILES=()

cleanup_tmp_files() {
  local file
  set +u
  for file in "${TMP_FILES[@]}"; do
    [ -f "$file" ] && rm -f "$file"
  done
  set -u
}
trap cleanup_tmp_files EXIT

if [ -f "$FORMATTER_DEFAULT" ]; then
  FORMATTER="$FORMATTER_DEFAULT"
elif [ -f "$FORMATTER_INSTALLED" ]; then
  FORMATTER="$FORMATTER_INSTALLED"
fi

warn() {
  echo "[warn] $1" >&2
}

die() {
  echo "ERROR: $1" >&2
  exit 1
}

show_help() {
  cat <<EOF
Preboot Ralph

Usage:
  $COMMAND_NAME <prd-file> [max-iterations] [--agent=<cursor|codex|claude>] [--model=<model-id>]
  $COMMAND_NAME run <prd-file> [max-iterations] [--agent=<cursor|codex|claude>] [--model=<model-id>]
  $COMMAND_NAME set-default-agent <cursor|codex|claude>
  $COMMAND_NAME set-default-model <model-id>
  $COMMAND_NAME list-models [--agent=<cursor|codex|claude>]
  $COMMAND_NAME uninstall
  $COMMAND_NAME update
  $COMMAND_NAME help
  $COMMAND_NAME --help

Commands:
  run                 Run the PRD loop (default command if omitted)
  set-default-agent   Persist default agent in config
  set-default-model   Persist default model in config
  list-models         List models per agent using available CLIs
  uninstall           Remove installed command + saved config
  update              Reinstall Preboot Ralph from latest install script
  help                Show this help text

Examples:
  $COMMAND_NAME feature.prd.md
  $COMMAND_NAME feature.prd.md 2 --agent=codex --model=gpt-5.3-codex
  $COMMAND_NAME set-default-agent claude
  $COMMAND_NAME set-default-model claude-sonnet-4-5-20250929
  $COMMAND_NAME list-models
  $COMMAND_NAME uninstall
  $COMMAND_NAME update
EOF
}

is_valid_agent() {
  case "$1" in
    cursor|codex|claude) return 0 ;;
    *) return 1 ;;
  esac
}

agent_cli_name() {
  case "$1" in
    cursor) echo "agent" ;;
    codex) echo "codex" ;;
    claude) echo "claude" ;;
    *) echo "" ;;
  esac
}

ensure_config_dir() {
  mkdir -p "$CONFIG_DIR"
}

load_config() {
  DEFAULT_AGENT=""
  DEFAULT_MODEL=""

  if [ -f "$CONFIG_FILE" ]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
  fi

  DEFAULT_AGENT="${DEFAULT_AGENT:-$DEFAULT_AGENT_FALLBACK}"
  DEFAULT_MODEL="${DEFAULT_MODEL:-}"

  if ! is_valid_agent "$DEFAULT_AGENT"; then
    warn "Invalid DEFAULT_AGENT '$DEFAULT_AGENT' in $CONFIG_FILE; using '$DEFAULT_AGENT_FALLBACK'."
    DEFAULT_AGENT="$DEFAULT_AGENT_FALLBACK"
  fi
}

write_config() {
  ensure_config_dir
  {
    printf "DEFAULT_AGENT=%q\n" "$DEFAULT_AGENT"
    printf "DEFAULT_MODEL=%q\n" "$DEFAULT_MODEL"
  } > "$CONFIG_FILE"
}

set_default_agent_command() {
  local new_agent="$1"
  load_config

  if ! is_valid_agent "$new_agent"; then
    die "Invalid agent '$new_agent'. Allowed: cursor, codex, claude."
  fi

  DEFAULT_AGENT="$new_agent"
  write_config
  echo "Default agent set to '$DEFAULT_AGENT' in $CONFIG_FILE"
}

set_default_model_command() {
  local new_model="$1"
  load_config

  if [ -z "$new_model" ]; then
    die "Model value cannot be empty."
  fi

  DEFAULT_MODEL="$new_model"
  write_config
  echo "Default model set to '$DEFAULT_MODEL' in $CONFIG_FILE"
}

require_agent_cli() {
  local selected_agent="$1"
  local cli_name
  cli_name="$(agent_cli_name "$selected_agent")"

  if [ -z "$cli_name" ]; then
    die "Unknown agent '$selected_agent'."
  fi

  if ! command -v "$cli_name" >/dev/null 2>&1; then
    die "Selected agent '$selected_agent' requires '$cli_name' CLI, but it is not installed or not in PATH."
  fi
}

build_iteration_prompt() {
  local prd_file="$1"
  local progress_file="$2"
  cat <<EOF
Read the file at $prd_file and the progress file at $progress_file.
You are executing a Preboot Ralph loop on this PRD.

Rules:
- Read the PRD and the progress file.
- Find the NEXT incomplete task (unchecked checkbox).
- Implement that ONE task fully. Do not skip ahead.
- Run tests and typechecks check after making changes BEFORE commiting your changes.
- Commit your changes with a descriptive message.
- Append a single line to $progress_file summarizing what you completed and the current date/time.
- Mark the task as complete in the PRD by changing [ ] to [x].
- ONLY DO ONE TASK PER ITERATION.
- If ALL tasks in the PRD are complete, output $COMPLETION_SIGIL and nothing else after it.
EOF
}

run_cursor_iteration() {
  local prompt="$1"
  local model="$2"
  local iteration_output="$3"
  local -a cmd

  [ -n "$FORMATTER" ] || die "Formatter script not found. Expected $FORMATTER_DEFAULT or $FORMATTER_INSTALLED."

  cmd=(
    agent
    -p
    --output-format
    stream-json
    --stream-partial-output
    --yolo
    --trust
  )

  if [ -n "$model" ]; then
    cmd+=(--model "$model")
  fi

  cmd+=("$prompt")
  "${cmd[@]}" 2>&1 | tee "$iteration_output" | node "$FORMATTER"
}

run_codex_iteration() {
  local prompt="$1"
  local model="$2"
  local iteration_output="$3"
  local -a cmd

  cmd=(
    codex
    exec
    --dangerously-bypass-approvals-and-sandbox
    --skip-git-repo-check
  )

  if [ -n "$model" ]; then
    cmd+=(--model "$model")
  fi

  cmd+=("-")
  printf "%s\n" "$prompt" | "${cmd[@]}" 2>&1 | tee "$iteration_output"
}

run_claude_iteration() {
  local prompt="$1"
  local model="$2"
  local iteration_output="$3"
  local -a cmd

  cmd=(
    claude
    -p
    --dangerously-skip-permissions
    --output-format
    text
  )

  if [ -n "$model" ]; then
    cmd+=(--model "$model")
  fi

  cmd+=("$prompt")
  "${cmd[@]}" 2>&1 | tee "$iteration_output"
}

run_agent_iteration() {
  local selected_agent="$1"
  local prompt="$2"
  local model="$3"
  local iteration_output="$4"

  case "$selected_agent" in
    cursor) run_cursor_iteration "$prompt" "$model" "$iteration_output" ;;
    codex) run_codex_iteration "$prompt" "$model" "$iteration_output" ;;
    claude) run_claude_iteration "$prompt" "$model" "$iteration_output" ;;
    *) die "Unsupported agent '$selected_agent'." ;;
  esac
}

did_iteration_complete() {
  local selected_agent="$1"
  local iteration_output="$2"

  if [ "$selected_agent" = "cursor" ]; then
    grep '"type":"assistant"' "$iteration_output" | grep -q "$COMPLETION_SIGIL"
  else
    grep -q "$COMPLETION_SIGIL" "$iteration_output"
  fi
}

list_cursor_models() {
  if ! command -v agent >/dev/null 2>&1; then
    warn "cursor: 'agent' CLI is not installed."
    return 0
  fi

  if ! agent --list-models; then
    warn "cursor: failed to list models from 'agent'."
  fi
}

list_codex_models() {
  if ! command -v codex >/dev/null 2>&1; then
    warn "codex: 'codex' CLI is not installed."
    return 0
  fi

  warn "codex: this CLI does not provide a built-in model listing command."
  echo "Use: codex exec --model <model-id> ..."
}

list_claude_models() {
  if ! command -v claude >/dev/null 2>&1; then
    warn "claude: 'claude' CLI is not installed."
    return 0
  fi

  warn "claude: this CLI does not provide a built-in model listing command."
  echo "Use: claude -p --model <model-id> \"<prompt>\""
}

list_models_command() {
  local selected_agent="${1:-}"

  if [ -n "$selected_agent" ] && ! is_valid_agent "$selected_agent"; then
    die "Invalid --agent value '$selected_agent'. Allowed: cursor, codex, claude."
  fi

  if [ -n "$selected_agent" ]; then
    echo "=== Models: $selected_agent ==="
    case "$selected_agent" in
      cursor) list_cursor_models ;;
      codex) list_codex_models ;;
      claude) list_claude_models ;;
    esac
    return 0
  fi

  echo "=== Models: cursor ==="
  list_cursor_models
  echo ""
  echo "=== Models: codex ==="
  list_codex_models
  echo ""
  echo "=== Models: claude ==="
  list_claude_models
}

uninstall_command() {
  local installed_command=""
  local installed_formatter=""
  local is_managed_install=0
  local removed_any=0

  installed_command="$(command -v "$INSTALL_COMMAND_NAME" 2>/dev/null || true)"
  if [ -n "$installed_command" ] && [ -f "$installed_command" ]; then
    installed_formatter="$(dirname "$installed_command")/$INSTALL_FORMATTER_NAME"

    if [ -f "$installed_formatter" ]; then
      is_managed_install=1
    elif grep -q "Preboot Ralph" "$installed_command" 2>/dev/null; then
      is_managed_install=1
    fi

    if [ "$is_managed_install" -eq 1 ]; then
      if rm -f "$installed_command"; then
        echo "Removed command: $installed_command"
        removed_any=1
      else
        die "Failed to remove command: $installed_command"
      fi

      if [ -f "$installed_formatter" ]; then
        if rm -f "$installed_formatter"; then
          echo "Removed formatter: $installed_formatter"
          removed_any=1
        else
          die "Failed to remove formatter: $installed_formatter"
        fi
      fi
    else
      warn "Found '$INSTALL_COMMAND_NAME' at $installed_command, but it does not look like a Preboot Ralph install. Skipping binary removal."
    fi
  else
    warn "No '$INSTALL_COMMAND_NAME' command found in PATH."
  fi

  if [ -f "$CONFIG_FILE" ]; then
    if rm -f "$CONFIG_FILE"; then
      echo "Removed config: $CONFIG_FILE"
      removed_any=1
    else
      die "Failed to remove config: $CONFIG_FILE"
    fi
  else
    warn "No config file found at $CONFIG_FILE."
  fi

  if [ -d "$CONFIG_DIR" ]; then
    rmdir "$CONFIG_DIR" 2>/dev/null || true
  fi

  if [ "$removed_any" -eq 0 ]; then
    echo "Nothing to uninstall."
    return 0
  fi

  echo "Uninstall complete."
}

update_command() {
  uninstall_command
  echo "Reinstalling Preboot Ralph..."
  curl -fsSL "$INSTALL_SCRIPT_URL" | bash
  echo "Update complete."
}

run_loop() {
  local prd_file="$1"
  local max_iterations_arg="$2"
  local selected_agent="$3"
  local selected_model="$4"
  local progress_file
  local task_count
  local max_iterations
  local iteration_output
  local prompt
  local i

  if [ ! -f "$prd_file" ]; then
    die "PRD file not found at $prd_file"
  fi

  progress_file="${prd_file%.md}.progress.txt"
  task_count="$(grep -c '^\- \[ \]' "$prd_file" || true)"
  max_iterations="${max_iterations_arg:-$task_count}"

  if ! [[ "$max_iterations" =~ ^[0-9]+$ ]]; then
    die "max-iterations must be a positive integer."
  fi

  if [ "$max_iterations" -eq 0 ]; then
    die "No incomplete tasks found in $prd_file"
  fi

  touch "$progress_file"

  echo "=== Preboot Ralph ==="
  echo "PRD:            $prd_file"
  echo "Progress:       $progress_file"
  echo "Tasks found:    $task_count"
  echo "Max iterations: $max_iterations"
  echo "Agent:          $selected_agent"
  echo "Model:          ${selected_model:-<agent default>}"
  echo ""

  for ((i = 1; i <= max_iterations; i++)); do
    echo "--- Iteration $i of $max_iterations ---"

    prompt="$(build_iteration_prompt "$prd_file" "$progress_file")"
    iteration_output="$(mktemp -t preboot-ralph-iteration.XXXXXX)"
    TMP_FILES+=("$iteration_output")

    run_agent_iteration "$selected_agent" "$prompt" "$selected_model" "$iteration_output"

    echo ""

    if did_iteration_complete "$selected_agent" "$iteration_output"; then
      echo "=== PRD complete after $i iteration(s). ==="
      return 0
    fi
  done

  echo "=== Reached max iterations ($max_iterations). Review progress in $progress_file ==="
}

run_command() {
  local prd_file=""
  local max_iterations=""
  local override_agent=""
  local override_model=""
  local arg
  local selected_agent
  local selected_model

  for arg in "$@"; do
    case "$arg" in
      --agent=*)
        override_agent="${arg#--agent=}"
        ;;
      --model=*)
        override_model="${arg#--model=}"
        ;;
      --help|-h)
        show_help
        exit 0
        ;;
      --agent|--model)
        die "Use --agent=<value> and --model=<value>."
        ;;
      --*)
        die "Unknown option: $arg"
        ;;
      *)
        if [ -z "$prd_file" ]; then
          prd_file="$arg"
        elif [ -z "$max_iterations" ]; then
          max_iterations="$arg"
        else
          die "Unexpected argument: $arg"
        fi
        ;;
    esac
  done

  if [ -z "$prd_file" ]; then
    echo "ERROR: missing required <prd-file>" >&2
    echo "" >&2
    show_help
    exit 1
  fi

  if [ -n "$max_iterations" ] && ! [[ "$max_iterations" =~ ^[0-9]+$ ]]; then
    die "max-iterations must be a positive integer."
  fi

  load_config
  selected_agent="${override_agent:-$DEFAULT_AGENT}"
  selected_model="${override_model:-$DEFAULT_MODEL}"

  if ! is_valid_agent "$selected_agent"; then
    die "Invalid agent '$selected_agent'. Allowed: cursor, codex, claude."
  fi

  if [ "$selected_agent" = "cursor" ] && [ -z "$selected_model" ]; then
    selected_model="$DEFAULT_CURSOR_MODEL"
  fi

  require_agent_cli "$selected_agent"
  run_loop "$prd_file" "$max_iterations" "$selected_agent" "$selected_model"
}

main() {
  local subcommand="${1:-}"
  local selected_agent=""
  local arg

  case "$subcommand" in
    help|--help|-h)
      show_help
      exit 0
      ;;
    set-default-agent)
      shift
      [ -n "${1:-}" ] || die "Usage: $COMMAND_NAME set-default-agent <cursor|codex|claude>"
      set_default_agent_command "$1"
      ;;
    set-default-model)
      shift
      [ -n "${1:-}" ] || die "Usage: $COMMAND_NAME set-default-model <model-id>"
      set_default_model_command "$1"
      ;;
    list-models)
      shift
      for arg in "$@"; do
        case "$arg" in
          --agent=*) selected_agent="${arg#--agent=}" ;;
          --help|-h)
            echo "Usage: $COMMAND_NAME list-models [--agent=<cursor|codex|claude>]"
            exit 0
            ;;
          *)
            die "Unknown option for list-models: $arg"
            ;;
        esac
      done
      list_models_command "$selected_agent"
      ;;
    uninstall)
      shift
      for arg in "$@"; do
        case "$arg" in
          --help|-h)
            echo "Usage: $COMMAND_NAME uninstall"
            exit 0
            ;;
          *)
            die "Unknown option for uninstall: $arg"
            ;;
        esac
      done
      uninstall_command
      ;;
    update)
      shift
      for arg in "$@"; do
        case "$arg" in
          --help|-h)
            echo "Usage: $COMMAND_NAME update"
            exit 0
            ;;
          *)
            die "Unknown option for update: $arg"
            ;;
        esac
      done
      update_command
      ;;
    run)
      shift
      run_command "$@"
      ;;
    "")
      show_help
      exit 1
      ;;
    *)
      run_command "$@"
      ;;
  esac
}

main "$@"
