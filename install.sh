#!/usr/bin/env bash
set -euo pipefail

MIN_NODE_MAJOR=18
INSTALL_COMMAND_NAME="ralph"
INSTALL_FORMATTER_NAME="ralph-format-log.mjs"
DEFAULT_AGENT_FALLBACK="cursor"
REMOTE_REPO_OWNER="${PREBOOT_RALPH_REPO_OWNER:-prebootai}"
REMOTE_REPO_NAME="${PREBOOT_RALPH_REPO_NAME:-ralph}"
REMOTE_REF="${PREBOOT_RALPH_REF:-main}"
REMOTE_RAW_BASE="${PREBOOT_RALPH_RAW_BASE:-https://raw.githubusercontent.com/${REMOTE_REPO_OWNER}/${REMOTE_REPO_NAME}/${REMOTE_REF}}"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/preboot-ralph"
CONFIG_FILE="$CONFIG_DIR/config"
TEMP_SOURCE_DIR=""

if [[ -t 1 ]]; then
  BOLD="$(printf '\033[1m')"
  DIM="$(printf '\033[2m')"
  BLUE="$(printf '\033[34m')"
  GREEN="$(printf '\033[32m')"
  YELLOW="$(printf '\033[33m')"
  RED="$(printf '\033[31m')"
  RESET="$(printf '\033[0m')"
else
  BOLD=""
  DIM=""
  BLUE=""
  GREEN=""
  YELLOW=""
  RED=""
  RESET=""
fi

log_step() {
  printf "%b==>%b %s\n" "${BLUE}${BOLD}" "$RESET" "$1"
}

log_ok() {
  printf "%b[ok]%b %s\n" "$GREEN" "$RESET" "$1"
}

log_warn() {
  printf "%b[warn]%b %s\n" "$YELLOW" "$RESET" "$1"
}

log_error() {
  printf "%b[error]%b %s\n" "$RED" "$RESET" "$1" >&2
}

die() {
  log_error "$1"
  exit 1
}

cleanup_temp_source_dir() {
  if [[ -n "${TEMP_SOURCE_DIR:-}" && -d "$TEMP_SOURCE_DIR" ]]; then
    rm -rf "$TEMP_SOURCE_DIR"
  fi
}
trap cleanup_temp_source_dir EXIT

usage() {
  cat <<'EOF'
Install Preboot Ralph as a global `ralph` command.

Usage:
  ./install.sh [--dir <path>] [--default-agent <cursor|codex|claude|opencode>]

Options:
  --dir <path>                  Install into this existing directory (must already be in PATH)
  --default-agent <agent>       Set default agent without interactive prompt (cursor|codex|claude|opencode)
  -h, --help                  Show this help text
EOF
}

normalize_dir() {
  local dir="$1"
  if [[ "$dir" != "/" ]]; then
    dir="${dir%/}"
  fi
  printf "%s" "$dir"
}

path_contains_dir() {
  local needle
  local entry
  local normalized_entry
  local path_entries
  needle="$(normalize_dir "$1")"

  IFS=':' read -r -a path_entries <<< "${PATH:-}"
  for entry in "${path_entries[@]}"; do
    [[ -z "$entry" ]] && continue
    normalized_entry="$(normalize_dir "$entry")"
    if [[ "$normalized_entry" == "$needle" ]]; then
      return 0
    fi
  done

  return 1
}

choose_writable_path_dir() {
  local entry
  local path_entries
  local home_dir
  local preferred
  local -a preferred_dirs=()

  home_dir="${HOME:-}"
  if [[ -n "$home_dir" ]]; then
    preferred_dirs+=("$home_dir/.local/bin")
    preferred_dirs+=("$home_dir/bin")
  fi
  preferred_dirs+=("/usr/local/bin")
  preferred_dirs+=("/opt/homebrew/bin")

  for preferred in "${preferred_dirs[@]}"; do
    if path_contains_dir "$preferred" && [[ -d "$preferred" && -w "$preferred" ]]; then
      printf "%s" "$preferred"
      return 0
    fi
  done

  IFS=':' read -r -a path_entries <<< "${PATH:-}"
  for entry in "${path_entries[@]}"; do
    [[ -z "$entry" || "$entry" == "." ]] && continue
    if [[ -d "$entry" && -w "$entry" ]]; then
      printf "%s" "$entry"
      return 0
    fi
  done

  return 1
}

is_valid_agent() {
  case "$1" in
    cursor|codex|claude|opencode) return 0 ;;
    *) return 1 ;;
  esac
}

agent_cli_name() {
  case "$1" in
    cursor) echo "agent" ;;
    codex) echo "codex" ;;
    claude) echo "claude" ;;
    opencode) echo "opencode" ;;
    *) echo "" ;;
  esac
}

agent_status_label() {
  local agent_name="$1"
  local cli_name
  cli_name="$(agent_cli_name "$agent_name")"
  if command -v "$cli_name" >/dev/null 2>&1; then
    printf "%binstalled%b (%s)" "$GREEN" "$RESET" "$cli_name"
  else
    printf "%bnot installed%b (%s)" "$YELLOW" "$RESET" "$cli_name"
  fi
}

