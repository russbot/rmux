import Foundation

/// Builds environment variables for a worktree-backed workspace.
/// Provides both cmux-native and Conductor-compatible variables.
enum WorktreeEnvironment {
    static func build(metadata: WorktreeMetadata, port: Int, defaultBranch: String) -> [String: String] {
        [
            "CMUX_ROOT_PATH": metadata.rootRepoPath,
            "CMUX_WORKSPACE_NAME": metadata.workspaceName,
            "CMUX_WORKTREE_PATH": metadata.worktreePath,
            "CMUX_BRANCH_NAME": metadata.branchName,
            "CONDUCTOR_ROOT_PATH": metadata.rootRepoPath,
            "CONDUCTOR_WORKSPACE_NAME": metadata.workspaceName,
            "CONDUCTOR_WORKSPACE_PATH": metadata.worktreePath,
            "CONDUCTOR_DEFAULT_BRANCH": defaultBranch,
            "CONDUCTOR_PORT": String(port),
        ]
    }
}
