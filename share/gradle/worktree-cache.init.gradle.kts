// Worktree Build Cache Init Script
// Enables local build cache isolation for git worktrees.
//
// In worktrees, .git is a FILE (pointing to the main repo's .git/worktrees/<name>).
// In main repos, .git is a DIRECTORY.
// This script enables local build cache with an isolated directory ONLY in worktrees.
//
// This runs AFTER settings.gradle, so it can override project-level local cache settings.
// The remote cache (e.g., S3 via burrunan plugin) is NOT touched — only the local slot.
//
// Location: ~/.gradle/init.d/worktree-cache.init.gradle.kts

settingsEvaluated {
    val gitFile = File(rootDir, ".git")
    val isWorktree = gitFile.isFile

    if (isWorktree) {
        buildCache {
            local {
                isEnabled = true
                directory = File(rootDir, ".build-cache")
            }
        }
    }
}
