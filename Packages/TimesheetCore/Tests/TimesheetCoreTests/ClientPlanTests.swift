import Foundation
import Testing
@testable import TimesheetCore

struct ClientPlanTests {
    func endpoint(_ url: String, confirmed: Bool = false) -> EndpointConfig {
        EndpointConfig(baseURL: URL(string: url)!, model: "m", remoteConfirmed: confirmed)
    }

    @Test func noModelIsUnavailable() {
        #expect(ClientPlan.resolve(.none, isDownloaded: { _ in true }) == .unavailable(.noModel))
    }

    @Test func downloadedLocalModelIsUsed() {
        #expect(ClientPlan.resolve(.local(repoId: "org/m"), isDownloaded: { $0 == "org/m" })
            == .local(repoId: "org/m"))
    }

    @Test func missingLocalModelIsUnavailable() {
        #expect(ClientPlan.resolve(.local(repoId: "org/m"), isDownloaded: { _ in false })
            == .unavailable(.notDownloaded))
    }

    @Test func localEndpointNeedsNoConfirmation() {
        let config = endpoint("http://localhost:11434")
        #expect(ClientPlan.resolve(.endpoint(config), isDownloaded: { _ in false }) == .endpoint(config))
    }

    @Test func unconfirmedRemoteEndpointIsUnavailable() {
        let config = endpoint("https://api.example.com/v1")
        #expect(ClientPlan.resolve(.endpoint(config), isDownloaded: { _ in false })
            == .unavailable(.remoteNotConfirmed))
    }

    @Test func confirmedRemoteEndpointIsUsed() {
        let config = endpoint("https://api.example.com/v1", confirmed: true)
        #expect(ClientPlan.resolve(.endpoint(config), isDownloaded: { _ in false }) == .endpoint(config))
    }

    @Test func everyReasonHasANote() {
        for reason in [ClientPlan.Unavailable.noModel, .notDownloaded, .remoteNotConfirmed] {
            #expect(!reason.note.isEmpty)
        }
    }
}
