import Foundation

/// `application/x-www-form-urlencoded` bodies and OAuth query strings.
enum FormEncoding {
    static func encode(_ form: [String: String]) -> String {
        // RFC 3986 unreserved characters only; `alphanumerics` would let non-ASCII letters through.
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        func escape(_ text: String) -> String { text.addingPercentEncoding(withAllowedCharacters: allowed) ?? "" }
        return form.sorted { $0.key < $1.key }.map { "\(escape($0.key))=\(escape($0.value))" }.joined(separator: "&")
    }
}
