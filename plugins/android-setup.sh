#!/bin/bash
# Android Worktree Setup Script
# Configures a newly created worktree with Android-specific files and directories.
# Called by worktree-start.sh and worktree-create.sh after git worktree add.
#
# Usage: ./plugins/android-setup.sh <worktree-path> <source-project-path>
#
# ERROR HANDLING: No set -e. Each operation has its own check. Script prints
# warnings but continues — a missing local.properties should not block worktree use.

WORKTREE_PATH="$1"
SOURCE_PROJECT="$2"

if [[ -z "$WORKTREE_PATH" ]] || [[ -z "$SOURCE_PROJECT" ]]; then
    echo "Usage: $0 <worktree-path> <source-project-path>" >&2
    exit 1
fi

if [[ ! -d "$WORKTREE_PATH" ]]; then
    echo "Error: Worktree path does not exist: $WORKTREE_PATH" >&2
    exit 1
fi

if [[ ! -d "$SOURCE_PROJECT" ]]; then
    echo "Error: Source project path does not exist: $SOURCE_PROJECT" >&2
    exit 1
fi

# Resolve workspace root: walk up from script location to find .worktreeinclude.
# bin/wtx exports WORKSPACE_ROOT, so prefer it over guessing from SCRIPT_DIR —
# the guess only holds when the toolkit sits one level below the workspace.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_ROOT="${CLAUDE_PROJECT_ROOT:-${WORKSPACE_ROOT:-$(dirname "$(dirname "$SCRIPT_DIR")")}}"

# Config is optional here: this plugin runs standalone in tests and from layouts
# where the toolkit isn't nearby, so validate the root before sourcing and fall
# back to built-in defaults when the loader is unavailable.
_ANDROID_WTX_ROOT=""
if [[ -n "${WTX_ROOT:-}" ]] && [[ -f "$WTX_ROOT/lib/wtx-config.sh" ]]; then
    _ANDROID_WTX_ROOT="$WTX_ROOT"
elif [[ -f "$(dirname "$SCRIPT_DIR")/lib/wtx-config.sh" ]]; then
    _ANDROID_WTX_ROOT="$(dirname "$SCRIPT_DIR")"
fi
if [[ -n "$_ANDROID_WTX_ROOT" ]]; then
    # shellcheck source=../lib/wtx-config.sh disable=SC1091
    source "$_ANDROID_WTX_ROOT/lib/wtx-config.sh" 2>/dev/null || true
fi

INCLUDE_FILE="$WORKSPACE_ROOT/.worktreeinclude"

