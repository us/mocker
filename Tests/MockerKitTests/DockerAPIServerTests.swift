import Testing
import Foundation
@testable import MockerKit

@Suite("DockerAPIServer Tests")
struct DockerAPIServerTests {

    @Test("HTTPRequest strips API version prefix")
    func testStrippedPath() {
        let req = HTTPRequest(
            method: "GET",
            path: "/v1.47/containers/json",
            queryItems: [:],
            headers: [:],
            body: Data()
        )
        #expect(req.strippedPath == "/containers/json")
    }

    @Test("HTTPRequest strips two-digit minor version")
    func testStrippedPathTwoDigit() {
        let req = HTTPRequest(
            method: "GET",
            path: "/v1.100/images/json",
            queryItems: [:],
            headers: [:],
            body: Data()
        )
        #expect(req.strippedPath == "/images/json")
    }

    @Test("HTTPRequest passes through non-versioned path")
    func testStrippedPathNoVersion() {
        let req = HTTPRequest(
            method: "GET",
            path: "/_ping",
            queryItems: [:],
            headers: [:],
            body: Data()
        )
        #expect(req.strippedPath == "/_ping")
    }

    @Test("HTTPResponse.json produces correct Content-Type header")
    func testJSONResponseHeaders() {
        struct Payload: Encodable, Sendable { let ok: Bool }
        let resp = HTTPResponse.json(body: Payload(ok: true))
        #expect(resp.status == 200)
        #expect(resp.headers["Content-Type"] == "application/json")
        #expect(resp.headers["Api-Version"] == DockerAPIServer.apiVersion)
    }

    @Test("HTTPResponse.text produces correct headers")
    func testTextResponseHeaders() {
        let resp = HTTPResponse.text(body: "OK")
        #expect(resp.status == 200)
        #expect(resp.headers["Content-Type"]?.hasPrefix("text/plain") == true)
    }

    @Test("HTTPResponse.noContent produces 204 with empty body")
    func testNoContentResponse() {
        let resp = HTTPResponse.noContent()
        #expect(resp.status == 204)
        #expect(resp.body.isEmpty)
    }

    @Test("HTTPResponse.error produces expected JSON")
    func testErrorResponse() throws {
        let resp = HTTPResponse.error(404, message: "not found")
        #expect(resp.status == 404)
        let json = try JSONDecoder().decode([String: String].self, from: resp.body)
        #expect(json["message"] == "not found")
    }

    @Test("versionResponse returns correct API version")
    func testVersionResponse() throws {
        let resp = DockerAPIHandlers.versionResponse()
        #expect(resp.status == 200)
        let json = try JSONDecoder().decode([String: AnyCodable].self, from: resp.body)
        #expect(json["ApiVersion"]?.stringValue == DockerAPIServer.apiVersion)
    }

    @Test("MockerConfig includes socketPath")
    func testSocketPath() {
        let config = MockerConfig()
        #expect(config.socketPath.hasSuffix("mocker.sock"))
    }

    @Test("MockerConfig includes launchAgentPlistPath")
    func testLaunchAgentPlistPath() {
        let config = MockerConfig()
        #expect(config.launchAgentPlistPath.hasSuffix(".plist"))
        #expect(config.launchAgentPlistPath.contains("LaunchAgents"))
    }

    @Test("MockerConfig has correct launchAgentLabel")
    func testLaunchAgentLabel() {
        #expect(MockerConfig.launchAgentLabel == "io.mocker.socket")
    }
}

// Minimal helper to decode any JSON value for test assertions.
private struct AnyCodable: Decodable {
    let stringValue: String?
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        stringValue = try? container.decode(String.self)
    }
}
