# rmux

Personal fork of [manaflow-ai/cmux](https://github.com/manaflow-ai/cmux) at `russbot/rmux`.

This directory contains all fork-specific code, keeping it separate from upstream `Sources/` so rebases stay clean.

## Repository layout

```
rmux/
  README.md                  # this file
  WORKTREE_STATUS.md         # feature status and design decisions
  Worktree/                  # Swift source files for git worktree integration
    ConductorConfig.swift
    GitWorktreeService.swift
    SidebarWorktreeButton.swift
    TabManager+Worktree.swift
    Workspace+Worktree.swift
    WorktreeContextMenuItems.swift
    WorktreeEnvironment.swift
    WorktreeMetadata.swift
    WorktreePickerView.swift
    WorktreePortAllocator.swift
```

## Remotes

```
origin    https://github.com/russbot/rmux.git
upstream  https://github.com/manaflow-ai/cmux.git
```

## Rebasing from upstream

```bash
git fetch upstream
git checkout main
git reset --hard upstream/main
git checkout russbot/rmux
git rebase main
```

After rebase, the Xcode project file (`project.pbxproj`) will lose the worktree file references because it was reset to upstream's version. Follow the patching instructions below to re-add them.

## Patching project.pbxproj after rebase

The upstream `project.pbxproj` has no knowledge of the `rmux/Worktree/` files. After every rebase that resets `project.pbxproj` to upstream, the worktree entries need to be re-added.

### Finding the current entries

The worktree entries in `project.pbxproj` all share a common ID prefix. To extract them from an existing working copy:

```bash
grep -i 'worktree\|ConductorConfig' GhosttyTabs.xcodeproj/project.pbxproj
```

This will show all lines with their full Xcode-generated UUIDs. The entries fall into 5 sections described below.

If the entries are missing entirely (clean upstream pbxproj after rebase), the easiest approach is:
1. Open the project in Xcode
2. Drag the `rmux/Worktree` folder into the Sources group (uncheck "Copy items if needed")
3. Xcode generates fresh UUIDs — commit the result

### What the entries look like

The pbxproj needs worktree references in 5 sections. The file names are stable; only the hex UUIDs change if Xcode re-adds the files. Below is the structure using placeholder `{PREFIX}` — replace with the actual UUIDs from your copy.

**1. PBXBuildFile section** — one entry per source file, maps a file reference to a build target:

```
{UUID} /* <FileName>.swift in Sources */ = {isa = PBXBuildFile; fileRef = {FILE_REF_UUID} /* <FileName>.swift */; };
```

There should be 10 entries (one per `.swift` file in `rmux/Worktree/`).

**2. PBXFileReference section** — declares each file's path and type:

```
{UUID} /* <FileName>.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = <FileName>.swift; sourceTree = "<group>"; };
```

Files with `+` in the name (e.g. `TabManager+Worktree.swift`) have the path quoted.

**3. PBXGroup (Worktree group)** — defines the folder group and lists its children:

```
{UUID} /* Worktree */ = {
    isa = PBXGroup;
    children = (
        {FILE_REF_UUID} /* ConductorConfig.swift */,
        {FILE_REF_UUID} /* GitWorktreeService.swift */,
        ... (all 10 files)
    );
    name = Worktree;
    path = rmux/Worktree;
    sourceTree = "<group>";
};
```

**4. PBXGroup (Sources children)** — the Worktree group UUID must appear in the `A5001041 /* Sources */` group's children list:

```
{WORKTREE_GROUP_UUID} /* Worktree */,
```

**5. PBXSourcesBuildPhase** — the build file UUIDs must appear in the main target's (`A5001051`) source file list:

```
{BUILD_FILE_UUID} /* <FileName>.swift in Sources */,
```

### Quick verification

After patching, confirm all 10 files are present:

```bash
grep -c -i 'worktree\|ConductorConfig' GhosttyTabs.xcodeproj/project.pbxproj
```

Expected: ~40 lines (10 files x 4 references each: build file, file ref, group child, source phase).

## Upstream source file edits

These are small diffs to upstream files that enable worktree integration. They may need manual conflict resolution after rebase.

**Sources/Workspace.swift** — adds `additionalEnvironment` param and `worktreeMetadata` session persistence:
- `init()`: add `additionalEnvironment: [String: String] = [:]` parameter, pass to TerminalPanel
- `snapshot()`: add `worktreeMetadata: worktreeMetadata` to SessionWorkspaceSnapshot
- `restore(from:)`: add `worktreeMetadata = snapshot.worktreeMetadata`

**Sources/TabManager.swift** — adds `additionalEnvironment` param:
- `addWorkspace()`: add `additionalEnvironment: [String: String] = [:]` parameter, pass to Workspace init

**Sources/ContentView.swift** — adds worktree UI hooks:
- `SidebarFooterButtons`: add `Spacer()` + `SidebarWorktreeButton()` after `UpdatePill`
- `TabItemView` context menu: add `WorktreeContextMenuItems(workspace: tab)` before the close divider

**Sources/SessionPersistence.swift** — adds worktree metadata to session snapshot:
- `SessionWorkspaceSnapshot`: add `var worktreeMetadata: WorktreeMetadata?`

## Fork conventions

- **No localization** — use hardcoded strings in all fork code. Do not modify xcstrings files.
- **Fork code lives in `rmux/`** — keep `Sources/` changes minimal for clean rebases.
- **Xcode project IDs change on relink** — if files are re-added via Xcode, UUIDs change. The structure and file names are stable; see patching instructions above.
