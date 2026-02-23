# Contributing to Preboot Ralph

Thanks for contributing.

## Before You Start

- Open an issue for significant behavior changes or architecture proposals.
- Keep pull requests small and focused (single concern if possible).
- Update docs when behavior or usage changes.

## Local Setup

1) Clone and enter the repo:

```bash
git clone <your-fork-url>
cd preboot-ralph
```

2) Ensure prerequisites are installed:
- Bash
- Node.js 18+
- One supported agent CLI in your `PATH`: `agent`, `codex`, or `claude`

3) Make scripts executable if needed:

```bash
chmod +x ralph.sh
```

## Development Guidelines

- Prefer clear, minimal shell logic over clever one-liners.
- Keep behavior deterministic and easy to audit in logs.
- Preserve the one-task-per-iteration contract.
- Keep formatter output concise and readable.

## Testing Changes

Validate with a small PRD fixture:

```md
- [ ] Example task one
- [ ] Example task two
```

Then run:

```bash
./ralph.sh test.prd.md 1
```

Check:
- expected terminal formatting
- `test.prd.log` and `test.prd.progress.txt` behavior
- proper PRD checkbox update semantics

## Pull Request Checklist

- [ ] Code and docs are updated together
- [ ] Change is scoped and explained clearly
- [ ] Reproduction/verification steps are included
- [ ] No unrelated refactors bundled

## Commit Messages

Use descriptive messages that explain intent, not only file-level changes.

Examples:
- `improve README for open-source onboarding`
- `simplify log formatter output for tool events`
- `tighten PRD task detection in loop script`
