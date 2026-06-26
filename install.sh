#!/usr/bin/env bash
# wtx installer — symlinks the `wtx` dispatcher onto your PATH.
#
# The wtx tree stays where it is (this checkout). We create a symlink
#   $prefix/bin/wtx  ->  <this-repo>/bin/wtx
# bin/wtx resolves WTX_ROOT back through the symlink (symlink-safe, no
# `readlink -f`), so upgrading is just `git pull` in this directory.
#
# Usage:
#   ./install.sh [--prefix PATH] [--hooks] [--gradle] [--force] [--dry-run]
#   ./install.sh --uninstall [--prefix PATH] [--dry-run]
#
# Options:
#   --prefix PATH   Install prefix; the symlink is created at $prefix/bin/wtx
#                   (default: $HOME/.local)
#   --hooks         Also copy Claude Code hooks into $PWD/.claude/hooks/
#   --gradle        Also copy the Gradle worktree-cache init script to
#                   ~/.gradle/init.d/
#   --uninstall     Remove the wtx symlink and print remaining cleanup steps
#   --force         Overwrite a non-symlink file already at the target path
#   --dry-run       Print what would happen without making any changes
#   -h, --help      Show this help
#
# ERROR HANDLING: graceful — `set -u` only, never `set -e`. Optional tooling
# (git) is detected at call sites. Side-effecting operations are checked and
# surfaced; the installer reports failures rather than silently "succeeding".

set -u

# --- WTX_ROOT resolution (symlink-safe, no readlink -f) -----------------------
# install.sh lives at the repo root, so its own directory *is* WTX_ROOT.
_self="${BASH_SOURCE[0]}"
while [[ -L "$_self" ]]; do
    _link="$(readlink "$_self")"
    case "$_link" in
        /*) _self="$_link" ;;
        *)  _self="$(cd "$(dirname "$_self")" && pwd)/$_link" ;;
    esac
done
WTX_ROOT="$(cd "$(dirname "$_self")" && pwd)"
unset _self _link

# --- Output helpers -----------------------------------------------------------
log()  { printf '%s\n' "$*"; }
info() { printf '  %s\n' "$*"; }
err()  { printf 'install.sh: %s\n' "$*" >&2; }

usage() {
    cat <<EOF
wtx installer — symlink the wtx dispatcher onto your PATH

USAGE:
  ./install.sh [--prefix PATH] [--hooks] [--gradle] [--force] [--dry-run]
  ./install.sh --uninstall [--prefix PATH] [--dry-run]

OPTIONS:
  --prefix PATH   Install prefix; symlink is created at \$prefix/bin/wtx
                  (default: \$HOME/.local)
  --hooks         Also copy Claude Code hooks into \$PWD/.claude/hooks/
  --gradle        Also copy the Gradle worktree-cache init script to
                  ~/.gradle/init.d/
  --uninstall     Remove the wtx symlink and print remaining cleanup steps
  --force         Overwrite a non-symlink file already at the target path
  --dry-run       Print what would happen without making any changes
  -h, --help      Show this help
EOF
}

# Expand a leading ~ and make a path absolute without requiring it to exist.
_expand_path() {
    local p="$1"
    case "$p" in
        "~")   p="$HOME" ;;
        "~/"*) p="$HOME/${p#"~/"}" ;;
    esac
    case "$p" in
        /*) : ;;
        *)  p="$PWD/$p" ;;
    esac
    printf '%s' "$p"
}

# Best-guess shell startup file, for the PATH hint.
_shell_rc() {
    case "${SHELL##*/}" in
        zsh)  printf '%s' "$HOME/.zshrc" ;;
        bash)
            if [[ "$(uname)" = "Darwin" ]]; then
                printf '%s' "$HOME/.bash_profile"
            else
                printf '%s' "$HOME/.bashrc"
            fi ;;
        *)    printf '%s' "your shell startup file" ;;
    esac
}

# --- Install steps ------------------------------------------------------------

