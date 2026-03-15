import Foundation

/// In-memory port registry. Allocates blocks of 10 consecutive ports per workspace,
/// matching Conductor's behavior where CONDUCTOR_PORT is the first of 10 exclusive ports.
final class WorktreePortAllocator {
    static let shared = WorktreePortAllocator()

    private let blockSize = 10
    private let basePort = 3000
    private var allocations: [UUID: Int] = [:]
    private let lock = NSLock()

    private init() {}

    /// Returns the first port of a 10-port block for the given workspace.
    func allocate(for workspaceId: UUID) -> Int {
        lock.lock()
        defer { lock.unlock() }

        if let existing = allocations[workspaceId] {
            return existing
        }

        let usedPorts = Set(allocations.values)
        var candidate = basePort
        while usedPorts.contains(candidate) {
            candidate += blockSize
        }
        allocations[workspaceId] = candidate
        return candidate
    }

    func release(workspaceId: UUID) {
        lock.lock()
        defer { lock.unlock() }
        allocations.removeValue(forKey: workspaceId)
    }
}