detect_default_agent() {
  local candidate
  for candidate in cursor codex claude opencode; do
    if command -v "$(agent_cli_name "$candidate")" >/dev/null 2>&1; then
      printf "%s" "$candidate"
      return 0
    fi
  done
  printf "%s" "$DEFAULT_AGENT_FALLBACK"
}

prompt_for_default_agent() {
  local suggested="$1"
  local response=""

  printf "\n" >&2
  log_step "Choose a default agent" >&2
  printf "  1) cursor    [%s]\n" "$(agent_status_label cursor)" >&2
  printf "  2) codex     [%s]\n" "$(agent_status_label codex)" >&2
  printf "  3) claude    [%s]\n" "$(agent_status_label claude)" >&2
  printf "  4) opencode  [%s]\n" "$(agent_status_label opencode)" >&2
  printf "Press Enter for default [%s]: " "$suggested" >&2
  if [[ -t 0 ]]; then
    read -r response
  elif [[ -r /dev/tty ]]; then
    read -r response < /dev/tty
  else
    printf "%s" "$suggested"
    return 0
  fi

  case "$response" in
    "" ) printf "%s" "$suggested" ;;
    1|cursor) printf "cursor" ;;
    2|codex) printf "codex" ;;
    3|claude) printf "claude" ;;
    4|opencode) printf "opencode" ;;
    *)
      log_warn "Invalid selection '$response'; using '$suggested'." >&2
      printf "%s" "$suggested"
      ;;
  esac
}

write_defaults_config() {
  local default_agent="$1"
  local default_model="$2"
  mkdir -p "$CONFIG_DIR"
  {
    printf "DEFAULT_AGENT=%q\n" "$default_agent"
    printf "DEFAULT_MODEL=%q\n" "$default_model"
  } > "$CONFIG_FILE"
}

download_file() {
  local url="$1"
  local dest="$2"
  if command -v curl >/dev/null 2>&1; then
    curl --fail --silent --show-error --location "$url" --output "$dest"
  elif command -v wget >/dev/null 2>&1; then
    wget --quiet --output-document="$dest" "$url"
  else
    die "Missing downloader. Install curl or wget and rerun."
  fi
}

resolve_source_file() {
  local script_source="${BASH_SOURCE[0]:-}"
  local script_dir=""
  local remote_ralph_url="$REMOTE_RAW_BASE/ralph.sh"
  local remote_formatter_url="$REMOTE_RAW_BASE/format-log.mjs"

  if [[ -n "$script_source" ]]; then
    script_dir="$(cd "$(dirname "$script_source")" && pwd)"
  else
    script_dir="$(pwd)"
  fi

  SOURCE_RALPH="$script_dir/ralph.sh"
  SOURCE_FORMATTER="$script_dir/format-log.mjs"
  if [[ -f "$SOURCE_RALPH" && -f "$SOURCE_FORMATTER" ]]; then
    return 0
  fi

  log_step "Fetching installer payload"
  TEMP_SOURCE_DIR="$(mktemp -d)"
  SOURCE_RALPH="$TEMP_SOURCE_DIR/ralph.sh"
  SOURCE_FORMATTER="$TEMP_SOURCE_DIR/format-log.mjs"

  if ! download_file "$remote_ralph_url" "$SOURCE_RALPH"; then
    die "Failed to download: $remote_ralph_url"
  fi
  if ! download_file "$remote_formatter_url" "$SOURCE_FORMATTER"; then
    die "Failed to download: $remote_formatter_url"
  fi
  chmod 0755 "$SOURCE_RALPH" "$SOURCE_FORMATTER"
  log_ok "Fetched scripts from: $REMOTE_RAW_BASE"
}

TARGET_DIR=""
DEFAULT_AGENT_INPUT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)
      shift
      [[ $# -gt 0 ]] || die "Missing value for --dir."
      TARGET_DIR="$1"
      ;;
    --default-agent)
      shift
      [[ $# -gt 0 ]] || die "Missing value for --default-agent."
      DEFAULT_AGENT_INPUT="$1"
      ;;
    --default-agent=*)
      DEFAULT_AGENT_INPUT="${1#--default-agent=}"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1 (run ./install.sh --help)"
      ;;
  esac
  shift
done

SOURCE_RALPH=""
SOURCE_FORMATTER=""
resolve_source_file

printf "%bPreboot Ralph Installer%b\n" "$BOLD" "$RESET"
printf "%bInstalls ralph + formatter into your PATH.%b\n\n" "$DIM" "$RESET"

log_step "Checking platform support"
case "$(uname -s)" in
  Darwin)
    log_ok "Detected macOS"
    ;;
  Linux)
    log_ok "Detected Linux"
    ;;
  *)
    die "Unsupported OS. This installer supports macOS and Linux only."
    ;;
