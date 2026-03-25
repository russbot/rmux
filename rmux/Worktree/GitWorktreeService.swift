import Foundation

/// Entry parsed from `git worktree list --porcelain`.
struct WorktreeEntry: Identifiable, Equatable {
    var id: String { path }
    let path: String
    let head: String
    let branch: String?
    let isBare: Bool
}

enum WorktreeError: Error, LocalizedError {
    case gitFailed(String)
    case alreadyExists(String)
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case .gitFailed(let msg): return msg
        case .alreadyExists(let msg): return msg
        case .notFound(let msg): return msg
        }
    }
}

/// Static service wrapping git worktree commands via Foundation.Process.
/// All methods are nonisolated static for background-queue use.
enum GitWorktreeService {

    // MARK: - Queries

    static func listWorktrees(repoRoot: String) -> [WorktreeEntry] {
        guard let output = runGitCommand(directory: repoRoot, arguments: ["worktree", "list", "--porcelain"]) else {
            return []
        }
        return parsePorcelainWorktreeList(output)
    }

    static func repoRoot(for directory: String) -> String? {
        runGitCommand(directory: directory, arguments: ["rev-parse", "--show-toplevel"])?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    struct LocalBranch: Identifiable, Equatable {
        var id: String { name }
        let name: String
        let isCurrent: Bool
        let isInWorktree: Bool
    }

    static func localBranches(repoRoot: String) -> [LocalBranch] {
        guard let output = runGitCommand(directory: repoRoot, arguments: ["branch", "--list"]) else {
            return []
        }
        return output
            .split(separator: "\n")
            .map {
                let raw = $0.trimmingCharacters(in: .whitespaces)
                if raw.hasPrefix("* ") {
                    return LocalBranch(name: String(raw.dropFirst(2)), isCurrent: true, isInWorktree: false)
                } else if raw.hasPrefix("+ ") {
                    return LocalBranch(name: String(raw.dropFirst(2)), isCurrent: false, isInWorktree: true)
                } else {
                    return LocalBranch(name: raw, isCurrent: false, isInWorktree: false)
                }
            }
    }

    static func defaultBranch(repoRoot: String) -> String {
        if let ref = runGitCommand(directory: repoRoot, arguments: ["symbolic-ref", "refs/remotes/origin/HEAD"]) {
            let trimmed = ref.trimmingCharacters(in: .whitespacesAndNewlines)
            if let last = trimmed.split(separator: "/").last {
                return String(last)
            }
        }
        return "main"
    }

    // MARK: - Mutations

    static func createWorktree(
        repoRoot: String,
        path: String,
        branch: String,
        createNewBranch: Bool
    ) -> Result<String, WorktreeError> {
        var args = ["worktree", "add"]
        if createNewBranch {
            args += ["-b", branch, path]
        } else {
            args += [path, branch]
        }
        guard let output = runGitCommand(directory: repoRoot, arguments: args) else {
            return .failure(.gitFailed("Failed to create worktree at \(path) for branch \(branch)"))
        }
        return .success(output)
    }

    static func removeWorktree(repoRoot: String, path: String, force: Bool = false) -> Result<Void, WorktreeError> {
        var args = ["worktree", "remove"]
        if force { args.append("--force") }
        args.append(path)

        let process = Process()
        let stderrPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", repoRoot] + args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return .failure(.gitFailed("Failed to launch git: \(error.localizedDescription)"))
        }

        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        if process.terminationStatus == 0 {
            return .success(())
        }

        let stderrMsg = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return .failure(.gitFailed(stderrMsg.isEmpty ? "Failed to remove worktree at \(path)" : stderrMsg))
    }

    /// Cleans up stale worktree tracking entries (e.g. from interrupted removals).
    static func pruneWorktrees(repoRoot: String) {
        let _ = runGitCommand(directory: repoRoot, arguments: ["worktree", "prune"])
    }

    // MARK: - Helpers

    static func defaultWorktreePath(repoRoot: String, branchName: String) -> String {
        let parent = URL(fileURLWithPath: repoRoot).deletingLastPathComponent().path
        return "\(parent)/worktrees/\(branchSlug(branchName))"
    }

    static func branchSlug(_ branch: String) -> String {
        var slug = branch
        // Strip remote prefix like "origin/"
        if let slashIndex = slug.firstIndex(of: "/"),
           slug[slug.startIndex..<slashIndex].allSatisfy({ $0.isLetter || $0.isNumber }) {
            slug = String(slug[slug.index(after: slashIndex)...])
        }
        return slug.replacingOccurrences(of: "/", with: "_")
    }

    // MARK: - Git Process

    private static func runGitCommand(directory: String, arguments: [String]) -> String? {
        let process = Process()
        let stdout = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", directory] + arguments
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Porcelain Parser

    private static func parsePorcelainWorktreeList(_ output: String) -> [WorktreeEntry] {
        var entries: [WorktreeEntry] = []
        var currentPath: String?
        var currentHead: String = ""
        var currentBranch: String?
        var isBare = false

        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let str = String(line)
            if str.isEmpty {
                if let path = currentPath {
                    entries.append(WorktreeEntry(
                        path: path,
                        head: currentHead,
                        branch: currentBranch,
                        isBare: isBare
                    ))
                }
                currentPath = nil
                currentHead = ""
                currentBranch = nil
                isBare = false
            } else if str.hasPrefix("worktree ") {
                currentPath = String(str.dropFirst("worktree ".count))
            } else if str.hasPrefix("HEAD ") {
                currentHead = String(str.dropFirst("HEAD ".count))
            } else if str.hasPrefix("branch ") {
                let ref = String(str.dropFirst("branch ".count))
                // Strip refs/heads/ prefix
                if ref.hasPrefix("refs/heads/") {
                    currentBranch = String(ref.dropFirst("refs/heads/".count))
                } else {
                    currentBranch = ref
                }
            } else if str == "bare" {
                isBare = true
            }
        }

        // Handle last entry if no trailing newline
        if let path = currentPath {
            entries.append(WorktreeEntry(
                path: path,
                head: currentHead,
                branch: currentBranch,
                isBare: isBare
            ))
        }

        return entries
    }
}