install_symlink() {
    log "Linking wtx dispatcher"
    local bindir="$PREFIX/bin"

    if [[ ! -d "$bindir" ]]; then
        if [[ $DRY_RUN -eq 1 ]]; then
            info "[dry-run] would create $bindir"
        elif mkdir -p "$bindir"; then
            info "created $bindir"
        else
            err "could not create $bindir"
            return 1
        fi
    fi

    if [[ -L "$LINK" ]]; then
        local cur; cur="$(readlink "$LINK")"
        if [[ "$cur" = "$SRC" ]]; then
            info "already linked: $LINK -> $SRC"
            return 0
        fi
        # An existing symlink at $prefix/bin/wtx is "the wtx command" — safe to
        # repoint. (Replacing a symlink never destroys real file content.)
        if [[ $DRY_RUN -eq 1 ]]; then
            info "[dry-run] would repoint existing symlink (was -> $cur)"
        elif rm -f "$LINK"; then
            info "repointing existing symlink (was -> $cur)"
        else
            err "could not remove existing symlink $LINK"
            return 1
        fi
    elif [[ -e "$LINK" ]]; then
        if [[ $FORCE -eq 1 ]]; then
            if [[ $DRY_RUN -eq 1 ]]; then
                info "[dry-run] would overwrite existing file $LINK (--force)"
            elif rm -f "$LINK"; then
                info "removed existing file $LINK (--force)"
            else
                err "could not remove existing file $LINK"
                return 1
            fi
        else
            err "$LINK already exists and is not a symlink."
            err "  use --force to overwrite it, or choose a different --prefix."
            return 1
        fi
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        info "[dry-run] would symlink $LINK -> $SRC"
    elif ln -s "$SRC" "$LINK"; then
        info "linked $LINK -> $SRC"
    else
        err "failed to create symlink $LINK"
        return 1
    fi
    return 0
}

install_hooks() {
    local destdir="$PWD/.claude/hooks"
    local h hooks=(worktree-create.sh worktree-detect.sh worktree-remove.sh)
    local rc=0

    log
    log "Installing Claude Code hooks -> $destdir"
    if ! git -C "$PWD" rev-parse --git-dir >/dev/null 2>&1; then
        info "note: $PWD is not a git repo; copying hooks here anyway"
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        info "[dry-run] would create $destdir"
    elif ! mkdir -p "$destdir"; then
        err "could not create $destdir"
        return 1
    fi

    for h in "${hooks[@]}"; do
        local src="$WTX_ROOT/hooks/$h"
        if [[ ! -f "$src" ]]; then
            info "skip (missing in checkout): hooks/$h"
            continue
        fi
        if [[ $DRY_RUN -eq 1 ]]; then
            info "[dry-run] would copy hooks/$h -> $destdir/$h"
        elif cp "$src" "$destdir/$h" && chmod +x "$destdir/$h"; then
            info "copied $h"
        else
            err "failed to copy hooks/$h"
            rc=1
        fi
    done
    return $rc
}

install_gradle() {
    local src="$WTX_ROOT/share/gradle/worktree-cache.init.gradle.kts"
    local destdir="$HOME/.gradle/init.d"
    local dest="$destdir/worktree-cache.init.gradle.kts"

    log
    log "Installing Gradle worktree-cache init script -> $dest"
    if [[ ! -f "$src" ]]; then
        err "source not found: $src"
        return 1
    fi
    if [[ $DRY_RUN -eq 1 ]]; then
        info "[dry-run] would create $destdir"
        info "[dry-run] would copy -> $dest"
        return 0
    fi
    if ! mkdir -p "$destdir"; then
        err "could not create $destdir"
        return 1
    fi
    if cp "$src" "$dest"; then
        info "copied worktree-cache.init.gradle.kts"
    else
        err "failed to copy Gradle init script"
        return 1
    fi
    return 0
}

