import Foundation

extension Workspace {
    private static var _worktreeMetadata: [UUID: WorktreeMetadata] = [:]
    private static let _worktreeLock = NSLock()

    var worktreeMetadata: WorktreeMetadata? {
        get {
            Self._worktreeLock.lock()
            defer { Self._worktreeLock.unlock() }
            return Self._worktreeMetadata[id]
        }
        set {
            Self._worktreeLock.lock()
            Self._worktreeMetadata[id] = newValue
            Self._worktreeLock.unlock()
            objectWillChange.send()
        }
    }

    static func cleanupWorktreeMetadata(for id: UUID) {
        _worktreeLock.lock()
        _worktreeMetadata.removeValue(forKey: id)
        _worktreeLock.unlock()
    }
}
