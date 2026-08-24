import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(LuminaPad)
@testable import LuminaPad

@MainActor
final class AppModelTests: XCTestCase {
    func testRefreshLoadsEveryHubCatalogAndUpdatesCache() async {
        AppModelURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            switch request.url?.path {
            case "/api/v1/devices": return (200, devicesEnvelope(power: false))
            case "/api/v1/modes": return (200, modesEnvelope)
            case "/api/v1/scenes": return (200, scenesEnvelope)
            case "/api/v1/runs": return (200, #"{"data":[]}"#)
            default: return (404, #"{"error":{"message":"unexpected route"}}"#)
            }
        }
        let cache = TestCacheStore()
        let model = AppModel(api: makeClient(), settings: configuredStore(), cache: cache)

        await model.refreshAll()

        XCTAssertTrue(model.isOnline)
        XCTAssertEqual(model.devices.map(\.id), ["wiz:test"])
        XCTAssertEqual(model.modes.map(\.id), ["wiz-14"])
        XCTAssertEqual(model.scenes.map(\.id), ["scene-test"])
        XCTAssertNotNil(model.lastUpdated)
        XCTAssertEqual(cache.savedDevices.map(\.id), ["wiz:test"])
        XCTAssertEqual(cache.savedModes.map(\.id), ["wiz-14"])
        XCTAssertEqual(cache.savedScenes.map(\.id), ["scene-test"])
    }

    func testControlUsesHubThenReconcilesFromReadBack() async throws {
        let cache = TestCacheStore(devices: [Self.device(power: false)])
        AppModelURLProtocol.handler = { request in
            switch (request.httpMethod, request.url?.path) {
            case ("POST", "/api/v1/devices/wiz:test/control"):
                let body = try XCTUnwrap(requestBody(request))
                let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
                XCTAssertEqual(object["power"] as? Bool, true)
                return (200, #"{"data":{}}"#)
            case ("GET", "/api/v1/devices"):
                return (200, devicesEnvelope(power: true))
            default:
                return (404, #"{"error":{"message":"unexpected route"}}"#)
            }
        }
        let model = AppModel(api: makeClient(), settings: configuredStore(), cache: cache)

        await model.control(deviceID: "wiz:test", action: .init(zone: "main", power: true))

        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.devices.first?.zoneState("main").power, true)
        XCTAssertEqual(cache.savedDevices.first?.zoneState("main").power, true)
    }

    func testPairingURLRequiresConfirmationBeforeSaving() throws {
        let model = AppModel(api: makeClient(), settings: TestConnectionStore(.init()), cache: TestCacheStore())
        let encodedBaseURL = try XCTUnwrap("http://192.0.2.10:17890".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed))
        let url = try XCTUnwrap(URL(string: "lumina://pair?baseURL=\(encodedBaseURL)&token=test-secret"))

        model.preparePairing(from: url)

        XCTAssertEqual(model.pendingPairing?.connection.baseURL, "http://192.0.2.10:17890")
        XCTAssertEqual(model.pendingPairing?.connection.bearerToken, "test-secret")
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.isConfigured)
    }

