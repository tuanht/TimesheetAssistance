import Foundation
import Testing
@testable import TimesheetCore

struct EndpointPolicyTests {
    @Test(arguments: [
        "http://localhost:1234",
        "http://LOCALHOST:1234",
        "http://192.168.1.5:11434",
        "http://mac-studio.local",
        "http://127.0.0.1:8080",
        "http://127.8.9.10",
        "http://10.1.2.3",
        "http://172.16.0.1",
        "http://172.31.255.255",
        "http://169.254.1.1",
        "http://[::1]:8080",
        "http://[fd12:3456::1]:8080",
        "http://[fe80::1]",
    ])
    func local(_ string: String) {
        #expect(EndpointPolicy.isLocal(URL(string: string)!))
    }

    @Test(arguments: [
        "https://api.openai.com",
        "http://8.8.8.8",
        "http://172.32.0.1",
        "http://172.15.0.1",
        "http://192.169.0.1",
        "http://11.0.0.1",
        "http://[2001:4860:4860::8888]",
        "http://localhost.example.com",
        "http://local",
        "http://myserver",
        "http://127.0.0.1.nip.io",
    ])
    func nonLocal(_ string: String) {
        #expect(!EndpointPolicy.isLocal(URL(string: string)!))
    }

    @Test func noHostIsNotLocal() {
        #expect(!EndpointPolicy.isLocal(URL(string: "file:///tmp/x")!))
    }
}
