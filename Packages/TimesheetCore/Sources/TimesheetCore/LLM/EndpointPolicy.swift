import Darwin
import Foundation

/// Classifies an endpoint as local (this machine or a private network) by its literal host only.
/// No DNS lookups: any hostname other than `localhost` / `*.local` counts as non-local.
public enum EndpointPolicy {
    public static func isLocal(_ url: URL) -> Bool {
        guard var host = url.host(percentEncoded: false)?.lowercased(), !host.isEmpty else { return false }
        if host.hasPrefix("["), host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        if host.hasSuffix(".") { host.removeLast() }

        if host == "localhost" || host.hasSuffix(".local") { return true }
        if let v4 = parseIPv4(host) { return isPrivateIPv4(v4) }
        if let v6 = parseIPv6(host) { return isPrivateIPv6(v6) }
        return false
    }

    /// 127/8, 10/8, 172.16/12, 192.168/16, 169.254/16.
    private static func isPrivateIPv4(_ a: [UInt8]) -> Bool {
        switch (a[0], a[1]) {
        case (127, _), (10, _), (172, 16...31), (192, 168), (169, 254): return true
        default: return false
        }
    }

    /// ::1, fc00::/7 (unique-local), fe80::/10 (link-local), and IPv4-mapped private addresses.
    private static func isPrivateIPv6(_ a: [UInt8]) -> Bool {
        if a == [UInt8](repeating: 0, count: 15) + [1] { return true }
        if a[0] & 0xFE == 0xFC { return true }
        if a[0] == 0xFE, a[1] & 0xC0 == 0x80 { return true }
        if a[0..<10].allSatisfy({ $0 == 0 }), a[10] == 0xFF, a[11] == 0xFF {
            return isPrivateIPv4(Array(a[12..<16]))
        }
        return false
    }

    /// Strict dotted-quad only, so shorthand like `127.1` or hostnames are rejected.
    private static func parseIPv4(_ host: String) -> [UInt8]? {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var bytes: [UInt8] = []
        for part in parts {
            guard !part.isEmpty, part.count <= 3, part.allSatisfy(\.isASCII), part.allSatisfy(\.isNumber),
                  let value = UInt8(part)
            else { return nil }
            bytes.append(value)
        }
        return bytes
    }

    private static func parseIPv6(_ host: String) -> [UInt8]? {
        // Drop a zone id such as `%en0` from link-local addresses.
        let address = host.split(separator: "%", maxSplits: 1).first.map(String.init) ?? host
        var storage = in6_addr()
        guard inet_pton(AF_INET6, address, &storage) == 1 else { return nil }
        return withUnsafeBytes(of: &storage) { Array($0) }
    }
}
