import Foundation
import TimesheetCore

/// What the user needs to approve a device sign-in, and what we poll with.
public struct DeviceCode: Equatable, Sendable {
    public let userCode: String
    public let verificationURL: URL
    public let interval: Int
    public let deviceCode: String

    public init(userCode: String, verificationURL: URL, interval: Int, deviceCode: String) {
        self.userCode = userCode
        self.verificationURL = verificationURL
        self.interval = interval
        self.deviceCode = deviceCode
    }
}

/// GitHub's OAuth device flow for a GitHub App. Sends only the client ID: no secret, and
/// GitHub Apps ignore scopes. Every error is a `ContextError`, never server text.
public struct GitHubDeviceFlow: Sendable {
    static let codeURL = URL(string: "https://github.com/login/device/code")!
    static let tokenURL = URL(string: "https://github.com/login/oauth/access_token")!
    static let grantType = "urn:ietf:params:oauth:grant-type:device_code"
    static let maxInterval = 120

    private let clientId: String
    private let session: URLSession
    private let sleep: @Sendable (Duration) async throws -> Void
    private let now: @Sendable () -> Date

    public init(clientId: String, session: URLSession? = nil) {
        self.init(clientId: clientId, session: session, sleep: { try await Task.sleep(for: $0) }, now: Date.init)
    }

    init(
        clientId: String, session: URLSession?, sleep: @escaping @Sendable (Duration) async throws -> Void,
        now: @escaping @Sendable () -> Date
    ) {
        self.clientId = clientId
        self.session = session ?? URLSession(
            configuration: .ephemeral, delegate: RedirectRefuser.shared, delegateQueue: nil)
        self.sleep = sleep
        self.now = now
    }

    public func start() async throws -> DeviceCode {
        let reply = try await post(Self.codeURL, form: ["client_id": clientId])
        guard case .string(let deviceCode)? = reply["device_code"],
              case .string(let userCode)? = reply["user_code"],
              case .string(let uri)? = reply["verification_uri"],
              let url = URL(string: uri), url.scheme == "https", url.host == "github.com",
              // Bounded so a bogus value can neither trap `Int(_:)` nor stall polling.
              case .number(let seconds)? = reply["interval"], let interval = Int(exactly: seconds),
              (1...Self.maxInterval).contains(interval)
        else { throw ContextError.unexpectedReply(.github) }
        return DeviceCode(userCode: userCode, verificationURL: url, interval: interval, deviceCode: deviceCode)
    }

    public func poll(_ code: DeviceCode) async throws -> OAuthToken {
        var interval = code.interval
        while true {
            try await sleep(.seconds(interval))
            let reply = try await post(Self.tokenURL, form: [
                "client_id": clientId, "device_code": code.deviceCode, "grant_type": Self.grantType,
            ])
            switch reply["error"] {
            case nil, .null?:
                return try token(from: reply)
            case .string("authorization_pending")?:
                continue
            case .string("slow_down")?:
                interval += 5
            case .string("expired_token")?, .string("access_denied")?:
                throw ContextError.signInAgain(.github)
            default:
                throw ContextError.unexpectedReply(.github)
            }
        }
    }

    private func token(from reply: JSONValue) throws -> OAuthToken {
        guard case .string(let access)? = reply["access_token"], !access.isEmpty else {
            throw ContextError.unexpectedReply(.github)
        }
        var refresh: String?
        if case .string(let value)? = reply["refresh_token"], !value.isEmpty { refresh = value }
        var expiresAt: Date?
        if case .number(let seconds)? = reply["expires_in"] { expiresAt = now().addingTimeInterval(seconds) }
        return OAuthToken(accessToken: access, refreshToken: refresh, expiresAt: expiresAt, clientId: clientId)
    }

    // MARK: - HTTP

    private func post(_ url: URL, form: [String: String]) async throws -> JSONValue {
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Data(FormEncoding.encode(form).utf8)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request, delegate: RedirectRefuser.shared)
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw ContextError.unreachable(.github)
        }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw ContextError.unexpectedReply(.github) }
        switch http.statusCode {
        case 200..<300: break
        // Redirects are refused, so GitHub is effectively unreachable.
        case 300..<400: throw ContextError.unreachable(.github)
        default: throw ContextError.unexpectedReply(.github)
        }
        guard let reply = try? JSONDecoder().decode(JSONValue.self, from: data), case .object = reply else {
            throw ContextError.unexpectedReply(.github)
        }
        return reply
    }
}
