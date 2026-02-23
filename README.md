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
- Stops automatically when all PRD tasks are complete

## Repository

```text
.
|-- ralph.sh          # Main loop orchestrator
`-- format-log.mjs    # JSON stream -> readable terminal formatter
```

## Requirements

- Bash (`ralph.sh`)
- Node.js 18+ (`format-log.mjs`)
- `agent` CLI available in your `PATH`
- Git repo context (the loop prompt requires committing each completed task)

## Quick Start

1) Create a PRD file with markdown checkboxes:

```md
# Feature: Add reporting

- [ ] Add database migration for reports table
- [ ] Implement report creation endpoint
- [ ] Add tests for report validation
```

2) Run the loop:

```bash
./ralph.sh feature.prd.md
```

3) Optionally cap iterations:

```bash
./ralph.sh feature.prd.md 2
```

## Command Reference

```bash
./ralph.sh <prd-file> [max-iterations]
```

- `<prd-file>`: required path to a markdown PRD
- `[max-iterations]`: optional hard cap; defaults to unchecked task count

## What Happens Each Iteration

`ralph.sh` directs the agent to:
1. Read the PRD and progress file.
2. Complete only the next unchecked task.
3. Run `npm run check`.
4. Commit with a descriptive message.
5. Append one progress line with timestamp.
6. Mark the PRD task complete.

It exits early when the completion sigil `<promise>COMPLETE</promise>` is detected.

## Output Files

For `feature.prd.md`, Preboot Ralph writes:
- `feature.prd.progress.txt`: append-only progress summaries
- `feature.prd.log`: full loop log (reset at start of each run)

## PRD Authoring Tips

- Keep each checkbox task atomic and verifiable.
- Use implementation-focused wording.
- Avoid bundling multiple deliverables in a single item.
- Use exact syntax: `- [ ] Task description`.

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
