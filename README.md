# Preboot Ralph

![Shell](https://img.shields.io/badge/shell-bash-121011?logo=gnu-bash)
![Node](https://img.shields.io/badge/node-%3E%3D18-339933?logo=node.js&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-blue.svg)
![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)
![Status](https://img.shields.io/badge/status-experimental-orange)

Run your PRD checklist as a focused execution loop: **one task, one iteration, one clean commit**.

Preboot Ralph is a tiny automation wrapper that repeatedly asks an agent to complete the next unchecked PRD task, validate changes, commit, and track progress until everything is done.

## Highlights

- Enforces strict single-task execution (`- [ ]` -> `- [x]`)
- Produces readable live logs from streamed JSON events
- Keeps a persistent progress journal per PRD
- Supports manual checkpoints via markdown separator lines (`---`)
- Sends native desktop notifications when checkpoint separators are reached
- Stops automatically when all PRD tasks are complete

## Repository

```text
.
|-- install.sh        # macOS/Linux installer for global `ralph` command
|-- ralph.sh          # Main loop orchestrator
`-- format-log.mjs    # JSON stream -> readable terminal formatter
```

## Requirements

- Bash (`ralph.sh`)
- Node.js 18+ (`format-log.mjs`)
- At least one supported agent CLI in your `PATH`: `agent` (Cursor), `codex`, `claude`, or `opencode`
- Optional for Linux notifications: `notify-send` (typically provided by `libnotify`)
- Git repo context (the loop prompt requires committing each completed task)

## Installation (macOS/Linux)

Install globally as `ralph` from a local clone:

```bash
./install.sh
```

Install without cloning:

```bash
curl -fsSL https://raw.githubusercontent.com/prebootai/ralph/refs/heads/main/install.sh | bash
```

Set default agent non-interactively (works well for CI or non-interactive shells):

```bash
curl -fsSL https://raw.githubusercontent.com/prebootai/ralph/refs/heads/main/install.sh | bash -s -- --default-agent codex
```

Installer behavior:
- Supports macOS and Linux
- Validates Node.js 18+
- Installs both the bash entrypoint and formatter script into a writable directory already in your `PATH`
- Prompts you to choose a default agent (`cursor`, `codex`, `claude`, or `opencode`)
- Lets you target a specific `PATH` directory:

```bash
./install.sh --dir "$HOME/.local/bin"
```

Set default agent non-interactively (local clone):

```bash
./install.sh --default-agent codex
```

Uninstall globally installed binaries and saved defaults:

```bash
ralph uninstall
```

## Quick Start

1) Create a PRD file with markdown checkboxes:

```md
# Feature: Add reporting

- [ ] Add database migration for reports table
- [ ] Implement report creation endpoint
- [ ] Add tests for report validation
```

2) Run the loop (global install):

```bash
ralph feature.prd.md
```

3) Optionally cap iterations:

```bash
ralph feature.prd.md 2
```

Alternative (without installing globally):

```bash
./ralph.sh feature.prd.md
```

## Command Reference

```bash
ralph <prd-file> [max-iterations] [--agent=<cursor|codex|claude|opencode>] [--model=<model-id>]
ralph run <prd-file> [max-iterations] [--agent=<cursor|codex|claude|opencode>] [--model=<model-id>]
ralph set-default-agent <cursor|codex|claude|opencode>
ralph set-default-model <model-id>
ralph list-models
ralph list-models --agent=opencode
ralph uninstall
ralph help
ralph --help
# or
./ralph.sh <prd-file> [max-iterations] [--agent=<cursor|codex|claude|opencode>] [--model=<model-id>]
./ralph.sh set-default-agent <cursor|codex|claude|opencode>
./ralph.sh set-default-model <model-id>
./ralph.sh list-models
./ralph.sh uninstall
./ralph.sh help
./ralph.sh --help
```

- `<prd-file>`: required path to a markdown PRD
- `[max-iterations]`: optional hard cap; defaults to unchecked task count
- `--agent=<...>`: per-run agent override (`cursor`, `codex`, `claude`, or `opencode`)
- `--model=<...>`: per-run model override (model id string accepted by selected CLI)
- `set-default-agent`: persist default agent in `~/.config/preboot-ralph/config` (or `XDG_CONFIG_HOME`)
- `set-default-model`: persist default model in `~/.config/preboot-ralph/config` (or `XDG_CONFIG_HOME`)
- `list-models`: print model listings from installed CLIs when available
- `uninstall`: remove installed `ralph` + `ralph-format-log.mjs` and delete saved config
- `help` / `--help`: show command help and exit

## What Happens Each Iteration

`ralph.sh` directs the selected agent (`cursor`, `codex`, `claude`, or `opencode`) to:
1. Read the PRD and progress file.
2. Complete only the next unchecked task.
3. Run `npm run check`.
4. Commit with a descriptive message.
5. Append one progress line with timestamp.
6. Mark the PRD task complete.

It exits early when the completion sigil `<promise>COMPLETE</promise>` is detected.

## Agent Model Listing Notes

- `cursor`: uses native CLI model listing (`agent --list-models`)
- `codex`: CLI currently does not expose a built-in model-list command
- `claude`: CLI currently does not expose a built-in model-list command
- `opencode`: uses native CLI model listing (`opencode models`)

`ralph list-models` prints warnings for unsupported or uninstalled CLIs.

## Output Files

For `feature.prd.md`, Preboot Ralph writes:
- `feature.prd.progress.txt`: append-only progress summaries
- `feature.prd.log`: full loop log (reset at start of each run)

## PRD Authoring Tips

- Keep each checkbox task atomic and verifiable.
- Use implementation-focused wording.
- Avoid bundling multiple deliverables in a single item.
- Use exact syntax: `- [ ] Task description`.
- Use a standalone `---` line as a checkpoint barrier; Ralph stops before tasks below it.

## Readable Log Stream

`format-log.mjs` transforms streamed JSON events into compact terminal labels like:
- `[INIT]`, `[PROMPT]`, `[THINKING]`, `[ASSISTANT]`
- `[TOOL]` with short tool summaries
- `[RESULT]` and `[ERROR]` output

This gives you clean terminal visibility while preserving full raw context in the `.log` file.

## Contributing

Contributions are welcome. Start with `CONTRIBUTING.md` for setup, style, and pull request guidance.

If you are proposing behavior changes, include:
- updated docs
- a clear reproduction path
- verification steps in your PR description

## License

This project is licensed under the MIT License. See `LICENSE`.