do_uninstall() {
    log "wtx uninstall (prefix: $PREFIX)"
    log
    if [[ -L "$LINK" ]]; then
        local tgt; tgt="$(readlink "$LINK")"
        if [[ $DRY_RUN -eq 1 ]]; then
            info "[dry-run] would remove symlink $LINK -> $tgt"
        elif rm -f "$LINK"; then
            info "removed symlink $LINK (was -> $tgt)"
        else
            err "failed to remove $LINK"
            return 1
        fi
    elif [[ -e "$LINK" ]]; then
        info "leaving $LINK in place — it is not a symlink (not created by this installer)"
    else
        info "no symlink at $LINK (nothing to remove)"
    fi

    log
    log "Other items the installer may have created — remove manually if you used them:"
    info "- Claude Code hooks:  <your-repo>/.claude/hooks/worktree-*.sh   (--hooks)"
    info "- Gradle init script: $HOME/.gradle/init.d/worktree-cache.init.gradle.kts   (--gradle)"
    info "- This wtx checkout:  $WTX_ROOT"
    info "- Per-repo config:    wtx.toml files in your workspaces"
    return 0
}

print_checklist() {
    log
    log "Next steps:"
    case ":$PATH:" in
        *":$PREFIX/bin:"*)
            info "[ok] $PREFIX/bin is already on your PATH" ;;
        *)
            info "[action] add $PREFIX/bin to your PATH:"
            info "         echo 'export PATH=\"$PREFIX/bin:\$PATH\"' >> $(_shell_rc)"
            info "         then restart your shell (or source that file)" ;;
    esac

    if [[ $DRY_RUN -eq 1 ]]; then
        info "[verify] after a real install, run: wtx doctor"
        return 0
    fi

    # Verify via the freshly created symlink so it works even before PATH is set.
    if [[ -x "$LINK" ]]; then
        log
        log "Verifying install (wtx doctor):"
        log
        if ! "$LINK" doctor; then
            log
            info "wtx doctor reported issues above. The wtx symlink itself is installed;"
            info "resolve any [FAIL] items (e.g. install missing required tools)."
        fi
    else
        info "[verify] run: wtx doctor"
    fi
    return 0
}

# --- Argument parsing ---------------------------------------------------------

PREFIX="$HOME/.local"
DO_HOOKS=0
DO_GRADLE=0
DO_UNINSTALL=0
FORCE=0
DRY_RUN=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --prefix)
            [[ $# -ge 2 ]] || { err "--prefix requires a path argument"; exit 2; }
            PREFIX="$2"; shift 2 ;;
        --prefix=*) PREFIX="${1#--prefix=}"; shift ;;
        --hooks)     DO_HOOKS=1; shift ;;
        --gradle)    DO_GRADLE=1; shift ;;
        --uninstall) DO_UNINSTALL=1; shift ;;
        --force)     FORCE=1; shift ;;
        --dry-run)   DRY_RUN=1; shift ;;
        -h|--help)   usage; exit 0 ;;
        *)           err "unknown option: $1"; echo >&2; usage >&2; exit 2 ;;
    esac
done

PREFIX="$(_expand_path "$PREFIX")"
LINK="$PREFIX/bin/wtx"
SRC="$WTX_ROOT/bin/wtx"

# --- Validate the source checkout --------------------------------------------
if [[ ! -f "$SRC" ]]; then
    err "cannot find bin/wtx at $SRC"
    err "  run install.sh from inside the wtx checkout."
    exit 1
fi
if [[ ! -f "$WTX_ROOT/lib/wtx-config.sh" ]]; then
    err "this does not look like a complete wtx checkout (missing lib/wtx-config.sh)."
    exit 1
fi

# --- Dispatch -----------------------------------------------------------------
if [[ $DO_UNINSTALL -eq 1 ]]; then
    if [[ $DO_HOOKS -eq 1 || $DO_GRADLE -eq 1 ]]; then
        info "note: --hooks/--gradle are ignored with --uninstall; see cleanup notes below"
        log
    fi
    do_uninstall
    exit $?
fi

log "wtx installer"
info "source : $WTX_ROOT"
info "prefix : $PREFIX"
[[ $DRY_RUN -eq 1 ]] && info "mode   : dry-run (no changes will be made)"
log

rc=0
install_symlink || rc=1
[[ $DO_HOOKS  -eq 1 ]] && { install_hooks  || rc=1; }
[[ $DO_GRADLE -eq 1 ]] && { install_gradle || rc=1; }

if [[ $rc -ne 0 ]]; then
    log
    err "installation completed with errors (see above)."
    exit 1
fi

print_checklist
exit 0
