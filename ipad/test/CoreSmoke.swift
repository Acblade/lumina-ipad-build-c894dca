import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@main
enum CoreSmoke {
    static func main() async throws {
        let fixture = Data(#"""
        {
          "id":"lamp-1","name":"屏幕灯","protocol":"yeelight","online":true,
          "capabilities":{
            "supportsRatio":true,
            "nativeScenes":[{"id":14,"name":"Night light"}],
            "zones":[
              {"id":"main","label":"主灯","power":true,"brightness":{"min":1,"max":100},"colorTemperature":{"min":2700,"max":6500},"whiteChannels":true},
              {"id":"ambient","label":"背光","power":true,"brightness":{"min":1,"max":100},"colorTemperature":{"min":1700,"max":6500},"rgb":true,"flow":true}
            ]
          },
          "state":{"zones":{"main":{"power":true,"brightness":55,"colorTemperatureKelvin":4000},"ambient":{"power":true,"brightness":25,"rgb":{"r":10,"g":20,"b":255}}}}
        }
        """#.utf8)
        let device = try JSONDecoder().decode(Device.self, from: fixture)
        try require(device.vendor == "yeelight", "protocol alias did not decode")
        try require(device.capabilities.support.isEmpty, "missing support did not default")
        try require(device.capabilities.zones[0].rgb == false, "missing rgb did not default")
        try require(device.capabilities.nativeScenes[0].dynamic == false, "missing dynamic did not default")

        let scene = Scene(
            name: "  测试场景  ",
            tracks: [SceneTrack(
                deviceId: "lamp-1",
                zone: "main",
                keyframes: [
                    .init(offsetMs: 1_000, brightness: 20),
                    .init(offsetMs: 0, power: true, brightness: 40),
                ]
            )]
        ).normalized
        try require(scene.name == "测试场景", "scene name was not normalized")
        try require(scene.durationMs == 1_000, "scene duration was not inferred")
        let sceneObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(scene)) as! [String: Any]
        let tracks = sceneObject["tracks"] as! [[String: Any]]
        try require(tracks[0]["repeat"] as? Bool == false, "repeat did not encode with Hub key")
        try require(tracks[0]["repeatTrack"] == nil, "internal repeatTrack leaked to Hub")
        try require(scene.validationError(devices: [device]) == nil, "valid Hub scene was rejected")
        let normalizedConnection = HubConnection(baseURL: "  http://hub.local:17890/  ", bearerToken: " token\n").normalized
        try require(normalizedConnection.baseURL == "http://hub.local:17890/", "Hub URL whitespace was not normalized")
        try require(normalizedConnection.bearerToken == "token", "bearer token whitespace was not normalized")

        let unsupported = Scene(
            name: "错误场景",
            tracks: [SceneTrack(
                deviceId: device.id,
                zone: "main",
                keyframes: [.init(offsetMs: 0, rgb: .init(r: 255, g: 0, b: 0))]
            )]
        )
        try require(unsupported.validationError(devices: [device])?.contains("RGB") == true, "capability validation did not reject RGB")

        MockURLProtocol.handler = { request in
            try require(request.value(forHTTPHeaderField: "Authorization") == "Bearer smoke-secret", "bearer header missing")
            try require(request.value(forHTTPHeaderField: "CF-Access-Client-Id") == "smoke-client", "Cloudflare header missing")
            try require(request.url?.path == "/api/v1/devices", "device endpoint mismatch")
            return (200, #"{"data":[]}"#)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let api = LuminaAPIClient(session: URLSession(configuration: configuration))
        let devices = try await api.devices(.init(
            baseURL: "https://lumina.invalid",
            bearerToken: " smoke-secret\n",
            cloudflareClientID: "smoke-client",
            cloudflareClientSecret: "smoke-client-secret"
        ))
        try require(devices.isEmpty, "data envelope did not decode")

        MockURLProtocol.handler = { _ in (200, #"{"data":{"unexpected":true}}"#) }
        do {
            _ = try await api.devices(.init(baseURL: "https://lumina.invalid", bearerToken: "secret"))
            throw SmokeError.failed("malformed list envelope was accepted")
        } catch APIError.invalidResponse {
            // Expected: a malformed payload must not masquerade as an empty home.
        }

        MockURLProtocol.handler = { _ in
            (400, #"{"error":{"message":"Invalid scene","details":["Track 0: first keyframe offsetMs must be 0"]}}"#)
        }
        do {
            try await api.health(.init(baseURL: "https://lumina.invalid", bearerToken: "secret"))
            throw SmokeError.failed("Hub validation error was accepted")
        } catch let APIError.server(_, message) {
            try require(message.contains("first keyframe"), "Hub error details were discarded")
        }

        print("LuminaCore smoke passed")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw SmokeError.failed(message) }
    }
}

private enum SmokeError: LocalizedError {
    case failed(String)
    var errorDescription: String? {
        if case let .failed(message) = self { return message }
        return nil
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
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}
