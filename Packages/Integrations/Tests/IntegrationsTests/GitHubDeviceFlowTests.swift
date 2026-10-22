import Foundation
import Testing
import TimesheetCore
@testable import Integrations

/// Answers device-flow requests from a queue of replies, in order.
/// State is static, so the suite using it is `.serialized`.
final class DeviceStubProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var replies: [(status: Int, body: String)] = []
    nonisolated(unsafe) private static var captured: [URLRequest] = []

    static func session(_ replies: [(status: Int, body: String)]) -> URLSession {
        lock.withLock {
            self.replies = replies
            captured = []
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DeviceStubProtocol.self]
        return URLSession(configuration: config)
    }

    static var requests: [URLRequest] { lock.withLock { captured } }

    static func form(of request: URLRequest) -> [String: String] {
        var components = URLComponents()
        components.percentEncodedQuery = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
        return Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var request = self.request
        if request.httpBody == nil, let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
            stream.close()
            request.httpBody = data
        }
        let reply = Self.lock.withLock {
            Self.captured.append(request)
            return Self.replies.isEmpty ? (status: 500, body: "") : Self.replies.removeFirst()
        }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Records requested sleeps instead of waiting.
private actor SleepRecorder {
    private(set) var sleeps: [Duration] = []
    func record(_ duration: Duration) { sleeps.append(duration) }
}

@Suite(.serialized)
struct GitHubDeviceFlowTests {
    private static let clientId = "Iv1.testclient"
    private static let code = DeviceCode(
        userCode: "WDJB-MJHT", verificationURL: URL(string: "https://github.com/login/device")!, interval: 5,
        deviceCode: "device-code-1")
    private static let pending = (status: 200, body: #"{"error":"authorization_pending"}"#)
    private static let granted = (
        status: 200,
        body: #"{"access_token":"test-access-1","token_type":"bearer","scope":"","expires_in":28800,"refresh_token":"test-refresh-1"}"#)

    private static func flow(
        _ replies: [(status: Int, body: String)], recorder: SleepRecorder = SleepRecorder(),
        now: Date = Date(timeIntervalSince1970: 1_000_000)
    ) -> GitHubDeviceFlow {
        GitHubDeviceFlow(
            clientId: clientId, session: DeviceStubProtocol.session(replies),
            sleep: { await recorder.record($0) }, now: { now })
    }

    @Test func deviceStartParses() async throws {
        let flow = Self.flow([(200, """
            {"device_code":"device-code-1","user_code":"WDJB-MJHT",\
            "verification_uri":"https://github.com/login/device","expires_in":900,"interval":5}
            """)])
        #expect(try await flow.start() == Self.code)

        let request = try #require(DeviceStubProtocol.requests.first)
        #expect(request.url?.absoluteString == "https://github.com/login/device/code")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(DeviceStubProtocol.form(of: request) == ["client_id": Self.clientId])
    }

    @Test func startRejectsForeignVerificationURL() async {
        let flow = Self.flow([(200, """
            {"device_code":"d","user_code":"u","verification_uri":"https://example.com/login/device","interval":5}
            """)])
        await #expect(throws: ContextError.unexpectedReply(.github)) { try await flow.start() }
    }

    @Test func pollWaitsThenSucceeds() async throws {
        let recorder = SleepRecorder()
        let now = Date(timeIntervalSince1970: 1_000_000)
        let flow = Self.flow([Self.pending, Self.granted], recorder: recorder, now: now)
        let token = try await flow.poll(Self.code)

        #expect(token == OAuthToken(
            accessToken: "test-access-1", refreshToken: "test-refresh-1",
            expiresAt: now.addingTimeInterval(28800), clientId: Self.clientId))
        #expect(await recorder.sleeps == [.seconds(5), .seconds(5)])

        let requests = DeviceStubProtocol.requests
        #expect(requests.count == 2)
        let request = try #require(requests.last)
        #expect(request.url?.absoluteString == "https://github.com/login/oauth/access_token")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(DeviceStubProtocol.form(of: request) == [
            "client_id": Self.clientId, "device_code": "device-code-1",
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
        ])
    }

    @Test func pollSlowDownIncreasesInterval() async throws {
        let recorder = SleepRecorder()
        let flow = Self.flow(
            [(200, #"{"error":"slow_down","interval":10}"#), Self.pending, Self.granted], recorder: recorder)
        _ = try await flow.poll(Self.code)
        #expect(await recorder.sleeps == [.seconds(5), .seconds(10), .seconds(10)])
    }

    @Test(arguments: ["access_denied", "expired_token"])
    func pollDeniedSignInAgain(error: String) async {
        let flow = Self.flow([Self.pending, (200, #"{"error":"\#(error)","error_description":"server text"}"#)])
        await #expect(throws: ContextError.signInAgain(.github)) { try await flow.poll(Self.code) }
    }

    @Test func pollUnknownErrorUnexpectedReply() async {
        let flow = Self.flow([(200, #"{"error":"device_flow_disabled"}"#)])
        await #expect(throws: ContextError.unexpectedReply(.github)) { try await flow.poll(Self.code) }
    }

    @Test func serverErrorUnexpectedReply() async {
        let flow = Self.flow([(500, "oops")])
        await #expect(throws: ContextError.unexpectedReply(.github)) { try await flow.start() }
    }
}