# Copy files listed in .worktreeinclude
if [[ -f "$INCLUDE_FILE" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip comments and empty lines
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^# ]] && continue

        # Trim whitespace and strip carriage return
        line="$(echo "$line" | xargs)"
        line="${line%$'\r'}"

        # Block path traversal
        if [[ "$line" == *".."* ]]; then
            echo "  Warning: Skipping path with '..': $line" >&2
            continue
        fi

        SOURCE_FILE="$SOURCE_PROJECT/$line"
        DEST_FILE="$WORKTREE_PATH/$line"

        if [[ -f "$SOURCE_FILE" ]]; then
            # Create parent directory if needed
            DEST_DIR="$(dirname "$DEST_FILE")"
            mkdir -p "$DEST_DIR" 2>/dev/null

            cp "$SOURCE_FILE" "$DEST_FILE" 2>/dev/null
            if [[ $? -eq 0 ]]; then
                echo "  Copied: $line" >/dev/tty 2>/dev/null || true
            else
                echo "  Warning: Failed to copy $line" >&2
            fi
        else
            echo "  Warning: Source file not found, skipping: $line" >&2
        fi
    done < "$INCLUDE_FILE"
else
    echo "  Warning: .worktreeinclude not found at $INCLUDE_FILE" >&2
fi

# Create .build-cache directory
mkdir -p "$WORKTREE_PATH/.build-cache" 2>/dev/null
if [[ $? -eq 0 ]]; then
    echo "  Created: .build-cache/" >/dev/tty 2>/dev/null || true
else
    echo "  Warning: Could not create .build-cache directory" >&2
fi

# Verify ANDROID_HOME or sdk.dir
SDK_OK=false
if [[ -n "$ANDROID_HOME" ]]; then
    SDK_OK=true
elif [[ -f "$WORKTREE_PATH/local.properties" ]]; then
    if grep -q "sdk.dir" "$WORKTREE_PATH/local.properties" 2>/dev/null; then
        SDK_OK=true
    fi
fi

if [[ "$SDK_OK" != "true" ]]; then
    echo "  Warning: Neither ANDROID_HOME nor sdk.dir in local.properties is set" >&2
fi

# Pin the Gradle JDK.
# Android Studio defaults a fresh worktree's gradleJvm to its bundled JBR, which may
# be newer than the project's Gradle supports (Gradle 8.14 tops out at Java 24), so
# sync fails on first open. Neither .idea/ nor .gradle/ is tracked, so this must be
# re-seeded per worktree.
GRADLE_JDK_VERSION="17"
if command -v wtx_config_get >/dev/null 2>&1; then
    GRADLE_JDK_VERSION="$(wtx_config_get "android.gradle_jdk_version" "17")"
fi

# Major version of the JDK at $1, e.g. "17". Empty if it can't be determined.
_jdk_major_version() {
    local java_bin="$1/bin/java"
    [[ -x "$java_bin" ]] || return 0
    # `java -version` writes to stderr: openjdk version "17.0.14" 2025-01-21
    "$java_bin" -version 2>&1 | head -1 | sed -n 's/.*version "\([0-9][0-9]*\).*/\1/p'
}

# Echo $1 back only if it is a JDK of the requested major version.
# Every candidate goes through this, because both sources can hand back the wrong
# JDK: `java_home -v N` treats N as a *minimum* (with no JDK N installed it returns
# the newest one, even for -v 99, and exits 0), and the source project's java.home
# is whatever Android Studio last wrote there — which is its bundled JBR once
# someone opens the main repo in the IDE. Pinning either would reintroduce the
# too-new JVM this hook exists to prevent.
_accept_jdk() {
    local candidate="$1" origin="$2" major
    [[ -n "$candidate" ]] || return 1
    if [[ ! -x "$candidate/bin/java" ]]; then
        echo "  Warning: $origin points at $candidate, which has no runnable java — ignoring" >&2
        return 1
    fi
    major="$(_jdk_major_version "$candidate")"
    if [[ "$major" != "$GRADLE_JDK_VERSION" ]]; then
        echo "  Warning: $origin resolved to JDK ${major:-unknown}, wanted $GRADLE_JDK_VERSION — ignoring" >&2
        return 1
    fi
    printf '%s\n' "$candidate"
}

GRADLE_CONFIG="$WORKTREE_PATH/.gradle/config.properties"
if [[ -f "$GRADLE_CONFIG" ]]; then
    echo "  Skipped: .gradle/config.properties already exists" >/dev/tty 2>/dev/null || true
else
    # Prefer whatever the source project already resolved to; else find a matching JDK.
    JAVA_HOME_PATH=""
    SOURCE_JAVA_HOME="$(grep -m1 '^java.home=' "$SOURCE_PROJECT/.gradle/config.properties" 2>/dev/null | cut -d= -f2-)"
    if [[ -n "$SOURCE_JAVA_HOME" ]]; then
        JAVA_HOME_PATH="$(_accept_jdk "$SOURCE_JAVA_HOME" "source project java.home")"
    fi
    if [[ -z "$JAVA_HOME_PATH" ]] && [[ -x /usr/libexec/java_home ]]; then
        JAVA_HOME_PATH="$(_accept_jdk "$(/usr/libexec/java_home -v "$GRADLE_JDK_VERSION" 2>/dev/null)" "java_home -v $GRADLE_JDK_VERSION")"
    fi

    if [[ -n "$JAVA_HOME_PATH" ]]; then
        mkdir -p "$WORKTREE_PATH/.gradle" 2>/dev/null
        printf '#%s\njava.home=%s\n' "$(date '+%a %b %d %H:%M:%S %Z %Y')" "$JAVA_HOME_PATH" > "$GRADLE_CONFIG" 2>/dev/null
        if [[ $? -eq 0 ]]; then
            echo "  Created: .gradle/config.properties (java.home=$JAVA_HOME_PATH)" >/dev/tty 2>/dev/null || true
        else
            echo "  Warning: Failed to write $GRADLE_CONFIG" >&2
        fi
    else
        echo "  Warning: No JDK $GRADLE_JDK_VERSION found — Android Studio may pick an incompatible Gradle JVM" >&2
    fi
fi

# Point gradle.xml at that JDK, but never clobber an existing Studio config.
GRADLE_XML="$WORKTREE_PATH/.idea/gradle.xml"
if [[ -f "$GRADLE_XML" ]]; then
    echo "  Skipped: .idea/gradle.xml already exists" >/dev/tty 2>/dev/null || true
elif [[ -f "$GRADLE_CONFIG" ]]; then
    mkdir -p "$WORKTREE_PATH/.idea" 2>/dev/null
    cat > "$GRADLE_XML" 2>/dev/null <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<project version="4">
  <component name="GradleSettings">
    <option name="linkedExternalProjectsSettings">
      <GradleProjectSettings>
        <option name="testRunner" value="CHOOSE_PER_TEST" />
        <option name="externalProjectPath" value="$PROJECT_DIR$" />
        <option name="gradleJvm" value="#GRADLE_LOCAL_JAVA_HOME" />
      </GradleProjectSettings>
    </option>
  </component>
</project>
EOF
    if [[ $? -eq 0 ]]; then
        echo "  Created: .idea/gradle.xml (gradleJvm=#GRADLE_LOCAL_JAVA_HOME)" >/dev/tty 2>/dev/null || true
    else
        echo "  Warning: Failed to write $GRADLE_XML" >&2
    fi
fi

# Add worktree entries to .git/info/exclude (local-only, not tracked)
# Worktrees share the main repo's .git, so we add to the source project's info/exclude.
# This covers both the main repo and all its worktrees.
EXCLUDE_FILE="$SOURCE_PROJECT/.git/info/exclude"
if [[ -f "$EXCLUDE_FILE" ]]; then
    if ! grep -q "\.build-cache/" "$EXCLUDE_FILE" 2>/dev/null; then
        printf "\n# Worktree artifacts\n.build-cache/\nWORKTREE_CONTEXT.md\n" >> "$EXCLUDE_FILE"
        echo "  Updated: .git/info/exclude" >/dev/tty 2>/dev/null || true
    fi
elif [[ -d "$SOURCE_PROJECT/.git/info" ]]; then
    printf "# Worktree artifacts\n.build-cache/\nWORKTREE_CONTEXT.md\n" >> "$EXCLUDE_FILE"
    echo "  Created: .git/info/exclude entries" >/dev/tty 2>/dev/null || true
else
    echo "  Warning: Could not find .git/info/exclude at $SOURCE_PROJECT" >&2
fi

echo "  Setup complete." >/dev/tty 2>/dev/null || true
