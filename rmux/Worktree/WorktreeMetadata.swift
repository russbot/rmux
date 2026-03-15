import Foundation

/// Metadata for a workspace backed by a git worktree.
/// Codable for session persistence.
struct WorktreeMetadata: Codable, Equatable, Sendable {
    let rootRepoPath: String
    let worktreePath: String
    let branchName: String
    let workspaceName: String
}
