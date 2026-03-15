import SwiftUI

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
            Text(String(localized: "worktree.picker.title", defaultValue: "Git Worktrees"))
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
            Text(String(localized: "worktree.picker.existing", defaultValue: "Existing Worktrees"))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            if worktrees.isEmpty {
                Text(String(localized: "worktree.picker.noWorktrees", defaultValue: "No worktrees found"))
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
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.05)))
    }

    private var createNewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "worktree.picker.createNew", defaultValue: "Create New Worktree"))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            BranchNameField(text: $newBranchName)

            if !localBranches.isEmpty {
                Picker(
                    String(localized: "worktree.picker.baseBranch", defaultValue: "Base branch"),
                    selection: Binding(
                        get: { selectedBaseBranch ?? "" },
                        set: { selectedBaseBranch = $0.isEmpty ? nil : $0 }
                    )
                ) {
                    ForEach(localBranches) { branch in
                        HStack {
                            Text(branch.name)
                            if branch.isCurrent {
                                Text(String(localized: "worktree.picker.currentBranch", defaultValue: "(current)"))
                                    .foregroundStyle(.secondary)
                            } else if branch.isInWorktree {
                                Text(String(localized: "worktree.picker.inWorktree", defaultValue: "(in worktree)"))
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
                    Text(String(localized: "worktree.picker.createAndOpen", defaultValue: "Create & Open"))
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
            errorMessage = String(localized: "worktree.picker.noRepo", defaultValue: "No git repository found in current workspace")
            isLoading = false
            return
        }

        let result: (root: String?, worktrees: [WorktreeEntry], branches: [GitWorktreeService.LocalBranch]) = await Task.detached {
            let root = GitWorktreeService.repoRoot(for: cwd)
            guard let root else { return (nil, [], []) }
            let wts = GitWorktreeService.listWorktrees(repoRoot: root)
            let branches = GitWorktreeService.localBranches(repoRoot: root)
            return (root, wts, branches)
        }.value

        repoRoot = result.root
        worktrees = result.worktrees
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
            errorMessage = String(localized: "worktree.picker.noRepo", defaultValue: "No git repository found in current workspace")
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
        TextField(
            String(localized: "worktree.picker.branchName", defaultValue: "New branch name"),
            text: $text
        )
        .textFieldStyle(.roundedBorder)
        .font(.body)
    }
}
