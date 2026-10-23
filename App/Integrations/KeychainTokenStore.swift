import Foundation
import Integrations
import TimesheetCore

/// Integration tokens in the Keychain, one account per `TokenKey`.
struct KeychainTokenStore: TokenStore {
    func get(_ key: TokenKey) -> String? {
        KeychainStore.get(account: key.rawValue)
    }

    func set(_ value: String, for key: TokenKey) throws {
        try KeychainStore.set(value, account: key.rawValue)
    }

    func delete(_ key: TokenKey) {
        KeychainStore.delete(account: key.rawValue)
    }
}