    func testForegroundRefreshDoesNotInterruptUnconfiguredPairing() async throws {
        let model = AppModel(api: makeClient(), settings: TestConnectionStore(.init()), cache: TestCacheStore())

        model.beginForegroundRefresh()
        try await Task.sleep(for: .milliseconds(50))
        model.stopForegroundRefresh()

        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.isConfigured)
    }

    func testFailedPairingRemainsAvailableForPermissionRetry() async throws {
        AppModelURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/v1/health")
            return (503, #"{"error":{"message":"offline"}}"#)
        }
        let model = AppModel(api: makeClient(), settings: TestConnectionStore(.init()), cache: TestCacheStore())
        let encodedBaseURL = try XCTUnwrap("http://192.0.2.10:17890".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed))
        let url = try XCTUnwrap(URL(string: "lumina://pair?baseURL=\(encodedBaseURL)&token=test-secret"))
        model.preparePairing(from: url)

        await model.confirmPendingPairing()

        XCTAssertNotNil(model.pendingPairing)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.isConfigured)
    }

    func testPairingRemainsAvailableWhenCredentialStorageFails() async throws {
        AppModelURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/v1/health")
            return (200, #"{"data":{"status":"ok"}}"#)
        }
        let model = AppModel(api: makeClient(), settings: SaveFailingConnectionStore(), cache: TestCacheStore())
        let encodedBaseURL = try XCTUnwrap("http://192.0.2.10:17890".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed))
        model.preparePairing(from: try XCTUnwrap(URL(string: "lumina://pair?baseURL=\(encodedBaseURL)&token=test-secret")))

        await model.confirmPendingPairing()

        XCTAssertNotNil(model.pendingPairing)
        XCTAssertEqual(model.errorMessage, "测试凭据存储不可用")
        XCTAssertFalse(model.isConfigured)
    }

    func testWidgetDeepLinkRunsSceneThroughConfiguredMainApp() async throws {
        AppModelURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/v1/scenes/scene_focus/run")
            return (200, #"{"data":{"run":{"id":"run-widget","sceneId":"scene_focus","status":"running"}}}"#)
        }
        let cache = TestCacheStore(scenes: [Scene(id: "scene_focus", name: "专注")])
        let model = AppModel(api: makeClient(), settings: configuredStore(), cache: cache)
        let url = try XCTUnwrap(URL(string: "lumina://run-scene?id=scene_focus"))

        await model.handleDeepLink(url)

        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.runs.first?.id, "run-widget")
        XCTAssertEqual(model.confirmationMessage, "正在运行“专注”")
    }

    func testWidgetDeepLinkRejectsMissingSceneID() async throws {
        let model = AppModel(api: makeClient(), settings: configuredStore(), cache: TestCacheStore())

        await model.handleDeepLink(try XCTUnwrap(URL(string: "lumina://run-scene")))

        XCTAssertEqual(model.errorMessage, "场景链接缺少有效的场景 ID")
    }

    private func makeClient() -> LuminaAPIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AppModelURLProtocol.self]
        return LuminaAPIClient(session: URLSession(configuration: configuration))
    }

    private func configuredStore() -> TestConnectionStore {
        TestConnectionStore(.init(baseURL: "https://lumina.invalid", bearerToken: "test-token"))
    }

    private static func device(power: Bool) -> Device {
        Device(
            id: "wiz:test",
            name: "测试灯",
            vendor: "wiz",
            online: true,
            capabilities: .init(zones: [.init(id: "main", brightness: .init(min: 1, max: 100))]),
            state: .init(zones: ["main": .init(power: power, brightness: 50)])
        )
    }

}

private func devicesEnvelope(power: Bool) -> String {
    """
    {"data":[{"id":"wiz:test","name":"测试灯","vendor":"wiz","online":true,"capabilities":{"zones":[{"id":"main","label":"主灯","power":true,"brightness":{"min":1,"max":100}}]},"state":{"zones":{"main":{"power":\(power),"brightness":50}}}}]}
    """
}

private let modesEnvelope = #"{"data":[{"id":"wiz-14","sceneId":14,"name":"夜灯","category":"function","dynamic":false,"frontCct":2200}]}"#
private let scenesEnvelope = #"{"data":[{"id":"scene-test","name":"测试场景","tracks":[{"deviceId":"wiz:test","zone":"main","keyframes":[{"offsetMs":0,"power":true}]}]}]}"#

private final class TestConnectionStore: ConnectionStore {
    private(set) var connection: HubConnection
    init(_ connection: HubConnection) { self.connection = connection }
    func loadConnection() -> HubConnection { connection }
    func saveConnection(_ connection: HubConnection) throws { self.connection = connection }
}

private struct SaveFailingConnectionStore: ConnectionStore {
    private struct StorageError: LocalizedError {
        var errorDescription: String? { "测试凭据存储不可用" }
    }

    func loadConnection() -> HubConnection { .init() }
    func saveConnection(_ connection: HubConnection) throws { throw StorageError() }
}

private final class TestCacheStore: CacheStore {
    private let initialDevices: [Device]
    private let initialScenes: [Scene]
    private let initialModes: [LightMode]
    private(set) var savedDevices: [Device] = []
    private(set) var savedScenes: [Scene] = []
    private(set) var savedModes: [LightMode] = []

    init(devices: [Device] = [], scenes: [Scene] = [], modes: [LightMode] = []) {
        initialDevices = devices
        initialScenes = scenes
        initialModes = modes
    }

    func loadDevices() -> [Device] { initialDevices }
    func loadScenes() -> [Scene] { initialScenes }
    func loadModes() -> [LightMode] { initialModes }
    func save(devices: [Device], scenes: [Scene], modes: [LightMode]) {
        savedDevices = devices
        savedScenes = scenes
        savedModes = modes
    }
}

private final class AppModelURLProtocol: URLProtocol {
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

private func requestBody(_ request: URLRequest) -> Data? {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return nil }
    stream.open()
    defer { stream.close() }
    var body = Data()
    var buffer = [UInt8](repeating: 0, count: 4_096)
    while true {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count <= 0 { break }
        body.append(buffer, count: count)
    }
    return body
}
#endif
