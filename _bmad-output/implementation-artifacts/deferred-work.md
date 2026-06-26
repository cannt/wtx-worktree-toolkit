# Deferred Work

## Portability Overhaul — COMPLETE (2026-06-26)

All five phases of the portability overhaul are done:

- **Phase 1 — Config system.** `lib/wtx-config.sh` flat-TOML loader; `wtx.example.toml` schema.
- **Phase 2 — De-hardcode.** All Acme-specific literals replaced by config-driven lookups.
- **Phase 3 — Dispatcher.** `bin/wtx` subcommand router with `WTX_ROOT`/`WORKSPACE_ROOT` resolution.
- **Phase 4 — Installer.** `install.sh [--prefix|--uninstall|--hooks|--gradle]`.
- **Phase 5 — Polish.** README rewritten, MIT LICENSE added, all syntax checks and tests pass (61/61), Acme reproduction verified via `wtx.example.toml`.

Reference: `PORTABILITY_PROMPT.md` in repo root.

## From: Phase 2 adversarial review (2026-04-15)

- **PR URL percent-encoding.** `_wtx_build_pr_url` in `scripts/worktree-done.sh` does not URL-encode `$branch` / `$org` / `$repo`. Branches containing `#`, `&`, `?`, or spaces produce broken URLs. Pre-existing in the original hardcoded bitbucket URL; Phase 2 preserved the behavior verbatim. Fix when the PR builder is revisited (likely alongside Phase 3 `wtx doctor` or Phase 5 polish).
- **Inconsistent `wtx-config.sh` sourcing anchors.** Scripts source the loader via `$(dirname "$SCRIPT_DIR")/lib/wtx-config.sh`; `hooks/worktree-create.sh` via `$WORKSPACE_ROOT/lib/wtx-config.sh`. Both are best-effort guesses that break under symlinked installs, non-standard cwds, or hook invocations from subdirs. Blocked on Phase 3 dispatcher introducing a canonical `WTX_ROOT` env var — all scripts should switch to `"$WTX_ROOT/lib/wtx-config.sh"` at that time.
- **Inconsistent `SETUP_HOOK` relative-path resolution.** `worktree-start.sh` / `builtin-worktree-enhance.sh` resolve relative `worktree.setup_hook` against `dirname SCRIPT_DIR`; `hooks/worktree-create.sh` resolves against `$WORKSPACE_ROOT`. Same Phase 3 anchor fix applies — resolve everywhere against `$WTX_ROOT`.
- **Inline `detect_project` stubs when libs fail to source.** When `lib/wtx-config.sh` cannot be sourced (e.g. the Phase-3 path math is still wrong under certain layouts), the inline fallback walks up looking for `.git` alone. This can misidentify a parent dotfiles repo as the project. The by-design case (config + markers) is safe; this concerns only the degraded path. Phase 3 should make lib sourcing reliable and allow inline stubs to become truly empty.
- **No `setup_hook` path confinement.** A `wtx.toml` with `worktree.setup_hook = "../../etc/something"` is executed as-is. Low exploitability (self-owned config) but worth a `realpath`-prefix check once `WTX_ROOT` exists.
