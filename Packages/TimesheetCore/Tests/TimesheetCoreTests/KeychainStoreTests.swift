import Foundation
import Testing
@testable import TimesheetCore

struct KeychainStoreTests {
    @Test func roundTripAndOverwrite() throws {
        let account = "test-only-\(UUID().uuidString)"
        defer { KeychainStore.delete(account: account) }

        #expect(KeychainStore.get(account: account) == nil)
        try KeychainStore.set("first", account: account)
        #expect(KeychainStore.get(account: account) == "first")
        try KeychainStore.set("second", account: account)
        #expect(KeychainStore.get(account: account) == "second")
        KeychainStore.delete(account: account)
        #expect(KeychainStore.get(account: account) == nil)
    }

    @Test func deleteMissingIsNoOp() {
        KeychainStore.delete(account: "test-only-missing-\(UUID().uuidString)")
    }
}
