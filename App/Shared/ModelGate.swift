import Foundation

/// Runs model calls one at a time, first come first served, so compile and context summaries
/// never load or drive the model concurrently.
actor ModelGate {
    static let shared = ModelGate()

    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func run<T: Sendable>(_ work: @Sendable () async throws -> T) async rethrows -> T {
        await acquire()
        defer { release() }
        return try await work()
    }

    /// An actor alone isn't enough: it is re-entrant across `await work()`.
    private func acquire() async {
        guard busy else {
            busy = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    /// Hands the gate straight to the next waiter, so a newcomer can't jump the queue.
    private func release() {
        if waiters.isEmpty {
            busy = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}
