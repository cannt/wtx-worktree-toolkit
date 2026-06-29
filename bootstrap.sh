#!/usr/bin/env bash
# wtx bootstrap — one-command install from anywhere.
#
#   curl -fsSL https://raw.githubusercontent.com/cannt/wtx-worktree-toolkit/main/bootstrap.sh | bash
#
# What it does (idempotent — safe to re-run, which is how you update):
#   1. Clones the wtx toolkit into a stable home ($WTX_HOME), or updates it in
#      place if already present.
#   2. Runs the toolkit's install.sh to symlink `wtx` onto your PATH.
#   3. If you ran it inside a git repo (and a terminal is attached), offers to
#      run the per-project `wtx install` wizard; otherwise prints the command.
#
# Everything is configurable via environment variables or flags so it also
# works against a private repo (SSH clone) or a fork.
#
# Environment:
#   WTX_HOME      where to clone the toolkit   (default: ${XDG_DATA_HOME:-$HOME/.local/share}/wtx)
#   WTX_REPO_URL  git URL to clone             (default: https://github.com/cannt/wtx-worktree-toolkit.git)
#   WTX_REF       branch/tag to check out      (default: main)
#   WTX_PREFIX    install prefix for the link  (default: $HOME/.local)
#
# Flags (also accepted via `bash -s -- <flags>` when piping from curl):
#   --home PATH      override WTX_HOME
#   --repo URL       override WTX_REPO_URL
#   --ref REF        override WTX_REF
#   --prefix PATH    override WTX_PREFIX
#   --no-project     skip the per-project `wtx install` wizard
#   --uninstall      remove an existing install (delegates to `wtx uninstall`)
#   --dry-run        print what would happen; make no changes
#   -h, --help       show this help
#
# ERROR HANDLING: graceful — `set -u` only, never `set -e`. Required tools
# (git, curl) are checked up front with a clear message.

set -u

WTX_HOME="${WTX_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/wtx}"
WTX_REPO_URL="${WTX_REPO_URL:-https://github.com/cannt/wtx-worktree-toolkit.git}"
WTX_REF="${WTX_REF:-main}"
WTX_PREFIX="${WTX_PREFIX:-$HOME/.local}"
NO_PROJECT=0
DRY_RUN=0
DO_UNINSTALL=0

log()  { printf '%s\n' "$*"; }
info() { printf '  %s\n' "$*"; }
err()  { printf 'bootstrap: %s\n' "$*" >&2; }

usage() {
    sed -n '2,/^set -u$/p' "$0" 2>/dev/null | sed 's/^# \{0,1\}//; s/^#$//' | sed '$d'
}

# When piped through `curl ... | bash`, $0 is "bash" and the comment block above
# is unavailable, so fall back to a compact inline help.
usage_fallback() {
    cat <<'EOF'
wtx bootstrap — one-command install from anywhere

USAGE:
  curl -fsSL <url>/bootstrap.sh | bash
  curl -fsSL <url>/bootstrap.sh | bash -s -- [flags]
  bash bootstrap.sh [flags]

FLAGS:
  --home PATH    where to clone the toolkit (default: ~/.local/share/wtx)
  --repo URL     git URL to clone
  --ref REF      branch/tag to check out (default: main)
  --prefix PATH  install prefix for the wtx symlink (default: ~/.local)
  --no-project   skip the per-project `wtx install` wizard
  --dry-run      print what would happen; make no changes
  -h, --help     show this help

ENVIRONMENT: WTX_HOME, WTX_REPO_URL, WTX_REF, WTX_PREFIX
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --home)    [[ $# -ge 2 ]] || { err "--home requires a path"; exit 2; };   WTX_HOME="$2"; shift 2 ;;
        --home=*)   WTX_HOME="${1#--home=}"; shift ;;
        --repo)    [[ $# -ge 2 ]] || { err "--repo requires a URL"; exit 2; };    WTX_REPO_URL="$2"; shift 2 ;;
        --repo=*)   WTX_REPO_URL="${1#--repo=}"; shift ;;
        --ref)     [[ $# -ge 2 ]] || { err "--ref requires a value"; exit 2; };   WTX_REF="$2"; shift 2 ;;
        --ref=*)    WTX_REF="${1#--ref=}"; shift ;;
        --prefix)  [[ $# -ge 2 ]] || { err "--prefix requires a path"; exit 2; }; WTX_PREFIX="$2"; shift 2 ;;
        --prefix=*) WTX_PREFIX="${1#--prefix=}"; shift ;;
        --no-project) NO_PROJECT=1; shift ;;
        --uninstall)  DO_UNINSTALL=1; shift ;;
        --dry-run)    DRY_RUN=1; shift ;;
        -h|--help)    usage_fallback; exit 0 ;;
        *) err "unknown option: $1"; echo >&2; usage_fallback >&2; exit 2 ;;
    esac
