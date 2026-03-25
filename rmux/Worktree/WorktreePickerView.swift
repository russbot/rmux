import SwiftUI

/// Tracks worktree paths currently being removed so they stay hidden across panel reopens.
/// Automatically clears paths whose directories no longer exist on disk.
private enum PendingWorktreeRemovals {
    private static var paths: Set<String> = []

    static func add(_ path: String) { paths.insert(path) }
    static func contains(_ path: String) -> Bool { paths.contains(path) }

    /// Remove paths whose directories are already gone.
    static func pruneCompleted() {
        paths = paths.filter { FileManager.default.fileExists(atPath: $0) }
    }
}

struct WorktreePickerView: View {
    @EnvironmentObject var tabManager: TabManager
    @Environment(\.dismiss) private var dismiss

    @State private var worktrees: [WorktreeEntry] = []
    @State private var localBranches: [GitWorktreeService.LocalBranch] = []
    @State private var repoRoot: String?
    @State private var isLoading = true
    @State private var errorMessage: String?

    // Create new worktree
    @State private var newBranchName = ""
    @State private var selectedBaseBranch: String?
    @State private var isCreating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if isLoading {
                loadingView
            } else if let error = errorMessage {
                errorView(error)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        existingWorktreesSection
                        Divider()
                        createNewSection
                    }
                    .padding(12)
                }
            }
        }
        .frame(width: 320, height: 400)
        .task { await loadData() }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack {
            Text("Git Worktrees")
                .font(.headline)
            Spacer()
        }
        .padding(12)
    }

    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    private var existingWorktreesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Existing Worktrees")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            if worktrees.isEmpty {
                Text("No worktrees found")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(worktrees) { entry in
                    worktreeRow(entry)
                }
            }
        }
    }

    private func worktreeRow(_ entry: WorktreeEntry) -> some View {
        HStack {
            Button {
                openExistingWorktree(entry)
            } label: {
                HStack {
                    Image(systemName: "arrow.triangle.branch")
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.branch ?? "detached")
                            .font(.body)
                            .lineLimit(1)
                        Text(entry.path)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !isMainWorktree(entry) {
                Button {
                    removeWorktree(entry)
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove worktree")
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.05)))
    }

    private var createNewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Create New Worktree")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            BranchNameField(text: $newBranchName)

            if !localBranches.isEmpty {
                Picker(
                    "Base branch",
                    selection: Binding(
                        get: { selectedBaseBranch ?? "" },
                        set: { selectedBaseBranch = $0.isEmpty ? nil : $0 }
                    )
                ) {
                    ForEach(localBranches) { branch in
                        HStack {
                            Text(branch.name)
                            if branch.isCurrent {
                                Text("(current)")
                                    .foregroundStyle(.secondary)
                            } else if branch.isInWorktree {
                                Text("(in worktree)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tag(branch.name)
                    }
                }
                .font(.caption)
            }

            Button {
                createAndOpen()
            } label: {
                HStack {
                    if isCreating {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                    Text("Create & Open")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(newBranchName.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
        }
    }

    // MARK: - Actions

    private func loadData() async {
        guard let cwd = tabManager.tabs.first(where: { $0.id == tabManager.selectedTabId })?.currentDirectory else {
            errorMessage = "No git repository found in current workspace"
            isLoading = false
            return
        }

        let result: (root: String?, worktrees: [WorktreeEntry], branches: [GitWorktreeService.LocalBranch]) = await Task.detached {
            let root = GitWorktreeService.repoRoot(for: cwd)
            guard let root else { return (nil, [], []) }
            GitWorktreeService.pruneWorktrees(repoRoot: root)
            let wts = GitWorktreeService.listWorktrees(repoRoot: root)
            let branches = GitWorktreeService.localBranches(repoRoot: root)
            return (root, wts, branches)
        }.value

        repoRoot = result.root
        PendingWorktreeRemovals.pruneCompleted()
        worktrees = result.worktrees.filter { !PendingWorktreeRemovals.contains($0.path) }
        localBranches = result.branches
        isLoading = false

        // Default to current tab's branch, then fall back to main/master
        if selectedBaseBranch == nil {
            let currentBranch = tabManager.tabs
                .first { $0.id == tabManager.selectedTabId }?
                .gitBranch?.branch
            selectedBaseBranch = localBranches.first { $0.name == currentBranch }?.name
                ?? localBranches.first { $0.name == "main" }?.name
                ?? localBranches.first { $0.name == "master" }?.name
        }

        if result.root == nil {
            errorMessage = "No git repository found in current workspace"
        }
    }

    private func isMainWorktree(_ entry: WorktreeEntry) -> Bool {
        if entry.isBare { return true }
        // The first entry from `git worktree list` is always the main worktree
        return worktrees.first?.id == entry.id
    }

    private func removeWorktree(_ entry: WorktreeEntry) {
        guard let root = repoRoot else { return }

        // Hide immediately, track as pending so it stays hidden across panel reopens
        worktrees.removeAll { $0.id == entry.id }
        PendingWorktreeRemovals.add(entry.path)

        // If this worktree is open as a tab, close it properly (releases ports, cleans metadata)
        if let openWorkspace = tabManager.tabs.first(where: { $0.worktreeMetadata?.worktreePath == entry.path }) {
            tabManager.removeWorktreeWorkspace(openWorkspace)
        } else {
            let path = entry.path
            Task.detached {
                let _ = GitWorktreeService.removeWorktree(repoRoot: root, path: path, force: true)
            }
        }
    }

    private func openExistingWorktree(_ entry: WorktreeEntry) {
        guard let root = repoRoot else { return }
        let metadata = WorktreeMetadata(
            rootRepoPath: root,
            worktreePath: entry.path,
            branchName: entry.branch ?? "detached",
            workspaceName: GitWorktreeService.branchSlug(entry.branch ?? "detached")
        )
        tabManager.addWorktreeWorkspace(metadata: metadata)
        dismiss()
    }

    private func createAndOpen() {
        guard let root = repoRoot else { return }
        let branch = newBranchName.trimmingCharacters(in: .whitespaces)
        guard !branch.isEmpty else { return }

        isCreating = true
        let path = GitWorktreeService.defaultWorktreePath(repoRoot: root, branchName: branch)

        Task.detached {
            let result = GitWorktreeService.createWorktree(
                repoRoot: root,
                path: path,
                branch: branch,
                createNewBranch: true
            )
            await handleCreateResult(result, root: root, path: path, branch: branch)
        }
    }

    @MainActor
    private func handleCreateResult(_ result: Result<String, WorktreeError>, root: String, path: String, branch: String) {
        isCreating = false
        switch result {
        case .success:
            let metadata = WorktreeMetadata(
                rootRepoPath: root,
                worktreePath: path,
                branchName: branch,
                workspaceName: GitWorktreeService.branchSlug(branch)
            )
            tabManager.addWorktreeWorkspace(metadata: metadata)
            dismiss()
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

}

/// Isolated text field to avoid re-rendering the entire picker on each keystroke.
private struct BranchNameField: View {
    @Binding var text: String

    var body: some View {
        TextField("New branch name", text: $text)
            .textFieldStyle(.roundedBorder)
            .font(.body)
    }
}
