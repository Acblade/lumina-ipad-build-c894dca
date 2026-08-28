import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(LuminaPad)
@testable import LuminaPad
#else
@testable import LuminaCore
#endif

final class APIClientTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.handler = nil
    }

    func testDevicesUnwrapsDataEnvelopeAndSendsAuthentication() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
            XCTAssertEqual(request.value(forHTTPHeaderField: "CF-Access-Client-Id"), "client-id")
            XCTAssertEqual(request.url?.path, "/api/v1/devices")
            return (200, #"{"data":[]}"#)
        }

        let devices = try await client().devices(.init(
            baseURL: "https://lumina.example",
            bearerToken: "secret",
            cloudflareClientID: "client-id",
            cloudflareClientSecret: "client-secret"
        ))
        XCTAssertTrue(devices.isEmpty)
    }

    func testSceneRunEncodesPathComponentAndDecodesRun() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.url?.absoluteString.contains("/api/v1/scenes/scene%2Fnight/run") == true)
            return (200, #"{"data":{"id":"run-1","sceneId":"scene/night","status":"running","trackResults":[]}}"#)
        }

        let run = try await client().runScene(
            .init(baseURL: "https://lumina.example", bearerToken: "secret"),
            sceneID: "scene/night"
        )
        XCTAssertEqual(run.id, "run-1")
        XCTAssertEqual(run.status, "running")
    }

    func testSceneRunDecodesCommandDeviceReadBack() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/v1/scenes/scene-1/run")
            return (200, devicesCommandEnvelope)
        }

        let result = try await client().runSceneWithReadBack(
            .init(baseURL: "https://lumina.example", bearerToken: "secret"),
            sceneID: "scene-1"
        )

        XCTAssertEqual(result.run.id, "run-1")
        XCTAssertEqual(result.devices.first?.id, "wiz:test")
        XCTAssertEqual(result.devices.first?.zoneState("main").power, true)
    }

    func testLocalEndpointWinsWhenRelayIsAlsoConfigured() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.host, "192.0.2.10")
            XCTAssertEqual(request.url?.path, "/api/v1/devices")
            return (200, #"{"data":[]}"#)
        }

        let devices = try await client().devices(.init(
            baseURL: "https://lumina-relay.workers.dev",
            bearerToken: "secret",
            cloudflareClientID: "client-id",
            cloudflareClientSecret: "client-secret",
            localBaseURL: "http://192.0.2.10:17890"
        ))

        XCTAssertTrue(devices.isEmpty)
    }

    func testServerErrorUsesHubMessage() async {
        MockURLProtocol.handler = { _ in
            (401, #"{"error":{"code":"unauthorized","message":"Invalid bearer token","details":["Pair again"]}}"#)
        }
        do {
            try await client().health(.init(baseURL: "https://lumina.example", bearerToken: "bad"))
            XCTFail("Expected APIError")
        } catch let APIError.server(status, message) {
            XCTAssertEqual(status, 401)
            XCTAssertEqual(message, "Invalid bearer token：Pair again")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func client() -> LuminaAPIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return LuminaAPIClient(session: URLSession(configuration: configuration))
    }
}

private let devicesCommandEnvelope = """
{"data":{"run":{"id":"run-1","sceneId":"scene-1","status":"running"},"devices":[{"id":"wiz:test","name":"测试灯","vendor":"wiz","online":true,"capabilities":{"zones":[{"id":"main","label":"主灯","power":true,"brightness":{"min":1,"max":100}}]},"state":{"zones":{"main":{"power":true,"brightness":50}}}}]}}
"""

private final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, String))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw URLError(.badServerResponse) }
            let (status, body) = try handler(request)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