esac

log_step "Checking Node.js version"
if ! command -v node >/dev/null 2>&1; then
  die "Node.js is not installed. Please install Node.js ${MIN_NODE_MAJOR}+ and rerun."
fi

NODE_VERSION="$(node --version 2>/dev/null || true)"
NODE_MAJOR="${NODE_VERSION#v}"
NODE_MAJOR="${NODE_MAJOR%%.*}"

if ! [[ "$NODE_MAJOR" =~ ^[0-9]+$ ]]; then
  die "Could not parse Node.js version from: ${NODE_VERSION:-unknown}"
fi

if (( NODE_MAJOR < MIN_NODE_MAJOR )); then
  die "Node.js ${MIN_NODE_MAJOR}+ is required. Found ${NODE_VERSION}."
fi
log_ok "Found Node.js ${NODE_VERSION}"

log_step "Selecting install directory"
if [[ -n "$TARGET_DIR" ]]; then
  TARGET_DIR="$(normalize_dir "$TARGET_DIR")"
  [[ -d "$TARGET_DIR" ]] || die "Install directory does not exist: $TARGET_DIR"
  path_contains_dir "$TARGET_DIR" || die "Install directory must already be in PATH: $TARGET_DIR"
  [[ -w "$TARGET_DIR" ]] || die "No write permission for: $TARGET_DIR"
  log_ok "Using provided directory: $TARGET_DIR"
else
  if ! TARGET_DIR="$(choose_writable_path_dir)"; then
    die "No writable directory found in PATH. Re-run with --dir <path> or adjust permissions."
  fi
  log_ok "Using writable PATH directory: $TARGET_DIR"
fi

DEST_RALPH="$TARGET_DIR/$INSTALL_COMMAND_NAME"
DEST_FORMATTER="$TARGET_DIR/$INSTALL_FORMATTER_NAME"

log_step "Installing files"
if [[ -e "$DEST_RALPH" ]]; then
  log_warn "Overwriting existing command: $DEST_RALPH"
fi
if [[ -e "$DEST_FORMATTER" ]]; then
  log_warn "Overwriting existing formatter: $DEST_FORMATTER"
fi

install -m 0755 "$SOURCE_RALPH" "$DEST_RALPH"
install -m 0755 "$SOURCE_FORMATTER" "$DEST_FORMATTER"

log_ok "Installed command: $DEST_RALPH"
log_ok "Installed formatter: $DEST_FORMATTER"

log_step "Configuring defaults"
SAVED_DEFAULT_MODEL=""
if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
  SAVED_DEFAULT_MODEL="${DEFAULT_MODEL:-}"
fi

if [[ -n "$DEFAULT_AGENT_INPUT" ]]; then
  is_valid_agent "$DEFAULT_AGENT_INPUT" || die "Invalid --default-agent value '$DEFAULT_AGENT_INPUT'."
  CHOSEN_DEFAULT_AGENT="$DEFAULT_AGENT_INPUT"
  log_ok "Using provided default agent: $CHOSEN_DEFAULT_AGENT"
else
  CHOSEN_DEFAULT_AGENT="$(prompt_for_default_agent "$(detect_default_agent)")"
  log_ok "Selected default agent: $CHOSEN_DEFAULT_AGENT"
fi

if ! command -v "$(agent_cli_name "$CHOSEN_DEFAULT_AGENT")" >/dev/null 2>&1; then
  log_warn "Selected default agent '$CHOSEN_DEFAULT_AGENT' is not currently installed."
  log_warn "You can change it later using: ralph set-default-agent <cursor|codex|claude|opencode>"
fi

write_defaults_config "$CHOSEN_DEFAULT_AGENT" "$SAVED_DEFAULT_MODEL"
log_ok "Saved defaults to: $CONFIG_FILE"

log_step "Verifying command availability"
if command -v "$INSTALL_COMMAND_NAME" >/dev/null 2>&1; then
  log_ok "'$INSTALL_COMMAND_NAME' resolves to $(command -v "$INSTALL_COMMAND_NAME")"
else
  log_warn "Installed successfully, but '$INSTALL_COMMAND_NAME' is not visible in this shell yet."
  log_warn "Open a new terminal, then run: $INSTALL_COMMAND_NAME <prd-file> [max-iterations]"
fi

printf "\n%bInstall complete.%b\n" "$GREEN$BOLD" "$RESET"
printf "Run: %b%s <prd-file> [max-iterations]%b\n" "$BOLD" "$INSTALL_COMMAND_NAME" "$RESET"
printf "Defaults:\n"
printf "  %b%s set-default-agent <cursor|codex|claude|opencode>%b\n" "$BOLD" "$INSTALL_COMMAND_NAME" "$RESET"
printf "  %b%s set-default-model <model-id>%b\n" "$BOLD" "$INSTALL_COMMAND_NAME" "$RESET"
printf "  %b%s uninstall%b\n" "$BOLD" "$INSTALL_COMMAND_NAME" "$RESET"
