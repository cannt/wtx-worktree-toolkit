---
status: done
---

# Phase 3: `bin/wtx` dispatcher + canonical `WTX_ROOT` anchor

## Goal

Turn the empty `bin/wtx` stub into a real subcommand dispatcher and use it as the
canonical anchor for every script/hook that needs to source `lib/wtx-config.sh` or
resolve a relative `worktree.setup_hook`. Closes the three anchor-related findings
from the Phase 2 adversarial review.

## In scope

- `bin/wtx`: full implementation of `start | done | status | init | doctor | version | help`.
  - Resolve `WTX_ROOT` from the script's own location (follow symlinks, macOS `readlink`-safe).
  - Resolve `WORKSPACE_ROOT` from `git rev-parse --show-toplevel`, falling back to `$PWD`.
  - Export both before exec'ing child scripts.
  - `start|done|status` → `exec "$WTX_ROOT/scripts/worktree-<cmd>.sh" "$@"`.
  - `init` → interactive generator writes `$WORKSPACE_ROOT/wtx.toml` (refuses to overwrite).
  - `doctor` → green/red report for required (git, bash, python3, curl) + optional (gum,
    claude, timeout, jq) deps, prints resolved `WTX_ROOT`, `WORKSPACE_ROOT`, config path.
  - `version` → print `$WTX_ROOT/VERSION` if present, else `0.1.0-dev`.
  - `help|--help|-h` and unknown command → usage on stdout/stderr respectively.

- **Sourcing-anchor fix (deferred from Phase 2 review):** every caller of
  `lib/wtx-config.sh` switches to `"$WTX_ROOT/lib/wtx-config.sh"`, with a
  self-resolve fallback so the scripts still work when invoked directly without the
  dispatcher:
  ```
  : "${WTX_ROOT:=$(cd "$SCRIPT_DIR/.." && pwd)}"
  ```
  Affected: `scripts/worktree-start.sh`, `scripts/worktree-done.sh`,
  `scripts/worktree-status.sh`, `scripts/builtin-worktree-enhance.sh`,
  `hooks/worktree-create.sh`.

- **Setup-hook anchor fix (deferred from Phase 2 review):** relative
  `worktree.setup_hook` values now resolve uniformly against `$WTX_ROOT` in
  `scripts/worktree-start.sh`, `scripts/builtin-worktree-enhance.sh`,
  `hooks/worktree-create.sh` — eliminating the `$WORKSPACE_ROOT` vs
  `dirname(SCRIPT_DIR)` divergence.

- **`WORKSPACE_ROOT` semantics:** stop computing it from `dirname(dirname(SCRIPT_DIR))`
  (a leftover from the Acme monorepo layout). Prefer env-var from dispatcher; fall
  back to `git rev-parse --show-toplevel`; finally to `$PWD`.

## Out of scope

- PR URL percent-encoding (deferred item #1) — unchanged, pre-existing.
- `setup_hook` path confinement / `realpath` jail (deferred item #5).
- Phase 4 installer and Phase 5 polish.
- Refactoring the `$SCRIPT_DIR/lib/worktree-tui.sh` (etc.) sourcing — broken but by
  design (inline stubs absorb the failure), not an anchor review finding.

## Files touched

- `bin/wtx` — full implementation (replaces 2-line stub).
- `scripts/worktree-start.sh` — WTX_ROOT/WORKSPACE_ROOT header, wtx-config anchor, setup_hook anchor.
- `scripts/worktree-done.sh` — same header + anchor update.
- `scripts/worktree-status.sh` — same header + anchor update.
- `scripts/builtin-worktree-enhance.sh` — same header + anchor update, setup_hook anchor.
- `hooks/worktree-create.sh` — same header + anchor update, setup_hook anchor.

## Tasks

- [x] bin/wtx: resolve WTX_ROOT via readlink loop, export env, add dispatcher `case`.
- [x] bin/wtx: `_wtx_doctor`, `_wtx_init`, `_wtx_version`, `_wtx_usage`.
- [x] scripts/worktree-start.sh: swap header block; swap setup_hook relative-path base.
- [x] scripts/worktree-done.sh: swap header block.
- [x] scripts/worktree-status.sh: swap header block.
- [x] scripts/builtin-worktree-enhance.sh: swap header block; swap setup_hook relative-path base.
- [x] hooks/worktree-create.sh: swap header block; swap setup_hook relative-path base.
- [x] `bash -n` sweep on every touched file.
- [x] `bash tests/test-wtx-config.sh` still 24/24.
- [x] `bin/wtx help`, `bin/wtx doctor`, `bin/wtx version` smoke-test.

## Acceptance

- Given `bin/wtx help`, when run, then prints usage and exits 0.
- Given `bin/wtx doctor`, when run in a clean env, then prints a green line for each
  present dep, red/warn for missing, and exits 0 if all required present.
- Given `bin/wtx version`, when no `VERSION` file exists, then prints `0.1.0-dev`.
- Given `bin/wtx start` (any subcommand), then `WTX_ROOT` and `WORKSPACE_ROOT` are
  exported and visible to the child script.
- Given `bash -n` on every `.sh` file in `bin/`, `scripts/`, `lib/`, `hooks/`, then
  exit 0 for each.
- Given `bash tests/test-wtx-config.sh`, then 24/24 pass.
