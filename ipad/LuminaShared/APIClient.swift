import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum APIError: LocalizedError, Equatable {
    case invalidBaseURL
    case invalidResponse
    case server(status: Int, message: String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL: "Hub 地址必须以 http:// 或 https:// 开头"
        case .invalidResponse: "Hub 返回了无效响应"
        case let .server(status, message): "\(message)（HTTP \(status)）"
        case let .decoding(message): "无法读取 Hub 数据：\(message)"
        }
    }
}

actor LuminaAPIClient {
    static let shared = LuminaAPIClient()

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(session: URLSession = .shared) {
        self.session = session
        decoder = JSONDecoder()
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
    }

    func health(_ connection: HubConnection) async throws {
        _ = try await request(connection, path: "/api/v1/health")
    }

    func devices(_ connection: HubConnection) async throws -> [Device] {
        try decodeList(try await request(connection, path: "/api/v1/devices"), key: "devices")
    }

    func modes(_ connection: HubConnection) async throws -> [LightMode] {
        try decodeList(try await request(connection, path: "/api/v1/modes"), key: "modes")
    }

    func scenes(_ connection: HubConnection) async throws -> [Scene] {
        try decodeList(try await request(connection, path: "/api/v1/scenes"), key: "scenes")
    }

    func runs(_ connection: HubConnection) async throws -> [RunInfo] {
        try decodeList(try await request(connection, path: "/api/v1/runs"), key: "runs")
    }

    func discover(_ connection: HubConnection) async throws {
        _ = try await request(connection, path: "/api/v1/discovery", method: "POST", body: EmptyBody())
    }

    func control(
        _ connection: HubConnection,
        deviceID: String,
        action: DeviceControlRequest
    ) async throws {
        _ = try await request(
            connection,
            path: "/api/v1/devices/\(pathComponent(deviceID))/control",
            method: "POST",
            body: action
        )
    }

    func controlMany(
        _ connection: HubConnection,
        deviceID: String,
        actions: [DeviceControlRequest]
    ) async throws {
        _ = try await request(
            connection,
            path: "/api/v1/devices/\(pathComponent(deviceID))/control-many",
            method: "POST",
            body: ActionList(actions: actions)
        )
    }

    func patch(_ connection: HubConnection, deviceID: String, patch: DevicePatch) async throws {
        _ = try await request(
            connection,
            path: "/api/v1/devices/\(pathComponent(deviceID))",
            method: "PATCH",
            body: patch
        )
    }

    func applyMode(_ connection: HubConnection, modeID: String, request body: ApplyModeRequest) async throws {
        let data = try await request(
            connection,
            path: "/api/v1/modes/\(pathComponent(modeID))/apply",
            method: "POST",
            body: body
        )
        let object = try jsonObject(from: unwrap(data))
        let failures = (object["results"] as? [[String: Any]] ?? []).compactMap { item -> String? in
            guard item["status"] as? String == "failed" else { return nil }
            return item["error"] as? String ?? "模式应用失败"
        }
        if !failures.isEmpty { throw APIError.server(status: 502, message: failures.joined(separator: "；")) }
    }

    func createScene(_ connection: HubConnection, scene: Scene) async throws -> Scene {
        let data = try await request(connection, path: "/api/v1/scenes", method: "POST", body: scene.normalized)
        return try decodeObject(data, key: "scene")
    }

    func updateScene(_ connection: HubConnection, scene: Scene) async throws -> Scene {
        let data = try await request(
            connection,
            path: "/api/v1/scenes/\(pathComponent(scene.id))",
            method: "PUT",
            body: scene.normalized
        )
        return try decodeObject(data, key: "scene")
    }

    func deleteScene(_ connection: HubConnection, sceneID: String) async throws {
        _ = try await request(
            connection,
            path: "/api/v1/scenes/\(pathComponent(sceneID))",
            method: "DELETE"
        )
    }

    func runScene(_ connection: HubConnection, sceneID: String) async throws -> RunInfo {
        let data = try await request(
            connection,
            path: "/api/v1/scenes/\(pathComponent(sceneID))/run",
            method: "POST",
            body: EmptyBody()
        )
        return try decodeObject(data, key: "run")
    }

    func stopRun(_ connection: HubConnection, runID: String) async throws {
        _ = try await request(
            connection,
            path: "/api/v1/runs/\(pathComponent(runID))/stop",
            method: "POST",
            body: EmptyBody()
        )
    }

    private func request(
        _ connection: HubConnection,
        path: String,
        method: String = "GET"
    ) async throws -> Data {
        try await request(connection, path: path, method: method, encodedBody: nil)
    }

    private func request<Body: Encodable>(
        _ connection: HubConnection,
        path: String,
        method: String,
        body: Body
    ) async throws -> Data {
        try await request(connection, path: path, method: method, encodedBody: try encoder.encode(body))
    }

    private func request(
        _ connection: HubConnection,
        path: String,
        method: String,
        encodedBody: Data?
    ) async throws -> Data {
        let connection = connection.normalized
        let rawBase = connection.baseURL
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard (rawBase.hasPrefix("http://") || rawBase.hasPrefix("https://")),
              let url = URL(string: rawBase + path) else { throw APIError.invalidBaseURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !connection.bearerToken.isEmpty {
            request.setValue("Bearer \(connection.bearerToken)", forHTTPHeaderField: "Authorization")
        }
        if !connection.cloudflareClientID.isEmpty {
            request.setValue(connection.cloudflareClientID, forHTTPHeaderField: "CF-Access-Client-Id")
        }
        if !connection.cloudflareClientSecret.isEmpty {
            request.setValue(connection.cloudflareClientSecret, forHTTPHeaderField: "CF-Access-Client-Secret")
        }
        if let encodedBody {
            request.httpBody = encodedBody
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard 200..<300 ~= http.statusCode else {
            throw APIError.server(status: http.statusCode, message: errorMessage(data) ?? "Hub 请求失败")
        }
        return data
    }

    private func decodeList<T: Decodable>(_ data: Data, key: String) throws -> [T] {
        do {
            let payload = try unwrap(data)
            if let array = payload as? [Any] {
                return try decoder.decode([T].self, from: JSONSerialization.data(withJSONObject: array))
            }
            if let object = payload as? [String: Any], let array = object[key] {
                return try decoder.decode([T].self, from: JSONSerialization.data(withJSONObject: array))
            }
            throw APIError.invalidResponse
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.decoding(error.localizedDescription)
        }
    }

    private func decodeObject<T: Decodable>(_ data: Data, key: String) throws -> T {
        do {
            let payload = try unwrap(data)
            let value = (payload as? [String: Any])?[key] ?? payload
            return try decoder.decode(T.self, from: JSONSerialization.data(withJSONObject: value))
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.decoding(error.localizedDescription)
        }
    }

    private func unwrap(_ data: Data) throws -> Any {
        let root = try JSONSerialization.jsonObject(with: data)
        if let object = root as? [String: Any], let data = object["data"] { return data }
        return root
    }

    private func jsonObject(from value: Any) throws -> [String: Any] {
        guard let object = value as? [String: Any] else { throw APIError.invalidResponse }
        return object
    }

    private func errorMessage(_ data: Data) -> String? {
        guard let envelope = try? decoder.decode(ErrorEnvelope.self, from: data) else { return nil }
        let summary = envelope.error.message
        let details = envelope.error.details ?? []
        let detailText = details.joined(separator: "；")
        return details.isEmpty ? summary : "\(summary)：\(detailText)"
    }

    private func pathComponent(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#[]@!$&'()*+,;=")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

private struct EmptyBody: Codable {}
private struct ActionList: Codable { let actions: [DeviceControlRequest] }
private struct ErrorEnvelope: Decodable { let error: ErrorPayload }
private struct ErrorPayload: Decodable {
    let message: String
    let details: [String]?
}
