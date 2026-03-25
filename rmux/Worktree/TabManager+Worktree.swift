import Foundation

extension TabManager {

    /// Creates a new workspace backed by a git worktree.
    /// Allocates a port block, injects environment variables, and optionally runs the conductor setup script.
    @discardableResult
    func addWorktreeWorkspace(metadata: WorktreeMetadata, select: Bool = true) -> Workspace {
        // Pre-allocate a workspace ID so port allocation is keyed correctly from the start
        let workspaceId = UUID()
        let port = WorktreePortAllocator.shared.allocate(for: workspaceId)
        let defaultBranch = GitWorktreeService.defaultBranch(repoRoot: metadata.rootRepoPath)
        let env = WorktreeEnvironment.build(metadata: metadata, port: port, defaultBranch: defaultBranch)

        let workspace = addWorkspace(
            workingDirectory: metadata.worktreePath,
            select: select,
            additionalEnvironment: env
        )
        workspace.worktreeMetadata = metadata

        // Re-key the port allocation from our pre-allocated ID to the actual workspace ID
        if workspaceId != workspace.id {
            WorktreePortAllocator.shared.release(workspaceId: workspaceId)
            let _ = WorktreePortAllocator.shared.allocate(for: workspace.id)
        }

        // Run conductor setup script if present
        if let config = ConductorConfig.load(repoRoot: metadata.rootRepoPath),
           let setupScript = config.scripts?.setup {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak workspace] in
                workspace?.focusedTerminalPanel?.sendText("\(setupScript)\r")
            }
        }

        return workspace
    }

    /// Removes a worktree-backed workspace: runs archive script if present,
    /// then removes the git worktree and closes the workspace.
    func removeWorktreeWorkspace(_ workspace: Workspace, force: Bool = true) {
        guard let metadata = workspace.worktreeMetadata else {
            closeWorkspace(workspace)
            return
        }

        let workspaceId = workspace.id
        let rootRepo = metadata.rootRepoPath
        let worktreePath = metadata.worktreePath

        // Run archive script if present
        if let config = ConductorConfig.load(repoRoot: rootRepo),
           let archiveScript = config.scripts?.archive {
            runScriptInWorktreeTerminal(workspace: workspace, metadata: metadata, script: archiveScript)
        }

        // Remove worktree and close workspace
        DispatchQueue.global(qos: .userInitiated).async {
            let _ = GitWorktreeService.removeWorktree(repoRoot: rootRepo, path: worktreePath, force: force)
            WorktreePortAllocator.shared.release(workspaceId: workspaceId)
            Workspace.cleanupWorktreeMetadata(for: workspaceId)

            DispatchQueue.main.async { [weak self] in
                self?.closeWorkspace(workspace)
            }
        }
    }

    /// Sends the conductor run script to a terminal with worktree env vars.
    func runWorktreeScript(_ workspace: Workspace) {
        guard let metadata = workspace.worktreeMetadata,
              let config = ConductorConfig.load(repoRoot: metadata.rootRepoPath),
              let runScript = config.scripts?.run else { return }
        runScriptInWorktreeTerminal(workspace: workspace, metadata: metadata, script: runScript)
    }

    /// Spawns a new terminal tab in the workspace with worktree env vars and runs the script.
    private func runScriptInWorktreeTerminal(workspace: Workspace, metadata: WorktreeMetadata, script: String) {
        let port = WorktreePortAllocator.shared.allocate(for: workspace.id)
        let defaultBranch = GitWorktreeService.defaultBranch(repoRoot: metadata.rootRepoPath)
        let env = WorktreeEnvironment.build(metadata: metadata, port: port, defaultBranch: defaultBranch)

        guard let paneId = workspace.bonsplitController.focusedPaneId,
              let newPanel = workspace.newTerminalSurface(
                  inPane: paneId,
                  workingDirectory: metadata.worktreePath,
                  startupEnvironment: env
              ) else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            newPanel.sendText("\(script)\r")
        }
    }
}
