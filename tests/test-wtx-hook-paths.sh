#!/bin/bash
# tests/test-wtx-hook-paths.sh — Hooks and builtin-worktree-* scripts must locate
# the toolkit from every layout they can be installed into.
#
# Regression guard. These scripts used to guess WTX_ROOT as "$SCRIPT_DIR/.." and
# never validate it, which silently resolved to a directory with no lib/ once the
# script was copied into a project's .claude/hooks/ (or vendored two levels deep).
# Nothing errored — the libs just failed to source and the registry update became
# a no-op stub. Assert the resolution instead of trusting it.
#
# Run: bash tests/test-wtx-hook-paths.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

FAILS=0
TOTAL=0

assert_eq() {
    local name="$1" expected="$2" actual="$3"
    TOTAL=$((TOTAL + 1))
    if [[ "$expected" == "$actual" ]]; then
        printf 'PASS  %s\n' "$name"
    else
        FAILS=$((FAILS + 1))
        printf 'FAIL  %s\n' "$name"
        printf '      expected: %s\n' "$expected"
        printf '      actual:   %s\n' "$actual"
    fi
}

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

# A fake `wtx` on PATH, symlinked at bin/wtx into the real checkout — this is how
# a real install looks, and it is the only anchor a copied hook has.
FAKEBIN="$TMPROOT/bin"
mkdir -p "$FAKEBIN"
ln -s "$REPO_ROOT/bin/wtx" "$FAKEBIN/wtx"

# Run a script's WTX_ROOT resolver in isolation and echo what it resolved to.
# Mirrors the block at the top of hooks/worktree-create.sh and the builtin scripts.
resolve_root_for() {
    local script="$1" with_wtx="${2:-yes}"
    # with_wtx=no drops the fake wtx from PATH entirely, so the PATH fallback has
    # nothing to find — that is the point of the degradation case.
    local path_env="$FAKEBIN:$PATH"
    [[ "$with_wtx" == "no" ]] && path_env="/usr/bin:/bin"
    env -u WTX_ROOT PATH="$path_env" bash -c '
        script="$1"
        _wtx_is_root() { [[ -n "${1:-}" ]] && [[ -f "$1/lib/wtx-config.sh" ]]; }
        _wtx_deref() {
            local p="$1" link
            while [[ -L "$p" ]]; do
                link="$(readlink "$p")"
                case "$link" in
                    /*) p="$link" ;;
                    *)  p="$(cd "$(dirname "$p")" && pwd)/$link" ;;
                esac
            done
            printf "%s" "$p"
        }
        WTX_ROOT=""
        _self="$(_wtx_deref "$script")"
        _dir="$(cd "$(dirname "$_self")" && pwd)"
        for c in "$_dir/.." "$_dir"; do
            if _wtx_is_root "$c"; then WTX_ROOT="$(cd "$c" && pwd)"; break; fi
        done
        if ! _wtx_is_root "${WTX_ROOT:-}" && command -v wtx >/dev/null 2>&1; then
            c="$(cd "$(dirname "$(_wtx_deref "$(command -v wtx)")")/.." 2>/dev/null && pwd)"
            _wtx_is_root "$c" && WTX_ROOT="$c"
        fi
        printf "%s" "${WTX_ROOT:-<unresolved>}"
    ' _ "$script"
}

# --- Layout 1: the wtx checkout itself (hooks/ and scripts/ are siblings of lib/)
assert_eq "layout: wtx checkout, hooks/worktree-create.sh" \
    "$REPO_ROOT" "$(resolve_root_for "$REPO_ROOT/hooks/worktree-create.sh")"
assert_eq "layout: wtx checkout, scripts/builtin-worktree-enhance.sh" \
    "$REPO_ROOT" "$(resolve_root_for "$REPO_ROOT/scripts/builtin-worktree-enhance.sh")"

# --- Layout 2: copied into a project's .claude/hooks/ — the toolkit is NOT nearby,
# so resolution must fall back to the `wtx` binary on PATH. This is the case that
# regressed silently before.
PROJ="$TMPROOT/proj/.claude/hooks"
mkdir -p "$PROJ"
cp "$REPO_ROOT/hooks/worktree-create.sh" "$PROJ/"
cp "$REPO_ROOT/scripts/builtin-worktree-post-exit.sh" "$PROJ/"
assert_eq "layout: .claude/hooks/ copy, worktree-create.sh (via PATH)" \
    "$REPO_ROOT" "$(resolve_root_for "$PROJ/worktree-create.sh")"
assert_eq "layout: .claude/hooks/ copy, builtin-worktree-post-exit.sh (via PATH)" \
    "$REPO_ROOT" "$(resolve_root_for "$PROJ/builtin-worktree-post-exit.sh")"

# --- Layout 3: a legacy vendored copy that ships its own lib/ — must prefer the
# local lib/ over the one on PATH, so existing vendored installs keep working.
VEND="$TMPROOT/vend/scripts/worktree"
mkdir -p "$VEND/lib"
cp "$REPO_ROOT/lib/wtx-config.sh" "$REPO_ROOT/lib/worktree-tui.sh" "$VEND/lib/"
cp "$REPO_ROOT/scripts/builtin-worktree-enhance.sh" "$VEND/"
assert_eq "layout: vendored copy prefers its own lib/" \
    "$VEND" "$(resolve_root_for "$VEND/builtin-worktree-enhance.sh")"

# --- No lib/ anywhere and no wtx on PATH: must degrade, not guess a bogus root.
ORPHAN="$TMPROOT/orphan/.claude/hooks"
mkdir -p "$ORPHAN"
cp "$REPO_ROOT/scripts/builtin-worktree-post-exit.sh" "$ORPHAN/"
assert_eq "no toolkit + no wtx on PATH: resolves to empty, not a bogus dir" \
    "<unresolved>" "$(resolve_root_for "$ORPHAN/builtin-worktree-post-exit.sh" no)"

# --- install.sh must ship the builtin hooks alongside the classic three.
for h in worktree-create.sh worktree-detect.sh worktree-remove.sh \
         builtin-worktree-cleanup.sh builtin-worktree-enhance.sh \
         builtin-worktree-post-exit.sh; do
    TOTAL=$((TOTAL + 1))
    if grep -qE "(hooks|scripts)/$h" "$REPO_ROOT/install.sh"; then
        printf 'PASS  install.sh --hooks installs %s\n' "$h"
    else
        FAILS=$((FAILS + 1))
        printf 'FAIL  install.sh --hooks installs %s\n' "$h"
    fi
done

printf '\n%d/%d passed\n' "$((TOTAL - FAILS))" "$TOTAL"
[[ $FAILS -eq 0 ]]
