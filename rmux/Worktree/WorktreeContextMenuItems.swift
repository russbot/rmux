import SwiftUI

struct WorktreeContextMenuItems: View {
    let workspace: Workspace
    @EnvironmentObject var tabManager: TabManager

    var body: some View {
        if workspace.worktreeMetadata != nil {
            Divider()

            if hasRunScript {
                Button(String(localized: "contextMenu.worktree.runScript", defaultValue: "Run Script")) {
                    tabManager.runWorktreeScript(workspace)
                }
            }

            Button(String(localized: "contextMenu.worktree.remove", defaultValue: "Remove Worktree…")) {
                tabManager.removeWorktreeWorkspace(workspace)
            }
        }
    }

    private var hasRunScript: Bool {
        guard let metadata = workspace.worktreeMetadata else { return false }
        return ConductorConfig.load(repoRoot: metadata.rootRepoPath)?.scripts?.run != nil
    }
}