done

run() {
    if [[ $DRY_RUN -eq 1 ]]; then
        info "[dry-run] $*"
        return 0
    fi
    "$@"
}

# --- Preflight ----------------------------------------------------------------
missing=""
command -v git  >/dev/null 2>&1 || missing="${missing:+$missing, }git"
command -v curl >/dev/null 2>&1 || missing="${missing:+$missing, }curl"
if [[ -n "$missing" ]]; then
    err "missing required tool(s): $missing"
    err "install them and re-run."
    exit 1
fi

# --- Uninstall path -----------------------------------------------------------
if [[ $DO_UNINSTALL -eq 1 ]]; then
    if [[ -x "$WTX_HOME/bin/wtx" ]]; then
        log "wtx uninstall (toolkit at $WTX_HOME)"
        log
        if [[ $DRY_RUN -eq 1 ]]; then
            "$WTX_HOME/bin/wtx" uninstall --dry-run
        else
            "$WTX_HOME/bin/wtx" uninstall
        fi
        exit $?
    fi
    err "no wtx install found at $WTX_HOME (nothing to uninstall)"
    err "  pass --home if you installed somewhere else."
    exit 1
fi

log "wtx bootstrap"
info "home   : $WTX_HOME"
info "repo   : $WTX_REPO_URL"
info "ref    : $WTX_REF"
info "prefix : $WTX_PREFIX"
[[ $DRY_RUN -eq 1 ]] && info "mode   : dry-run (no changes will be made)"
log

# --- Step 1: clone or update the toolkit --------------------------------------
if [[ -e "$WTX_HOME/.git" ]]; then
    # Already a clone — verify it is wtx, then update in place.
    if [[ ! -f "$WTX_HOME/bin/wtx" ]]; then
        err "$WTX_HOME exists and is a git repo but does not look like wtx."
        err "  move it aside or pass --home with a different path."
        exit 1
    fi
    log "Updating existing toolkit at $WTX_HOME"
    if [[ -n "$(git -C "$WTX_HOME" status --porcelain 2>/dev/null)" ]]; then
        info "local changes present — skipping update (commit/stash to update)"
    else
        run git -C "$WTX_HOME" pull --ff-only || { err "git pull failed"; exit 1; }
    fi
elif [[ -e "$WTX_HOME" ]]; then
    err "$WTX_HOME already exists and is not a wtx checkout — refusing to overwrite."
    err "  remove it or pass --home with a different path."
    exit 1
else
    log "Cloning wtx toolkit -> $WTX_HOME"
    run mkdir -p "$(dirname "$WTX_HOME")" || { err "could not create parent of $WTX_HOME"; exit 1; }
    run git clone --depth 1 --branch "$WTX_REF" "$WTX_REPO_URL" "$WTX_HOME" \
        || { err "git clone failed (check --repo / access to $WTX_REPO_URL)"; exit 1; }
fi

# --- Step 2: symlink the binary -----------------------------------------------
log
log "Linking the wtx dispatcher onto your PATH"
if [[ $DRY_RUN -eq 1 ]]; then
    info "[dry-run] would run: bash $WTX_HOME/install.sh --prefix $WTX_PREFIX"
else
    bash "$WTX_HOME/install.sh" --prefix "$WTX_PREFIX" || { err "install.sh failed"; exit 1; }
fi

# --- Step 3: optional per-project wizard --------------------------------------
WTX_BIN="$WTX_HOME/bin/wtx"
log
if [[ $NO_PROJECT -eq 1 ]]; then
    info "skipping per-project setup (--no-project)"
elif ! git rev-parse --git-dir >/dev/null 2>&1; then
    info "not inside a git repo — skip per-project setup."
    info "cd into a project and run:  $WTX_BIN install"
elif [[ ! -r /dev/tty ]]; then
    info "no terminal attached — skip the interactive wizard."
    info "in your project, run:  $WTX_BIN install"
elif [[ $DRY_RUN -eq 1 ]]; then
    info "[dry-run] would run per-project wizard: $WTX_BIN install"
else
    log "Running per-project setup: wtx install"
    "$WTX_BIN" install < /dev/tty || info "wizard exited non-zero — you can re-run: $WTX_BIN install"
fi

log
log "Done. Next steps:"
case ":$PATH:" in
    *":$WTX_PREFIX/bin:"*) info "[ok] $WTX_PREFIX/bin is already on your PATH" ;;
    *) info "[action] add to your PATH:  export PATH=\"$WTX_PREFIX/bin:\$PATH\"" ;;
esac
info "verify with:  wtx doctor"
exit 0
