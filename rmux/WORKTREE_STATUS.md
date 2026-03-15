# Git Worktree Feature — Status

## Completed

### New Files (rmux/Worktree/)
10 Swift source files implementing git worktree integration:

- **GitWorktreeService.swift** — Static service wrapping git commands (`listWorktrees`, `localBranches`, `createWorktree`, `removeWorktree`, `repoRoot`, `defaultBranch`, `defaultWorktreePath`, `branchSlug`). Uses `Foundation.Process`.
- **ConductorConfig.swift** — Reads `conductor.json` from repo root. Has `scripts.setup`, `scripts.run`, `scripts.archive`.
- **WorktreeMetadata.swift** — Codable struct: `rootRepoPath`, `worktreePath`, `branchName`, `workspaceName`.
- **WorktreePortAllocator.swift** — In-memory port registry, 10-port blocks per workspace. Singleton.
- **WorktreeEnvironment.swift** — Builds env var dict (CMUX_* + CONDUCTOR_*) from metadata.
- **Workspace+Worktree.swift** — Extension adding `worktreeMetadata` via static dictionary (avoids modifying Workspace.swift init).
- **TabManager+Worktree.swift** — Extension with `addWorktreeWorkspace`, `removeWorktreeWorkspace`, `runWorktreeScript`, `runScriptInWorktreeTerminal`.
- **WorktreePickerView.swift** — SwiftUI popover: lists existing worktrees, native Picker for base branch (local branches only), text field for new branch name.
- **SidebarWorktreeButton.swift** — Branch icon button in sidebar footer, opens WorktreePickerView popover.
- **WorktreeContextMenuItems.swift** — Context menu items for worktree workspaces: "Run Script" and "Remove Worktree...".

### Upstream File Edits (minimal, rebase-friendly)
- **Workspace.swift** — Added `additionalEnvironment` param to `init()`, passed to TerminalPanel, save/restore `worktreeMetadata` in session snapshot.
- **TabManager.swift** — Added `additionalEnvironment` param to `addWorkspace()`, passed to Workspace.
- **ContentView.swift** — Added `SidebarWorktreeButton()` to sidebar footer, `WorktreeContextMenuItems` to context menu.
- **SessionPersistence.swift** — Added `worktreeMetadata: WorktreeMetadata?` to `SessionWorkspaceSnapshot`.

## Design Decisions

- **Local branches only** in picker — repos can have thousands of remote branches, making SwiftUI Picker unusably slow.
- **Base branch auto-selects** current tab's git branch, falls back to main/master.
- **Tab name** comes from the worktree folder name (derived from `branchSlug`), not a custom title.
- **Scripts spawn a new terminal tab** with env vars injected — because restored sessions don't have env vars in existing shells.
- **`Workspace+Worktree.swift`** uses a static dictionary keyed by workspace UUID — avoids modifying `Workspace.swift` init.
- **Hardcoded strings** — this fork skips localization. No xcstrings entries needed.

## Not Yet Implemented

- **Socket API** — Add `worktree.list`, `worktree.create`, `worktree.remove` V2 commands to enable scriptable worktree management from CLI/scripts. Implementation lives in `Sources/TerminalController.swift` — the V2 dispatcher is a big switch on method name (around line 1850+), handlers return `V2CallResult`, and new methods must be registered in `v2Capabilities()` (around line 2260). Follow the pattern of existing `workspace.*` commands. Handlers would call `GitWorktreeService` and `TabManager+Worktree` methods. Low priority — only needed if interactive UI picker isn't sufficient.
- `runScriptMode: "nonconcurrent"` — process management for killing in-progress run scripts
- Command palette integration
- Branch name validation in create flow
