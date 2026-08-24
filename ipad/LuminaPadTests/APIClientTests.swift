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
